// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CEther } from "compound-protocol/contracts/CEther.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import "forge-std/interfaces/IERC20.sol";

contract TestScript is Script, Test {
    address payable user1 = payable(0x755557E102286F31F83BdE39c007cEE46D12D321);
    address payable user2 = payable(0xAdfaD0B8ccbAD46a009fAa4480E7986378a679bb);

    CEther cETH = CEther(payable(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5));
    // CErc20 使用 interface 方式，透過 CErc20Delegator contract address 實現它。這樣 CErc20Delegator 也會有 CErc20 的 function 可以使用。
    CErc20 cDAI = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    // CErc20Delegator cDAI = CErc20Delegator(payable(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643));

    IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    PriceOracle oracle = PriceOracle(0x65c816077C29b557BEE980ae3cC2dCE80204A0C5);

    Comptroller comptroller = Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    function setUp() public view {}

    function testRun() public {
        console.logString(unicode"*****使用 ERc20Delegator 宣告 cDai*****");
        vm.createSelectFork("mainnet");
        vm.startPrank(user1);
        vm.deal(user1, 20 ether);
        deal(address(dai), user2, 10000 ether);

        // console.log("user1 ETH balance: ", );
        //  ETH 價格，單位為 USD 。
        console.log("ETH price: ", oracle.getUnderlyingPrice(cETH)); // 1665903740000000000000 = 1665.90374 USD
        //  DAI 價格，單位為 USD 。 
        console.log("DAI price: ", oracle.getUnderlyingPrice(cDAI)); // 1000120000000000000 = 1.00012 USD

        cETH.mint{value: 15 ether}(); // 存款 - 15 ETH
        cETH.redeemUnderlying(5 ether); // 取款 - 5 ETH
        // 獲得 抵押率
        (, uint collateralFactorMantissa, ) = comptroller.markets(address(cETH)); 
        console2.log("eth collateral factor: ", collateralFactorMantissa); // 825000000000000000 = 0.825

        address[] memory collateralToken = new address[](1);
        collateralToken[0] = address(cETH);
        comptroller.enterMarkets(collateralToken);  // 將 ETH 設定為抵押物
        cDAI.borrow(10500 ether); // 借款 - 10500 DAI
        dai.approve(address(cDAI), 500 ether); // 核准 500 DAI 給 cDAI token
        cDAI.repayBorrow(500 ether); // 償還 500 DAI
        // liquidity 借款額度 = (存款數量(ETH) * underlying price * 抵押率) - (借款數量 * underlying price) 
        //                   = (15 - 5) * 1665.90374 * 0.825 - (10500 - 500) * 1.00012 = 13743.705855 - 10001.2 = 3742.505855 USD
        (, uint liquidity, uint shortfall) = comptroller.getAccountLiquidity(user1); 
        console2.log("before adjust: liquidity: ",liquidity, ";shortfall: ", shortfall); // 4951715752681302127959 = 4951.715752681302127959 USD

        vm.stopPrank();
        vm.prank(0x6d903f6003cca6255D85CcA4D3B5E5146dC33925); // 管理者錢包
        // 抵押率改為 100000000 gwei = 0.1 cETH => 造成借款額度為負數 => liquidity = 0
        comptroller._setCollateralFactor(cETH, 100000000 gwei); 
        vm.startPrank(user2);

        (, liquidity, shortfall) = comptroller.getAccountLiquidity(user1);
        console2.log("after adjust: liquidity: ",liquidity, ";shortfall: ", shortfall); // // 0, 8186792029978023984490

        dai.approve(address(cDAI), 5000 ether);
        // user2 對 user1 發起清算並代償還 5000 DAI
        // user2 獲得 user1 的 ETH 抵押物 = 償還數量 * 借款 token price / 抵押物價格 * 1.08
        //                               = 5000 * 1.00012 / 1665.90374 * 1.08 = 3.24187279
        cDAI.liquidateBorrow(user1, 5000 ether, cETH); 

        (, liquidity, shortfall) = comptroller.getAccountLiquidity(user1);
        console2.log("after liquidation: liquidity: ",liquidity, ";shortfall: ", shortfall); // 0, 3727237893922450676723

        console2.log("user1 eth balance: ",cETH.balanceOfUnderlying(user1)); // 7020508281273861317 = 7.020508281273861317
        console2.log("user2 eth balance: ",cETH.balanceOfUnderlying(user2)); // 2979491718847405202 = 2.979491718847405202

        vm.stopPrank();
    }
}

// Logs:
//   ETH price:  1665903740000000000000
//   DAI price:  1000120000000000000
//   eth collateral factor:  825000000000000000
//   before adjust: liquidity:  4951715752681302127959 ;shortfall:  0
//   after adjust: liquidity:  0 ;shortfall:  8186792029978023984490
//   after liquidation: liquidity:  0 ;shortfall:  3727237893922450676723
//   user1 eth balance:  7020508281273861317
//   user2 eth balance:  2979491718847405202