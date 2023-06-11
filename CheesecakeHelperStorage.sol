// SPDX-FileCopyrightText: 2022 Toucan Labs
//
// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract CheesecakeHelperStorage is OwnableUpgradeable {
    // token symbol => token address
    mapping(string => address) public eligibleTokenAddresses;
    address public contractRegistryAddress =
        0x48E04110aa4691ec3E9493187e6e9A3dB613e6e4; //as described https://app.toucan.earth/contracts#celo-alfajores > 0x10613Ef66846ba7c07834665c1292CAC53081276
    address public sushiRouterAddress =
        0x5615CDAb10dc425a742d643d949a7F474C01abc4; //Uniswap v3 router
        //0xE3D8bd6Aed4F159bc8000a9cD47CffDb95F96121; //Ubeswap router
    // user => (token => amount)
    mapping(address => mapping(address => uint256)) public balances;
}