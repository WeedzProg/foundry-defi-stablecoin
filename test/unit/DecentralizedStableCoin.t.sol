//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract StableCoinTest is Test {
    DeployDecentralizedStableCoin deployer;
    DecentralizedStableCoin public stablecoin;
    //    DecentralizedStableCoin dsc_contract;
    DSCEngine dscEngine_contract;
    HelperConfig helperConfig;

    address private USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDecentralizedStableCoin();

        (stablecoin, dscEngine_contract, helperConfig) = deployer.run();
    }

    function testMintingNotOwner() public {
        vm.prank(USER);
        vm.deal(USER, 100 ether);
        vm.expectRevert();
        stablecoin.mint(USER, 100 ether);
    }

    function testMintOwner() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(address(USER), 100 ether);
        assertEq(stablecoin.balanceOf(address(USER)), 100 ether);
    }

    function testMintAmount() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(address(this), 100 ether);
        assertEq(stablecoin.balanceOf(address(this)), 100 ether);
    }

    function testMintZero() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        vm.expectRevert();
        stablecoin.mint(stableCoinOwner, 0);
    }

    function testCantMintToAddressZero() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        vm.expectRevert();
        stablecoin.mint(address(0), 100 ether);
    }

    function testBurnNotOwner() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(address(USER), 100 ether);
        vm.prank(USER);
        vm.expectRevert();
        stablecoin.burn(100 ether);
    }

    function testBurnZeroAmount() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(stableCoinOwner, 100 ether);
        vm.prank(stableCoinOwner);
        vm.expectRevert();
        stablecoin.burn(0);
    }

    function testBurnMoreThanBalance() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(stableCoinOwner, 100 ether);
        vm.prank(stableCoinOwner);
        vm.expectRevert();
        stablecoin.burn(101 ether);
    }

    function testBurn() public {
        address stableCoinOwner = stablecoin.owner();
        vm.prank(stableCoinOwner);
        stablecoin.mint(stableCoinOwner, 100 ether);
        uint256 balanceBeforeBurn = stablecoin.balanceOf(stableCoinOwner);
        vm.prank(stableCoinOwner);
        stablecoin.burn(10 ether);
        uint256 balanceAfterBurn = stablecoin.balanceOf(stableCoinOwner);

        //balance difference check equal burnt amount
        assertEq((balanceBeforeBurn - balanceAfterBurn), 10 ether);
    }
}
