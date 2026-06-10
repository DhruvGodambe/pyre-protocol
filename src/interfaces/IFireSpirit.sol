// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFireSpirit {
    enum Stage {
        EMBER,
        FLAME,
        FORGE,
        PYRE
    }

    function stageOf(address account) external view returns (Stage);

    function walletToTokenId(address wallet) external view returns (uint256);
}
