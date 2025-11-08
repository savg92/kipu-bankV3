// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {KipuBankV2} from "../src/KipuBankV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mock ERC20 Token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

/// @title Mock Chainlink Aggregator for testing
contract MockAggregatorV3 {
    int256 private _price;
    uint8 private _decimals;
    uint80 private _roundId;
    uint256 private _updatedAt;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
        _roundId = 1;
        _updatedAt = block.timestamp;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, block.timestamp, _updatedAt, _roundId);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
    }

    function setStalePrice() external {
        _updatedAt = 0; // Makes price stale
    }

    function setStaleRound() external {
        _roundId = 2; // answeredInRound will be less than roundId
    }
}

/// @title KipuBankV2 Test Suite
/// @notice Comprehensive tests for multi-token vault with Chainlink oracles
contract KipuBankV2Test is Test {
    KipuBankV2 public bank;
    MockAggregatorV3 public ethUsdPriceFeed;
    MockAggregatorV3 public usdcPriceFeed;
    MockAggregatorV3 public usdtPriceFeed;
    
    MockERC20 public usdc;
    MockERC20 public usdt;
    MockERC20 public dai;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    // Test constants
    uint256 public constant BANK_CAP_USD = 100_000 * 10**6; // 100k USDC (6 decimals)
    uint256 public constant MAX_WITHDRAW_PER_TX = 1 ether; // 1 ETH
    int256 public constant INITIAL_ETH_PRICE = 2000 * 10**8; // $2000 (8 decimals)
    int256 public constant USDC_PRICE = 1 * 10**8; // $1 (8 decimals)
    int256 public constant USDT_PRICE = 1 * 10**8; // $1 (8 decimals)
    
    address public constant ETH_ADDRESS = address(0);
    
    // Events to test
    event DepositMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 valueUSD
    );
    
    event WithdrawalMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 valueUSD
    );
    
    event TokenAdded(address indexed token, uint8 decimals, address priceFeed);
    event TokenRemoved(address indexed token);
    event DepositsToggled(bool isPaused);
    
    function setUp() public {
        // Set up accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Fund test accounts with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        
        // Deploy mock price feeds
        ethUsdPriceFeed = new MockAggregatorV3(INITIAL_ETH_PRICE, 8);
        usdcPriceFeed = new MockAggregatorV3(USDC_PRICE, 8);
        usdtPriceFeed = new MockAggregatorV3(USDT_PRICE, 8);
        
        // Deploy KipuBankV2
        bank = new KipuBankV2(
            BANK_CAP_USD,
            MAX_WITHDRAW_PER_TX,
            address(ethUsdPriceFeed)
        );
        
        // Deploy mock ERC20 tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        
        // Mint tokens to test users
        usdc.mint(user1, 10_000 * 10**6); // 10k USDC
        usdc.mint(user2, 10_000 * 10**6);
        usdc.mint(user3, 10_000 * 10**6);
        
        usdt.mint(user1, 10_000 * 10**6); // 10k USDT
        usdt.mint(user2, 10_000 * 10**6);
        
        dai.mint(user1, 10_000 * 10**18); // 10k DAI
        
        // Add supported tokens (owner action)
        bank.addSupportedToken(address(usdc), 6, address(usdcPriceFeed));
        bank.addSupportedToken(address(usdt), 6, address(usdtPriceFeed));
    }
    
    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor_Success() public {
        assertEq(bank.bankCapUSD(), BANK_CAP_USD);
        assertEq(bank.MAX_WITHDRAW_PER_TX(), MAX_WITHDRAW_PER_TX);
        assertEq(address(bank.ethUsdPriceFeed()), address(ethUsdPriceFeed));
        assertEq(bank.owner(), owner);
        assertEq(bank.totalDepositsUSD(), 0);
        assertFalse(bank.depositsPaused());
    }
    
    function test_Constructor_RevertsOnZeroBankCap() public {
        vm.expectRevert(KipuBankV2.InvalidBankCap.selector);
        new KipuBankV2(0, MAX_WITHDRAW_PER_TX, address(ethUsdPriceFeed));
    }
    
    function test_Constructor_RevertsOnZeroMaxWithdraw() public {
        vm.expectRevert(KipuBankV2.InvalidMaxWithdraw.selector);
        new KipuBankV2(BANK_CAP_USD, 0, address(ethUsdPriceFeed));
    }
    
    function test_Constructor_RevertsOnInvalidPriceFeed() public {
        vm.expectRevert(KipuBankV2.InvalidPriceFeed.selector);
        new KipuBankV2(BANK_CAP_USD, MAX_WITHDRAW_PER_TX, address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                        ETH DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositETH_Success() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUSD = (depositAmount * uint256(INITIAL_ETH_PRICE)) / (10**20); // Normalize
        
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, false, true);
        emit DepositMade(user1, ETH_ADDRESS, depositAmount, expectedUSD);
        
        bank.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), depositAmount);
        assertEq(bank.getDepositCount(user1), 1);
        assertEq(bank.totalDepositsUSD(), expectedUSD);
        
        vm.stopPrank();
    }
    
    function test_DepositETH_MultipleDeposits() public {
        vm.startPrank(user1);
        
        bank.deposit{value: 0.5 ether}(ETH_ADDRESS, 0.5 ether);
        bank.deposit{value: 0.3 ether}(ETH_ADDRESS, 0.3 ether);
        bank.deposit{value: 0.2 ether}(ETH_ADDRESS, 0.2 ether);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), 1 ether);
        assertEq(bank.getDepositCount(user1), 3);
        
        vm.stopPrank();
    }
    
    function test_DepositETH_RevertsOnZeroAmount() public {
        vm.startPrank(user1);
        
        vm.expectRevert(KipuBankV2.ZeroDepositAmount.selector);
        bank.deposit{value: 0}(ETH_ADDRESS, 0);
        
        vm.stopPrank();
    }
    
    function test_DepositETH_RevertsOnInvalidAmount() public {
        vm.startPrank(user1);
        
        vm.expectRevert(KipuBankV2.InvalidETHAmount.selector);
        bank.deposit{value: 1 ether}(ETH_ADDRESS, 0.5 ether);
        
        vm.stopPrank();
    }
    
    function test_DepositETH_RevertsWhenPaused() public {
        // Pause deposits
        bank.pauseDeposits();
        
        vm.startPrank(user1);
        
        vm.expectRevert(KipuBankV2.DepositsArePaused.selector);
        bank.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);
        
        vm.stopPrank();
    }
    
    function test_DepositETH_RevertsWhenExceedingBankCap() public {
        // Deposit almost to cap
        uint256 maxETH = (BANK_CAP_USD * 10**20) / uint256(INITIAL_ETH_PRICE);
        
        vm.startPrank(user1);
        bank.deposit{value: maxETH}(ETH_ADDRESS, maxETH);
        vm.stopPrank();
        
        // Try to deposit more
        vm.startPrank(user2);
        vm.expectRevert(KipuBankV2.BankCapExceeded.selector);
        bank.deposit{value: 0.1 ether}(ETH_ADDRESS, 0.1 ether);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ERC20 DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositUSDC_Success() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        
        vm.expectEmit(true, true, false, true);
        emit DepositMade(user1, address(usdc), depositAmount, depositAmount);
        
        bank.deposit(address(usdc), depositAmount);
        
        assertEq(bank.getVaultBalance(user1, address(usdc)), depositAmount);
        assertEq(bank.getDepositCount(user1), 1);
        assertEq(bank.totalDepositsUSD(), depositAmount);
        
        vm.stopPrank();
    }
    
    function test_DepositToken_RevertsOnUnsupportedToken() public {
        vm.startPrank(user1);
        dai.approve(address(bank), 1000 * 10**18);
        
        vm.expectRevert(abi.encodeWithSelector(KipuBankV2.TokenNotSupported.selector, address(dai)));
        bank.deposit(address(dai), 1000 * 10**18);
        
        vm.stopPrank();
    }
    
    function test_DepositToken_RevertsWithUnexpectedETH() public {
        uint256 depositAmount = 1000 * 10**6;
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        
        vm.expectRevert(KipuBankV2.UnexpectedETHSent.selector);
        bank.deposit{value: 0.1 ether}(address(usdc), depositAmount);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ETH WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_WithdrawETH_Success() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 0.5 ether;
        
        vm.startPrank(user1);
        
        // Deposit first
        bank.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);
        
        uint256 balanceBefore = user1.balance;
        uint256 expectedUSD = (withdrawAmount * uint256(INITIAL_ETH_PRICE)) / (10**20);
        
        vm.expectEmit(true, true, false, true);
        emit WithdrawalMade(user1, ETH_ADDRESS, withdrawAmount, expectedUSD);
        
        bank.withdraw(ETH_ADDRESS, withdrawAmount);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), depositAmount - withdrawAmount);
        assertEq(bank.getWithdrawalCount(user1), 1);
        assertEq(user1.balance, balanceBefore + withdrawAmount);
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH_RevertsOnZeroAmount() public {
        vm.startPrank(user1);
        bank.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);
        
        vm.expectRevert(KipuBankV2.ZeroWithdrawalAmount.selector);
        bank.withdraw(ETH_ADDRESS, 0);
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH_RevertsOnInsufficientBalance() public {
        vm.startPrank(user1);
        bank.deposit{value: 0.5 ether}(ETH_ADDRESS, 0.5 ether);
        
        vm.expectRevert(KipuBankV2.InsufficientBalance.selector);
        bank.withdraw(ETH_ADDRESS, 1 ether);
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH_RevertsExceedingLimit() public {
        vm.startPrank(user1);
        bank.deposit{value: 5 ether}(ETH_ADDRESS, 5 ether);
        
        vm.expectRevert(KipuBankV2.WithdrawalLimitExceeded.selector);
        bank.withdraw(ETH_ADDRESS, 2 ether); // Exceeds MAX_WITHDRAW_PER_TX
        
        vm.stopPrank();
    }
    
    function test_WithdrawETH_EntireBalance() public {
        uint256 depositAmount = 0.5 ether;
        
        vm.startPrank(user1);
        bank.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);
        
        bank.withdraw(ETH_ADDRESS, depositAmount);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), 0);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ERC20 WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_WithdrawUSDC_Success() public {
        uint256 depositAmount = 5000 * 10**6;
        uint256 withdrawAmount = 1000 * 10**6;
        
        vm.startPrank(user1);
        
        usdc.approve(address(bank), depositAmount);
        bank.deposit(address(usdc), depositAmount);
        
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        bank.withdraw(address(usdc), withdrawAmount);
        
        assertEq(bank.getVaultBalance(user1, address(usdc)), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(user1), balanceBefore + withdrawAmount);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                        ORACLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetLatestETHPrice() public view {
        int256 price = bank.getLatestETHPrice();
        assertEq(price, INITIAL_ETH_PRICE);
    }
    
    function test_GetLatestETHPrice_RevertsOnStalePrice() public {
        ethUsdPriceFeed.setStalePrice();
        
        vm.expectRevert(KipuBankV2.StalePrice.selector);
        bank.getLatestETHPrice();
    }
    
    function test_GetETHValueInUSD() public view {
        uint256 ethAmount = 1 ether;
        uint256 expectedUSD = 2000 * 10**6; // $2000 with 6 decimals
        
        uint256 actualUSD = bank.getETHValueInUSD(ethAmount);
        assertEq(actualUSD, expectedUSD);
    }
    
    function test_NormalizeToUSDC() public view {
        // Test 18 decimals to 6
        uint256 amount18 = 1 * 10**18;
        uint256 normalized = bank.normalizeToUSDC(amount18, 18);
        assertEq(normalized, 1 * 10**6);
        
        // Test 8 decimals to 6
        uint256 amount8 = 1 * 10**8;
        normalized = bank.normalizeToUSDC(amount8, 8);
        assertEq(normalized, 1 * 10**6);
        
        // Test 6 decimals (no change)
        uint256 amount6 = 1 * 10**6;
        normalized = bank.normalizeToUSDC(amount6, 6);
        assertEq(normalized, 1 * 10**6);
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddSupportedToken_Success() public {
        vm.expectEmit(true, false, false, true);
        emit TokenAdded(address(dai), 18, address(usdcPriceFeed));
        
        bank.addSupportedToken(address(dai), 18, address(usdcPriceFeed));
        
        (bool isSupported, uint8 decimals, address priceFeed) = bank.supportedTokens(address(dai));
        assertTrue(isSupported);
        assertEq(decimals, 18);
        assertEq(priceFeed, address(usdcPriceFeed));
    }
    
    function test_AddSupportedToken_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.addSupportedToken(address(dai), 18, address(usdcPriceFeed));
    }
    
    function test_AddSupportedToken_RevertsForETHAddress() public {
        vm.expectRevert(abi.encodeWithSelector(KipuBankV2.TokenNotSupported.selector, ETH_ADDRESS));
        bank.addSupportedToken(ETH_ADDRESS, 18, address(usdcPriceFeed));
    }
    
    function test_AddSupportedToken_RevertsForInvalidPriceFeed() public {
        vm.expectRevert(KipuBankV2.InvalidPriceFeed.selector);
        bank.addSupportedToken(address(dai), 18, address(0));
    }
    
    function test_RemoveSupportedToken_Success() public {
        vm.expectEmit(true, false, false, false);
        emit TokenRemoved(address(usdc));
        
        bank.removeSupportedToken(address(usdc));
        
        (bool isSupported,,) = bank.supportedTokens(address(usdc));
        assertFalse(isSupported);
    }
    
    function test_RemoveSupportedToken_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.removeSupportedToken(address(usdc));
    }
    
    function test_PauseDeposits_Success() public {
        vm.expectEmit(false, false, false, true);
        emit DepositsToggled(true);
        
        bank.pauseDeposits();
        
        assertTrue(bank.depositsPaused());
    }
    
    function test_PauseDeposits_RevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.pauseDeposits();
    }
    
    function test_UnpauseDeposits_Success() public {
        bank.pauseDeposits();
        
        vm.expectEmit(false, false, false, true);
        emit DepositsToggled(false);
        
        bank.unpauseDeposits();
        
        assertFalse(bank.depositsPaused());
    }
    
    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetVaultBalance() public {
        vm.startPrank(user1);
        bank.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);
        vm.stopPrank();
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), 1 ether);
        assertEq(bank.getVaultBalance(user2, ETH_ADDRESS), 0);
    }
    
    function test_GetVaultBalanceInUSD() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUSD = 2000 * 10**6; // $2000
        
        vm.startPrank(user1);
        bank.deposit{value: depositAmount}(ETH_ADDRESS, depositAmount);
        vm.stopPrank();
        
        uint256 actualUSD = bank.getVaultBalanceInUSD(user1, ETH_ADDRESS);
        assertEq(actualUSD, expectedUSD);
    }
    
    function test_GetBankUtilization() public {
        // Deposit 50% of cap
        uint256 halfCapInETH = (BANK_CAP_USD * 10**20) / uint256(INITIAL_ETH_PRICE) / 2;
        
        vm.startPrank(user1);
        bank.deposit{value: halfCapInETH}(ETH_ADDRESS, halfCapInETH);
        vm.stopPrank();
        
        uint256 utilization = bank.getBankUtilization();
        assertApproxEqRel(utilization, 5000, 0.01e18); // ~50% (5000 out of 10000)
    }
    
    function test_GetRemainingCapacity() public {
        uint256 depositAmount = 1000 * 10**6; // $1000 worth
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        bank.deposit(address(usdc), depositAmount);
        vm.stopPrank();
        
        uint256 remaining = bank.getRemainingCapacity();
        assertEq(remaining, BANK_CAP_USD - depositAmount);
    }
    
    /*//////////////////////////////////////////////////////////////
                        SECURITY & EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function test_MultipleUsersCanDeposit() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}(ETH_ADDRESS, 1 ether);
        
        vm.prank(user2);
        bank.deposit{value: 0.5 ether}(ETH_ADDRESS, 0.5 ether);
        
        vm.prank(user3);
        bank.deposit{value: 0.3 ether}(ETH_ADDRESS, 0.3 ether);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), 1 ether);
        assertEq(bank.getVaultBalance(user2, ETH_ADDRESS), 0.5 ether);
        assertEq(bank.getVaultBalance(user3, ETH_ADDRESS), 0.3 ether);
    }
    
    function test_BankCapEnforcedAcrossUsers() public {
        // Calculate max ETH for bank cap
        uint256 maxETH = (BANK_CAP_USD * 10**20) / uint256(INITIAL_ETH_PRICE);
        uint256 halfMax = maxETH / 2;
        
        vm.prank(user1);
        bank.deposit{value: halfMax}(ETH_ADDRESS, halfMax);
        
        vm.prank(user2);
        bank.deposit{value: halfMax}(ETH_ADDRESS, halfMax);
        
        // User3 should not be able to deposit
        vm.prank(user3);
        vm.expectRevert(KipuBankV2.BankCapExceeded.selector);
        bank.deposit{value: 0.01 ether}(ETH_ADDRESS, 0.01 ether);
    }
    
    function test_ExactBankCapLimit() public {
        uint256 maxETH = (BANK_CAP_USD * 10**20) / uint256(INITIAL_ETH_PRICE);
        
        vm.prank(user1);
        bank.deposit{value: maxETH}(ETH_ADDRESS, maxETH);
        
        // Should be at exact cap
        assertApproxEqRel(bank.totalDepositsUSD(), BANK_CAP_USD, 0.01e18);
    }
    
    function test_ExactWithdrawalLimit() public {
        vm.startPrank(user1);
        bank.deposit{value: 5 ether}(ETH_ADDRESS, 5 ether);
        
        // Should succeed at exact limit
        bank.withdraw(ETH_ADDRESS, MAX_WITHDRAW_PER_TX);
        
        assertEq(bank.getVaultBalance(user1, ETH_ADDRESS), 5 ether - MAX_WITHDRAW_PER_TX);
        
        vm.stopPrank();
    }
    
    function test_CannotWithdrawFromZeroBalance() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV2.InsufficientBalance.selector);
        bank.withdraw(ETH_ADDRESS, 0.1 ether);
    }
    
    // Test receive function (contract can receive ETH)
    receive() external payable {}
}
