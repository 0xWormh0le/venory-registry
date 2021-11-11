// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CallTargetMock {
    uint256 public nonce;

    function increase() external {
        nonce += 1;
    }
}
