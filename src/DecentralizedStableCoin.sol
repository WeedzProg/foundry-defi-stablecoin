// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title Decentralized Stable Coin
 * @Author Hei02
 * @notice Exogenous stable coin collatarilezed by wETH and wBTC
 * @Property Minting: algorithmic minting
 * @Property Pegging: 1:1 with USD
 * @Property Collateral: wETH and wBTC
 *
 *
 * @dev This is a decentralized stable coin that is collateralized by crypto assets
 *
 * This contract is the ERC20 implementation of the stable coin token. It is ruled by the logic of the DSCEngine contract.
 *
 */

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__CantBurnMoreThanBalance();
    error DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
    error DecentralizedStableCoin__MintAmountMustBeMoreThanZero();
    error DecentralizedStableCoin__CantMintToAddressZero();

    constructor() ERC20("Decentralized Stable Coin", "DSC") {
        //_mint(msg.sender, 1000000000000000000000000000);
        _mint(msg.sender, 1000);
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount > balance) {
            revert DecentralizedStableCoin__CantBurnMoreThanBalance();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__BurnAmountMustBeMoreThanZero();
        } else {
            super.burn(_amount);
            //_burn(msg.sender, _amount);
        }
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MintAmountMustBeMoreThanZero();
        }
        if (_to == address(0)) {
            revert DecentralizedStableCoin__CantMintToAddressZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
