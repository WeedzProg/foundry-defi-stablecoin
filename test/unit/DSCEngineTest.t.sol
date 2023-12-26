// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    // Load contracts
    DeployDecentralizedStableCoin deployer;
    DecentralizedStableCoin dsc_contract;
    DSCEngine dscEngine_contract;
    HelperConfig helperConfig;

    // Set up test variables
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_WETH_BALANCE = 20 ether;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        (dsc_contract, dscEngine_contract, helperConfig) = deployer.run();

        // pricefeed
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = helperConfig.activeNetworkConfig();

        //user setup
        ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
    }

    //////////////////////////
    // Constructor Tests    //
    //////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    //token addresses test, wbtc and weth
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        //address[] memory tokenAddresses = new address[](2);
        //address[] memory priceFeedAddresses = new address[](1);

        //tokenAddresses = [weth, wbtc];

        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__CollateralAndPriceFeedArraysMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc_contract));
    }

    //////////////////////////
    // PriceFeed Tests      //
    //////////////////////////

    function testGetUsdValue() public {
        uint256 EthAmount = 12 ether;
        uint256 EthPrice = 2000; // this won't work for real price feeds when testing on Sepolia
        uint256 expected = EthAmount * EthPrice;
        uint256 actual = dscEngine_contract.getPriceFeedValue(weth, EthAmount);
        assertEq(expected, actual);
    }

    function testGetTokenValueFromUsd() public {
        uint256 UsdAmount = 100 ether; // 100 USD
        uint256 EthPrice = 2000; // this won't work for real price feeds when testing on Sepolia
        uint256 expected = UsdAmount / EthPrice;
        uint256 actual = dscEngine_contract.getTokenValueFromUsd(weth, UsdAmount);
        assertEq(expected, actual);
    }

    //////////////////////////
    // Deposit Tests        //
    //////////////////////////

    // Test when no collateral has been deposited yet
    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine_contract), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeMoreThanZero.selector);
        dscEngine_contract.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testReversIfCollateralNotAllowed() public {
        //Mock a random ERC20 token
        ERC20Mock badToken = new ERC20Mock("BAD", "BAD", msg.sender, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralTokenNotAllowed.selector);
        dscEngine_contract.depositCollateral(address(badToken), 1);
        vm.stopPrank();
        //++gasSpent; // this is a workaround for a bug in the VM
    }

    modifier depositFromUser() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine_contract), AMOUNT_COLLATERAL);
        dscEngine_contract.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositWithoutMinting() public depositFromUser {
        (uint256 totalDSCMinted, uint256 totalCollateralUSD) = dscEngine_contract
            .getTotalCollateralAndDSCValueOfUsers(USER);
        uint256 expectedCollateralUsd = dscEngine_contract.getTokenValueFromUsd(
            weth,
            totalCollateralUSD
        );
        assertEq(totalDSCMinted, 0);
        assertEq(AMOUNT_COLLATERAL, expectedCollateralUsd);
    }

    //To do: Add a test for reentrant on deposit collateral
    // correct this test -> testDepositWithoutMinting
    // Test Events
    //90% + coverage target
    //3h14m fuzz test
}
