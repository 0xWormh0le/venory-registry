// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "hardhat/console.sol";
import "./Utils.sol";
import "./IRegistry.sol";


contract Registry is IRegistry, ERC721URIStorage {
    /// @dev mapping of user to signature verification nonce
    mapping(address => uint256) nonces;

    /// @dev mapping from service name to service
    mapping(string => Service) public services;

    /// @dev total supply
    uint256 public totalSupply;

    uint256 constant public OPERATION_CALL = 0;
    uint256 constant public OPERATION_CREATE = 1;
    uint256 constant public OPERATION_CREATE2 = 2;
    uint256 constant public OPERATION_STATIC_CALL = 3;
    uint256 constant public OPERATION_DELEGATE_CALL =4;

    constructor(string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    { }

    receive() external payable { }

    function _baseURI() internal pure override returns (string memory) {
        return "https://ipfs.io/ipfs/";
    }

    /// @dev Allows user to register IPFS hash of some underlying document or folder as a new NFT
    /// @param _hash IPFS hash
    /// @return tokenId newly minted token id
    function registerAsset(string memory _hash) external override returns(uint256 tokenId) {
        tokenId = totalSupply;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(totalSupply, _hash);
        totalSupply += 1;

        emit AssetRegistered(msg.sender, _hash, tokenId);
    }

    /// @dev Allows user to register a service that has name , points to a collection of NFT and address of EOA
    /// @param _name service name
    /// @param _tokenIds array of NFT ids
    /// @param _eoa address of EOA
    function registerService(string memory _name, uint256[] memory _tokenIds, address _eoa) external override {
        require(bytes(_name).length > 0, "Registry: invalid service name");
        require(_eoa != address(0), "Registry: invalid eoa address");

        Service storage service = services[_name];

        require(service.eoa == address(0), "Registry: service already registered");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(_tokenIds[i] < totalSupply, "Registry: invalid token id");
        }

        service.eoa = _eoa;
        service.tokenIds = _tokenIds;

        emit ServiceRegistered(msg.sender, _name, _tokenIds, _eoa);
    }

    /// @dev ERC725X standard: executes a call on any other smart contracts, transfers native token, or deployes a new smart contract
    ///      after checking the tx is signed by the EOA which is registered for the service.
    ///      Only callable by contract owner
    /// @param _operation operation to execute. any of 0: call, 1: create, 2: create2, 3: staticcall and 4: delegatecall
    /// @param _to the smart contract or address to interact with. This will be unused if a contract is created (operation 1 and 2)
    /// @param _value the value of native token (ETH) to transfer
    /// @param _data the call data, or the contract data to deploy
    /// @param _serviceName service name
    /// @param _signature signature
    /// @return result the returned data of the called function, or the address of the contract created (operation 1 and 2)
    function execute(
        uint256 _operation,
        address _to,
        uint256 _value,
        bytes calldata _data,
        string memory _serviceName,
        bytes memory _signature
    ) external payable override returns(bytes memory result) {
        address signer = services[_serviceName].eoa;

        require(signer != address(0), "Registry: unregistered service");

        // if tx is sent directly from eoa, it's okay
        // if not, we verify using signature
        if (signer != msg.sender) {
            bytes32 message = keccak256(abi.encodePacked(
                _operation,
                _to,
                _value,
                _data,
                _serviceName,
                nonces[signer]
            ));
            nonces[signer] += 1;
            require(Utils.recoverSigner(message, _signature) == signer, "Registry: invalid signature");
        }

        uint256 gas = gasleft() - 2500;

        if (_operation == OPERATION_CALL) {
            result = executeCall(_to, _value, _data, gas);
            emit Executed(_operation, _to, _value, _data);

        } else if (_operation == OPERATION_CREATE) {
            address contractAddress = performCreate(_value, _data);
            result = abi.encodePacked(contractAddress);
            emit ContractCreated(_operation, contractAddress, _value);

        } else if (_operation == OPERATION_CREATE2) {
            address contractAddress = performCreate2(_value, _data);
            result = abi.encodePacked(contractAddress);
            emit ContractCreated(_operation, contractAddress, _value);

        } else if (_operation == OPERATION_STATIC_CALL) {
            result = executeStaticCall(_to, _data, gas);
            emit Executed(_operation, _to, _value, _data);

        } else if (_operation == OPERATION_DELEGATE_CALL) {
            result = executeDelegateCall(_to, _data, gas);
            emit Executed(_operation, _to, _value, _data);

        } else {
            revert('Registry: invalid operation type');
        }
    }

    function executeCall(
        address _to,
        uint256 _value,
        bytes memory _data,
        uint256 _gas
    ) internal returns (bytes memory) {

        (bool success, bytes memory result) = _to.call{gas: _gas, value: _value}(_data);

        if (!success) {
            if (result.length < 68) {
                revert();
            }
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

        return result;
    }
    
    function executeDelegateCall(
        address _to,
        bytes memory _data,
        uint256 _gas
    ) internal returns (bytes memory) {

        (bool success, bytes memory result) = _to.delegatecall{gas: _gas}(_data);

        if (!success) {
            if (result.length < 68) {
                revert();
            }
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

        return result;
    }

    function executeStaticCall(
        address _to,
        bytes memory _data,
        uint256 _gas
    ) internal returns (bytes memory) {

        (bool success, bytes memory result) = _to.staticcall{gas: _gas}(_data);

        if (!success) {
            if (result.length < 68) {
                revert();
            }
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

        return result;
    }

    function performCreate(
        uint256 _value,
        bytes memory _data
    ) internal returns (address newContract) {

        assembly {
            newContract := create(_value, add(_data, 0x20), mload(_data))
        }

        require(newContract != address(0), "Registry: could not deploy contract");
    }

    function performCreate2(
        uint256 _value,
        bytes memory _data
    ) internal returns (address newContract) {
        bytes32 salt = Utils.toBytes32(_data, _data.length - 32);
        bytes memory data = Utils.slice(_data, 0, _data.length - 32);

        newContract = Create2.deploy(_value, salt, data);
        require(newContract != address(0), "Registry: could not deploy contract");
    }
}
