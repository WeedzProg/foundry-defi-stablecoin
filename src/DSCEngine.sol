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

//import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
//import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * @title Decentralized Stable Coin Engine
 * @Author Hei02
 * @notice Exogenous stable coin collatarilezed by wETH and wBTC
 * @Property Minting: algorithmic minting
 * @Property Pegging: 1:1 with USD
 * @Property Collateral: wETH and wBTC
 *
 *
 * @dev This is a decentralized stable coin that is collateralized by crypto assets
 *
 * @important it should always be overcollateralized to avoid liquidation and maintain a ratio of all collateral superior to all DSC in circulation
 *
 * @notice This contract implement the logic of the DSCEngine contract, that rules the Decentralized Stable Coin token logics.
 * Designed to maintain 1$ pegged by using a collateralized algorithmic minting and burning mechanism on top of weth and wbtc.
 *
 * @notice similar to the dai token if it was not managed by a centralized entity and without fees.
 */

//DecentralizedStableCoin, Ownable, ERC20Burnable,
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////

    //Amount Sanitizer errors
    error DSCEngine__AmountMustBeMoreThanZero();

    //constructor errors
    error DSCEngine__CollateralAndPriceFeedArraysMustBeSameLength();

    //token not allowed for collateral
    error DSCEngine__CollateralTokenNotAllowed();

    // transfer deposit failed
    error DSCEngine__DepositTransferFailed();

    // Health Factor broken
    error DSCEngine__HealthFactorBroken(uint256 healthFactor);

    // DSC mint failed
    error DSCEngine__DscMintFailed();

    // Withdraw transfer failed More Than Collateral Balance is being Withdraw
    error DSCEngine__WithdrawTransferFailedMoreThanCollateralBalance();

    // Transfert failed for burning DSC
    error DSCEngine__TransfertFailedForBurningDSC();

    // Health Factor is above min thresold checker for liquidation
    error DSCEngine__HealthFactorIsAboveMinThresold();

    // Health Factor not improved after liquidation
    error DSCEngine__HealthFactorLiquidationNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////

    // instead of doing address to bool, use pricefeed to check if the token is a collateral and its value if it is.
    // So address to address checker using the latest solidity mapping version => can name pointers.
    // mapping(address => bool) public collateralTokenAddressChecker;
    mapping(address tokens => address priceFeed) private s_tokenToPriceFeed;

    mapping(address user => mapping(address collateral => uint256 amount))
        private s_collateralBalances;
    mapping(address user => uint256 amountOfMintedDSC) private s_mintedDSCBalances;
    mapping(address => uint256) public liquidationBalances;

    //array of collateral token addresses
    address[] private s_collateralTokenAddresses;

    // DscToken variable is the DSC token that is minted and burned by this contract
    DecentralizedStableCoin private i_dscToken;

    //decimals precision for pricefeed calculation
    uint256 private constant s_decimalsPrecision = 1e10;
    uint256 private constant s_precision = 1e18;

    // Liquidation Threshold, 200% overcollateralized ratio
    uint256 private constant s_liquidationThreshold = 50;
    uint256 private constant s_liquidationPrecision = 100;
    uint256 private constant s_minHealthFactor = 1e18;
    uint256 private constant s_liquidationBonus = 10; // 10% bonus for liquidators

    ///////////////////
    // Events
    ///////////////////

    event DepositCollateral(
        address indexed user,
        address indexed tokenCollateralAddress,
        uint256 indexed amount
    );

    // event CollateralRedeemed(
    //     address indexed user,
    //     address indexed tokenCollateralAddress,
    //     uint256 indexed amount
    // );

    //updated version of the event above
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amount
    );

    ///////////////////
    // Modifiers
    ///////////////////

    // Amount sanitizer modifier
    modifier AmountChecker(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier AllowedCollateral(address tokenCollateralAddress) {
        if (s_tokenToPriceFeed[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__CollateralTokenNotAllowed();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(
        address[] memory tokenCollateralAddresses,
        address[] memory tokenPriceFeedAddresses,
        address dsctokenAddress
    ) {
        if (tokenCollateralAddresses.length != tokenPriceFeedAddresses.length) {
            revert DSCEngine__CollateralAndPriceFeedArraysMustBeSameLength();
        }
        // USD price feed for ETH and BTC
        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_tokenToPriceFeed[tokenCollateralAddresses[i]] = tokenPriceFeedAddresses[i];
            s_collateralTokenAddresses.push(tokenCollateralAddresses[i]);
        }
        i_dscToken = DecentralizedStableCoin(dsctokenAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /*
     * @notice deposit collateral and mint DSC, it combined two functions in one transaction
     *
     * @param tokenCollateralAddress the address of the collateral token to deposit
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDSCToMint the amount of DSC to mint
     *
     */
    function depositCollateralAndMint(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice burnDSC and withdraw collateral, it combined two functions in one transaction
     *
     * @param tokenCollateralAddress the address of the collateral token
     * @param amount the amount of collateral
     * @param amountDSCToBurn the amount of DSC to burn
     *
     */
    function burnDSCAndWithdrawCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //checking Health Factor ratio within redeemCollateral function
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice deposit collateral to mint DSC
     *
     * @param tokenCollateralAddress the address of the collateral token to deposit
     * @param amount the amount of collateral to deposit
     *
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amount
    ) public AmountChecker(amount) AllowedCollateral(tokenCollateralAddress) nonReentrant {
        s_collateralBalances[msg.sender][tokenCollateralAddress] += amount;
        emit DepositCollateral(msg.sender, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) {
            revert DSCEngine__DepositTransferFailed();
        }
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice mint DSC by depositing collateral
     *
     * @param amountToBeMint the amount of DSC to mint
     *  Require to check the value of the collateral against the value of the Dsc Token
     *  deposited values need to be superior
     *  When minting, in a way users are minting a debt
     */
    function mintDSC(uint256 amountToBeMint) public AmountChecker(amountToBeMint) nonReentrant {
        // revert minting if minting more than the secured Health Factor threshold,
        // avoid automatic liquidation by minting too much
        s_mintedDSCBalances[msg.sender] += amountToBeMint;
        _revertIfMintingMoreThanHealthFactor(msg.sender);

        bool minted = i_dscToken.mint(msg.sender, amountToBeMint);
        if (!minted) {
            revert DSCEngine__DscMintFailed();
        }
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice Withdraw collateral by burning DSC
     *
     * @param tokenCollateralAddress, the address of the collateral token to withdraw
     * @param amountCollateral, the amount of collateral to withdraw
     *
     *  require to check the value of the collateral against the value of the Dsc Token
     *  require to check health factor to be superior to 1 after collateral being pulled out
     *  require to burn DSC for the collateral to be pulled out if needed
     *  When withdrawing, in a way users are paying back their debt
     *  Avoid liquidation by withdrawing too much
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public AmountChecker(amountCollateral) nonReentrant {
        // Avoid users to redeem more than their collateral
        // /!/ Updated /!/ 18.Dec.2023
        // s_collateralBalances[msg.sender][tokenCollateralAddress] -= amountCollateral;
        // emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);

        // bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        // if (!success) {
        //     revert DSCEngine__WithdrawTransferFailedMoreThanCollateralBalance();
        // }

        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        // then check Health Factor and revert if it is about to be under 1
        _revertIfMintingMoreThanHealthFactor(msg.sender);
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice Burn DSC by withdrawing collateral / Repaying the debt
     *
     * @param DSCamount, the amount of DSC to burn
     *
     * require to check the DSC balance of the user
     *
     */
    function burnDSC(uint256 DSCamount) public AmountChecker(DSCamount) {
        // /!/ Updated  for liquidation system /!/ 18.Dec.2023
        // s_mintedDSCBalances[msg.sender] -= DSCamount;
        // bool burned = i_dscToken.transferFrom(msg.sender, address(this), DSCamount);
        // if (!burned) {
        //     revert DSCEngine__TransfertFailedForBurningDSC();
        // }

        // i_dscToken.burn(DSCamount);
        _burnDSC(DSCamount, msg.sender, msg.sender);

        //Just in case, I don't think the below check about healthfactor is nessesary
        _revertIfMintingMoreThanHealthFactor(msg.sender);
    }

    /*
     * @notice Follows CEI pattern, Checks Effects Interactions
     * @notice Liquidate position of users if health factor is under 1
     *
     * @notice Can only liquidate if the position is still overcollateralized
     * @exemple if a user repay $50 to get back $20 it abort, $50 is the debt and $20 is the value left of the position
     * @notice which led to a known bug, that we can't incentivize liquidators to liquidate undercollateralized positions
     *
     *
     * @param tokenCollateralAddress, the address of the collateral token to use for recovering the debt
     * @param user, the address of the user to liquidate
     * @param debtToCover, the amount of debt to cover
     *
     * @dev liquidation is a process where the collateral of a user is sold to repay the debt of another user
     * @dev by doing so the user who repaid the debt gets the collateral of the user who got liquidated
     * @dev partial liquidation is possible
     */
    function liquidate(
        address tokenCollateralAddress,
        address user,
        uint256 debtToCover
    ) external AmountChecker(debtToCover) nonReentrant {
        // check if user is liquidatable
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= s_minHealthFactor) {
            revert DSCEngine__HealthFactorIsAboveMinThresold();
        }

        // Burn DSC from the liquidator
        // Take the collateral from the liquidated user
        // Give the collateral to the liquidator

        // Let say user to be liquidated as $140 of Eth, and $100 of DSC minted
        // debt to cover is $100
        // Need to calculate the value of the Eth amount in USD to use for recovering the debt

        //(10e18 * 1e18) / (2000e8 * 1e8) = 5e18
        uint256 tokenAmount = getTokenValueFromUsd(tokenCollateralAddress, debtToCover);
        // give a 10% bonus to the liquidator worth of the asset that they liquidate
        // 5e18 * 1.1 = 5.5e18
        uint256 bonusAmount = (tokenAmount * s_liquidationBonus) / s_liquidationPrecision;
        uint256 totalCollateralToRedeem = tokenAmount + bonusAmount;
        // should implement a feature in case the protocol is insolvent for rewarding the bonus
        // and sweep extra amounts into a treasury

        // check if the liquidator has enough collateral to cover the debt
        // redeem the collateral and burn the DSC
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);

        // Can liquidate ourselves and get 10% bonus ??
        // Burn DSC
        _burnDSC(debtToCover, user, msg.sender);

        // check health factor after liquidation
        uint256 endingHealthFactor = _healthFactor(user);

        //the below will be too expensive in gas vs reward for liquidators
        // if(endingHealthFactor < s_minHealthFactor) {
        //     // if health factor is still under 1, liquidate again
        //     liquidate(tokenCollateralAddress, user, debtToCover);
        // }

        if (endingHealthFactor <= s_minHealthFactor) {
            // better to revert i guess instead of relaunching a liquidation in an indefinite loop until it has nothing more to liquidate.
            // too expensive in gas
            revert DSCEngine__HealthFactorLiquidationNotImproved();
        }

        // revert also if the health factor of the liquidator gets broken
        _revertIfMintingMoreThanHealthFactor(msg.sender);
    }

    ///////////////////
    // Private Internal View Functions
    ///////////////////

    /**
     * @notice get the total value of the collateral and the total value of the DSC from an user
     *
     *
     * @return totalDSCMinted
     * @return totalCollateralValue
     */

    function _getTotalCollateralAndDSCValueOfUsers(
        address user
    ) private view returns (uint256 totalDSCMinted, uint256 totalCollateralValue) {
        totalDSCMinted = s_mintedDSCBalances[user];

        totalCollateralValue = getTotalCollateralValueOfUsers(user);
    }

    /**
     *
     * @param user the address of the user to get the health factor of
     * @return the health factor of the user
     *
     * @notice the health factor is the ratio of the value of the collateral to the value of the DSC
     * If it gets under 1, user might be liquidated
     *
     * There is actually a bug in here, figure it out !
     */
    function _healthFactor(address user) private view returns (uint256) {
        // get the TOTAL value of collaterals
        // get Total amount of DSC minted
        (
            uint256 totalCollateralValue,
            uint256 totalDSCValue
        ) = _getTotalCollateralAndDSCValueOfUsers(user);

        // health factor liquidation threshold is double of the size of the collateral value
        uint256 collateralAdjustedForThreshold = (totalCollateralValue * s_liquidationThreshold) /
            s_liquidationPrecision;

        // $1000 eth * 50 Health Factor pricision (200%)
        // = 50,000 / 100 DSC minted = 500 healthfactor / 100 liquidation precision = 5
        // 5 > 1 ----> no liquidation

        // $150 eth / 100 DSC = 1.5
        // 150 eth * 50 Health Factor pricision (200%)
        // = 7500 / 100 DSC minted = (75 healthfactor / 100 liquidation precision) < 1 ----> liquidation

        // $1000 of eth deposited, 100 DSC minted
        // 1000 * 50 Health Factor pricision (200%) / 100 DSC minted = (500 healthfactor / 100 liquidation precision) = 5
        // 5 > 1 ----> Health Factor above 1, no liquidation
        return (collateralAdjustedForThreshold * s_precision) / totalDSCValue;
    }

    /**
     *
     * @param user check the user address that is minting
     *
     * @notice revert if the health factor after minting is under 1
     * @notice it checks if collateral is enough, and revert if not
     */
    function _revertIfMintingMoreThanHealthFactor(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < s_minHealthFactor) {
            revert DSCEngine__HealthFactorBroken(userHealthFactor);
        }
        // get the value of the collateral
        // get the value of the DSC
        // compare the value of the collateral to the value of the DSC
        // if the value of the collateral is superior to the value of the DSC, then mint
        // if the value of the collateral is inferior to the value of the DSC, then revert
    }

    /**
     *
     * @param tokenCollateralAddress the address of the collateral token to withdraw
     * @param amount the amount of collateral to withdraw
     * @param from the address of the user to withdraw from
     * @param to the address of the user to withdraw to
     *
     * @notice redeem system re-arranged for being usable when liquidating
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amount,
        address from,
        address to
    ) private {
        // check if the user has enough collateral to redeem
        // check if the user has enough DSC to burn
        // redeem the collateral
        // burn the DSC

        // Avoid users to redeem more than their collateral
        s_collateralBalances[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) {
            revert DSCEngine__WithdrawTransferFailedMoreThanCollateralBalance();
        }

        // then check Health Factor and revert if it is about to be under 1
        _revertIfMintingMoreThanHealthFactor(msg.sender);
    }

    /**
     *
     * @param DSCamount the amount of DSC to burn
     * @param onBehalfOf the address of the user for who liquidator are burning for
     * @param dscFrom the address of the user to burn from
     *
     * @notice Burn DSC re-arranged for when liquidating
     * @dev Low-level internal function, do not call unless it is checking if health factor breaks / being broken
     */
    function _burnDSC(
        uint256 DSCamount,
        address onBehalfOf,
        address dscFrom
    ) public AmountChecker(DSCamount) {
        s_mintedDSCBalances[onBehalfOf] -= DSCamount;
        bool burned = i_dscToken.transferFrom(dscFrom, address(this), DSCamount);
        if (!burned) {
            revert DSCEngine__TransfertFailedForBurningDSC();
        }

        i_dscToken.burn(DSCamount);
    }

    ///////////////////
    // Getters Functions
    // Public & External View Functions
    ///////////////////
    function getHealthFactor() public view {}

    function getTotalCollateralValueOfUsers(address user) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < s_collateralTokenAddresses.length; i++) {
            //totalCollateralValue += s_collateralBalances[user][s_collateralTokenAddresses[i]];
            address token = s_collateralTokenAddresses[i];
            uint256 amount = s_collateralBalances[user][token];
            totalCollateralValue += amount * getPriceFeedValue(token, amount);
        }
        return totalCollateralValue;
    }

    function getPriceFeedValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);

        //(, int256 price, , , ) = priceFeed.latestRoundData();
        // change latestRoundData for the library that contains the token heartbeat checker and check if price is stale
        (, int256 price, , , ) = priceFeed.stalePriceFeedCheck();

        // let say eth is $1000
        // returned value will be using eth with 8 decimals
        // so 1000 * 10e8
        return ((uint256(price) * s_decimalsPrecision) * amount) / s_precision;
    }

    function getTokenValueFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        // USD amount in wei divided by the price of the token
        // 100 usd / 2000 usd per eth = 0.05 eth
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        //(, int256 price, , , ) = priceFeed.latestRoundData();
        // change latestRoundData for the library that contains the token heartbeat checker and check if price is stale
        (, int256 price, , , ) = priceFeed.stalePriceFeedCheck();

        //(10e18 * 1e18) / (2000e8 * 1e8) = 5e18
        return (usdAmountInWei * s_precision) / (uint256(price) * s_decimalsPrecision);
    }

    function getTotalCollateralAndDSCValueOfUsers(
        address user
    ) external view returns (uint256 totalDSCMinted, uint256 totalCollateralValue) {
        (totalDSCMinted, totalCollateralValue) = _getTotalCollateralAndDSCValueOfUsers(user);
    }

    function getAllcollateralTokenAddresses() external view returns (address[] memory) {
        return s_collateralTokenAddresses;
    }

    function getCollateralTokentsOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralBalances[user][token];
    }
}
