// SPDX-License-Identifier: MIT

// narrow down the way we call functions
// like we always need to approve token for deposit
// we always need a check before liquidation
// etc...

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin public stablecoin;
    DSCEngine dscEngine_contract;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // so we dont overflow 256 bytes if we do +1 to this massive number and get a revert
    //ghost variables
    uint256 public breakpointChecker = 0;

    address[] public usersWithDeposits;

    MockV3Aggregator public wethUsdPriceFeed;

    constructor(DSCEngine _dscEngine_contract, DecentralizedStableCoin _stablecoin) {
        dscEngine_contract = _dscEngine_contract;
        stablecoin = _stablecoin;

        address[] memory tokenCollateralAddresses = dscEngine_contract
            .getAllcollateralTokenAddresses();
        weth = ERC20Mock(tokenCollateralAddresses[0]);
        wbtc = ERC20Mock(tokenCollateralAddresses[1]);

        // pricefeed

        // Broke the below line after changing latestRoundData by the stale price check on DSCengine
        // it iis the latest change of the contract of DSCengine
        // wethUsdPriceFeed = MockV3Aggregator(dscEngine_contract.getPriceFeedValue(address(weth), 1));
    }

    // can redeem only if deposits has been made.
    // so to not waste calls we need to first call deposits before redeem
    // that is why the handler contract is required for fuzz test. to keep a certain logic in tests
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // deposit collateral
        //dscEngine_contract.depositCollateral(collateralSeed, amountCollateral);

        // deposit collateral by restricting usable collaterals addresses to only weth and wbtc
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        //bound amount between 1 and a max number to avoid 0 deposits. not good to do everytime
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        //prank msg.sender to mint and approve tokens for deposits
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine_contract), amountCollateral);

        dscEngine_contract.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // will push twice, should check the array if the user is already existing
        usersWithDeposits.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // only valid collateral to use for redeeming is weth and wbtc
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        // can redeem only the max amount of collateral deposited
        uint256 maxRedeemableCollateral = dscEngine_contract.getCollateralTokentsOfUser(
            address(collateral),
            msg.sender
        );

        //bound
        amountCollateral = bound(amountCollateral, 0, maxRedeemableCollateral);
        // if amount of collateral is zero discard the run and try a new one
        if (amountCollateral == 0) {
            return;
        }
        //redeem
        dscEngine_contract.redeemCollateral(address(collateral), amountCollateral);
        //breakpointChecker += 1;
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        //only depositor can mint
        if (usersWithDeposits.length == 0) {
            return;
        }
        address depositor = usersWithDeposits[addressSeed % usersWithDeposits.length];
        //mint dsc
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = dscEngine_contract
            .getTotalCollateralAndDSCValueOfUsers(depositor);
        int256 dscToMint = (int256(totalCollateralValue) / 2) - int256(totalDSCMinted);
        if (dscToMint < 0) {
            return;
        }
        amountDsc = bound(amountDsc, 0, uint256(dscToMint));
        if (amountDsc < 0) {
            return;
        }
        vm.startPrank(depositor);
        dscEngine_contract.mintDSC(amountDsc);
        vm.stopPrank();
        breakpointChecker += 1;
    }

    // break invariants if price spikes down in second
    function collateralUsdValueUpdate(uint96 newPrice) public {
        int256 newPriceUpdate = int256(uint256(newPrice));
        wethUsdPriceFeed.updateAnswer(newPriceUpdate);
    }

    // only allow test to choose between only between Weth and Webtc tokens for deposits
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
