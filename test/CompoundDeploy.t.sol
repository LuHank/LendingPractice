// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console.sol";
//cToken
import "compound-protocol/contracts/CErc20Delegator.sol";
import "compound-protocol/contracts/CErc20Delegate.sol";
import "solmate/tokens/ERC20.sol";
import "compound-protocol/contracts/CToken.sol";
import "compound-protocol/contracts/CErc20.sol";
//comptroller
import "compound-protocol/contracts/Unitroller.sol";
import "compound-protocol/contracts/Comptroller.sol";
//interestModel
import "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
//priceOracle
import "compound-protocol/contracts/SimplePriceOracle.sol";

contract FiatToken is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}
}

contract CompoundDeploy is Test {
    FiatToken public uniERC20;
    ERC20 public uni;
    CErc20Delegator public cUni;
    CErc20Delegate public cUniDelegate;
    Unitroller  public unitroller;
    // ComptrollerG1 public comptroller;
    // ComptrollerG1 public unitrollerProxy;
    Comptroller public comptroller;
    Comptroller public unitrollerProxy;
    WhitePaperInterestRateModel public whitePaper;
    SimplePriceOracle public priceOracle;
    address public alice;
    address public bob;
    CErc20 public cuni;

    function setUp() public {        
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");
        //先初始化priceOracle
        priceOracle = new SimplePriceOracle();
        //再初始化whitepaper
        whitePaper = new WhitePaperInterestRateModel(50000000000000000,
                                                    120000000000000000);
        //再初始化comptroller
        unitroller = new Unitroller();
        // comptroller = new ComptrollerG1();
        // unitrollerProxy = ComptrollerG1(address(unitroller));
        comptroller = new Comptroller();
        unitrollerProxy = Comptroller(address(unitroller));

        unitroller._setPendingImplementation(address(comptroller));
        // comptroller._become(unitroller, priceOracle, 500000000000000000, 20, true);
        comptroller._become(unitroller);

        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(500000000000000000); // 50% decimals=18
        // unitrollerProxy._setMaxAssets(20);
        unitrollerProxy._setLiquidationIncentive(1080000000000000000);
        //最后初始化cToken
        // uni = new Standard_Token(uint(-1),"Uniswap Test",18,"Uni");
        uniERC20 = new FiatToken("USDT", "USDT", 18);
        
        uni = ERC20(address(uniERC20));

        cUniDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);
        cUni = new CErc20Delegator(
                    address(uni), 
                                ComptrollerInterface(address(unitroller)), 
                                InterestRateModel(address(whitePaper)),
                                200000000000000000000000000, // = 200000000 decimals = 18
                                "Compound Uniswap",
                                "cUNI",
                                8,
                                payable(address(this)),
                                address(cUniDelegate),
                                data
                                );
        cUni._setImplementation(address(cUniDelegate), false, data);
        cUni._setReserveFactor(250000000000000000); // = 0.25 decimals = 18
        cuni = CErc20(address(cUni));
        
        //设置uni的价格
        priceOracle.setUnderlyingPrice(CToken(address(cUni)), 1e18);
        //支持的markets
        // unitrollerProxy._supportMarket(CToken(address(cUni)));
        unitrollerProxy._supportMarket(CToken(address(cUni)));
        // unitrollerProxy._setCollateralFactor(CToken(address(CUni)), 
        //                                     600000000000000000); 
        unitrollerProxy._setCollateralFactor(CToken(address(cUni)), 
                                            600000000000000000); // = 60% , decimals = 18
        //将uni的代币全部转移给msg.sender,方便后续测试
        vm.prank(alice);
        // uni.transfer(msg.sender, uni.balanceOf(address(this)));
        deal(address(uni), alice, type(uint).max);
        deal(address(uni), address(uni), type(uint).max);
        deal(address(uni), bob, type(uint).max);
    }

    function testCompoundCore() public {
        vm.startPrank(alice);
        //alice 有所有的Uni代币
        // uni.balanceOf(alice) = uint(-1)
        console.log("uni balance: ", uni.balanceOf(alice));
        /***** 存款 *****/
        //alice 调用unitroller的enterMarkets方法, 因为在mintAllowed函数中，存在一个检查：require(markets[cToken].isListed), 故即使在mint中也需要先调用enterMarkets
        address[] memory addr = new address[](1);
        addr[0] = address(cUni);
        Comptroller(address(unitroller)).enterMarkets(addr);
        //此时alice调用enterMarkets后，全局变量 accountAssets[alice] = cToken[cUni], markets[cUni]={true, 60%，{alice:true},false}
        // cToken = Comptroller(address(unitroller)).accountAssets[alice];
        // CToken[] memory cToken = unitrollerProxy.accountAssets[alice];
        // CToken cUniToken = cToken[0];
        // console.log("alice' assets: ", cUniToken.balanceOf(alice));
        console.log("alice's cUni balanceOf: ", cUni.balanceOf(alice));
        //alice 调用cUni的mint方法
        // uni.approve(address(cUni),uint(-1));
        uni.approve(address(cUni),type(uint).max);
        // cUni.mint(7584007913129639935);
        CErc20(address(cuni)).mint(7584007913129639935);
        // 7584007913129639935/200000000 
        // cUni.balanceOf(alice) = 37920039565; 
        // cUni.totalSupply() = 37920039565
        // cUni.getCash() = 7584007913129639935
        // cUni.supplyRatePerBlock() = 0 //此时没有借款，利用率为0
        console.log("alice's balance: ", cUni.balanceOf(alice));
        console.log("cUni's totalSupply: ", cUni.totalSupply());
        console.log("cUni's cash: ", cUni.getCash());
        console.log("cUni's supplyRatePerBlock: ", cUni.supplyRatePerBlock());
        // ComptrollerG1(address(unitroller)).getAccountLiquidity(alice) = 4550404747877783960 = 7584007913129639935 * 0.6 //用户流动性：为UnderlyingToken * 0.6 * price
        (, uint liquidity,) = unitrollerProxy.getAccountLiquidity(alice);
        console.log("alice's liquidity: ", liquidity);

        /***** 借款 *****/
        //alice 在compound中存入了7584007913129639935的uni代币，获得了37920039565的cUni代币
        //alice 向compound提出借款4584007913129639935的uni代币
        cUni.borrow(2584007913129639935);
        // cUni.totalBorrows() = 2584007913129639935;
        console.log("cUni totalBorrows: ", cUni.totalBorrows());
        // cUni.getCash() == 5000000000000000000 = 7584007913129639935 - 2584007913129639935
        console.log("cUni cash: ", cUni.getCash());
        // cUni.supplyRatePerBlock = 11046856810
        console.log("cUni supplyRatePerBlock: ", cUni.supplyRatePerBlock());
        // cUni.exchangeRateStored() = 200000000003418771090092875
        console.log("cUni exchangeRateStored: ", cUni.exchangeRateStored());
        // cUni.borrowRatePerBlock() = 43229717700
        console.log("cUni borrowRatePerBlock: ", cUni.borrowRatePerBlock());
        // 利用率：utilization = cUni.supplyRatePerBlock / cUni.borrowRatePerBlock * (1- 0.25) = 
        // 0.25 = reserveFactory
        uint noReserveFactory = 1000000000000000000 - 250000000000000000; // solidity 沒有小數點
        console.log("noReserveFactory: ", noReserveFactory);
        uint supplyRateBlock = cUni.supplyRatePerBlock() * 1e18 * 100; // 由於 solidity 無法表達小數點，所以只能再乘以 100 才能看到
        uint borrowRateBlock = cUni.borrowRatePerBlock() * 1e18;
        console.log("supplyRateBlock: ", supplyRateBlock);
        console.log("borrowRateBlock: ", borrowRateBlock);
        uint supplyRateBlockWithoutReserveFactory = supplyRateBlock * noReserveFactory;
        console.log("cUni utilization: ", supplyRateBlock / borrowRateBlock);
        // cUni.borrowIndex() = 1000000095129377644
        console.log("cUni borrowIndex: ", cUni.borrowIndex());
        // cUni.accrualBlockNumber() =  4
        console.log("cUni accrueBlockNumber: ", cUni.accrualBlockNumber());

        /***** 還款 *****/
        uint repayBorrowAmount = 2584007913129639935 * 600000000000000000 / 1e20 * 100;
        uni.approve(address(cUni), repayBorrowAmount);
        cUni.repayBorrow(repayBorrowAmount);
        (, liquidity,) = unitrollerProxy.getAccountLiquidity(alice);
        console.log("alice's liquidity: ", liquidity);
        /***** 取款 *****/
        console.log("alice's cUni balanceOf", cUni.balanceOf(alice));
        console.log("alice's totalBorrowCurrent: ", cUni.totalBorrowsCurrent());
        uint redeemAmount = 10000000000;
        cUni.approve(address(cUni), redeemAmount);
        cUni.redeem(redeemAmount);
        vm.stopPrank();

        /***** 清算 *****/
        unitrollerProxy._setCollateralFactor(CToken(address(cUni)), 
                                            100000000000000000);
        vm.startPrank(bob);
        // address[] memory addr = new address[](1);
        // addr[0] = address(cUni);
        // Comptroller(address(unitroller)).enterMarkets(addr);
        uni.approve(address(cUni), type(uint).max);
        CErc20(address(cuni)).mint(7584007913129639935);
        uint borrowBalance = cUni.borrowBalanceCurrent(alice);
        uint closeFactory = unitrollerProxy.closeFactorMantissa();
        cUni.liquidateBorrow(alice, borrowBalance * closeFactory / 1e20, cUni);
    }
}