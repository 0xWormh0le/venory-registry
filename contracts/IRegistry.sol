// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRegistry {
    struct Service {
        address eoa;
        uint256[] tokenIds;
    }

    function registerAsset(string memory _hash) external returns(uint256 tokenId);

    function registerService(string memory _name, uint256[] memory _tokenIds, address _eoa) external;

    function execute(
        uint256 _operation,
        address _to,
        uint256 _value,
        bytes calldata _data,
        string memory _serviceName,
        bytes memory _signature
    ) external payable returns(bytes memory result);

    event AssetRegistered(address user, string ipfsHash, uint256 tokenId);

    event ServiceRegistered(address user, string serviceName, uint256[] tokenIds, address eoa);

    event Executed(uint256 indexed _operation, address indexed _to, uint256 indexed _value, bytes _data);

    event ContractCreated(uint256 indexed _operation, address indexed _contractAddress, uint256 indexed _value);

}
