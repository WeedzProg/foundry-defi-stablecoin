// SPDX-License-Identifier: MIT

// invariants. properties that should always hold.
// like cant deposit with 0
// like cant mint with 0
// like cant burn with 0
// healthfactor cant be 0
// healthfactor should always be under 1 for liquidation
// total value of collateral should always be more than total value of dsc / debt
// getter view function should never revert (called an evergreen invariant)
// etc...

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract OpeninvariantsTest is StdInvariant, Test {
    DeployDecentralizedStableCoin deployer;
    DecentralizedStableCoin public stablecoin;
    DSCEngine dscEngine_contract;
    HelperConfig helperConfig;
    Handler handler;

    address weth;
    address wbtc;

    address private USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_WETH_BALANCE = 20 ether;

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();
        (stablecoin, dscEngine_contract, helperConfig) = deployer.run();
        (, , weth, wbtc, ) = helperConfig.activeNetworkConfig();

        // mint weth to user
        //ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);

        //targetContract(address(dscEngine_contract));

        handler = new Handler(dscEngine_contract, stablecoin);
        targetContract(address(handler));
    }

    // the below function is initially a view function, but we deposit weth before checking amounts
    function invariant_protocolMustHaveMoreCollateralValueThanDSCSupply() public view {
        //vm.startPrank(USER);
        // approve user weth for deposit
        //IERC20(weth).approve(address(dscEngine_contract), 2 ether);
        //deposit 2weth from user
        //dscEngine_contract.depositCollateral(weth, 2 ether);
        //vm.stopPrank();

        // ## To have this test woring as perfection, delete prank and set initial mint to 0 in DSC contract ##

        // get the value of all the colletaral in the protocol
        // compare to all the DSC in the protocol

        uint256 totalSupply = stablecoin.totalSupply();
        uint256 totalWethInProtocol = IERC20(weth).balanceOf(address(dscEngine_contract));
        uint256 totalWbtcInProtocol = IERC20(wbtc).balanceOf(address(dscEngine_contract));

        uint256 totalWethValue = dscEngine_contract.getPriceFeedValue(weth, totalWethInProtocol);
        uint256 totalWbtcValue = dscEngine_contract.getPriceFeedValue(wbtc, totalWbtcInProtocol);

        console.log("Weth value in protocol: ", totalWethInProtocol);
        console.log("Wbtc value in protocol: ", totalWbtcInProtocol);
        console.log("Total supply: ", totalSupply);
        console.log("Breakpoint Checker: ", handler.breakpointChecker());

        assert(totalWethValue + totalWbtcValue >= totalSupply);
    }

    //invariant test should always test getters
    function invariant_getters() public view {
        dscEngine_contract.getCollateralTokentsOfUser(weth, USER);
        dscEngine_contract.getTotalCollateralAndDSCValueOfUsers(USER);
    }
}
