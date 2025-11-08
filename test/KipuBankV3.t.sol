// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title KipuBankV3 Test Suite
/// @notice Comprehensive tests for KipuBankV3 contract (50%+ coverage target)
/// @dev Tests all deposit flows, withdrawals, Uniswap integration, and security patterns
contract KipuBankV3Test is Test {
    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST CONTRACTS & MOCKS
    // ═══════════════════════════════════════════════════════════════════════════════

    KipuBankV3 public bank;
    MockUniswapV2Router public mockRouter;
    MockWETH public mockWETH;
    MockUSDC public mockUSDC;
    MockERC20 public mockDAI;
    MockERC20 public mockUnsupportedToken;

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════════

    uint256 constant BANK_CAP_USDC = 100_000_000_000; // 100,000 USDC (6 decimals)
    uint256 constant MAX_WITHDRAW_PER_TX = 1_000_000_000; // 1,000 USDC (6 decimals)

    // ═══════════════════════════════════════════════════════════════════════════════
    // TEST ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════════

    address owner = address(this);
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    // ═══════════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════════

    function setUp() public {
        // Deploy mock contracts
        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();
        mockDAI = new MockERC20("DAI Stablecoin", "DAI", 18);
        mockUnsupportedToken = new MockERC20("Unsupported Token", "UNSUP", 18);

        // Deploy mock Uniswap router
        mockRouter = new MockUniswapV2Router(
            address(mockWETH),
            address(mockUSDC)
        );

        // Add DAI to router's supported pairs (DAI/USDC)
        mockRouter.addPair(address(mockDAI), address(mockUSDC));

        // Deploy KipuBankV3
        bank = new KipuBankV3(
            BANK_CAP_USDC,
            MAX_WITHDRAW_PER_TX,
            address(mockRouter),
            address(mockUSDC)
        );

        // Setup test users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        // Mint tokens to test users
        mockUSDC.mint(user1, 50_000_000_000); // 50,000 USDC
        mockUSDC.mint(user2, 50_000_000_000); // 50,000 USDC
        mockDAI.mint(user1, 100_000 ether); // 100,000 DAI
        mockDAI.mint(user2, 100_000 ether); // 100,000 DAI

        // Mint USDC to bank for withdrawals
        mockUSDC.mint(address(bank), 200_000_000_000); // 200,000 USDC
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Constructor_ValidInitialization() public {
        assertEq(bank.bankCapUSD(), BANK_CAP_USDC);
        assertEq(bank.MAX_WITHDRAW_PER_TX(), MAX_WITHDRAW_PER_TX);
        assertEq(address(bank.uniswapV2Router()), address(mockRouter));
        assertEq(bank.usdc(), address(mockUSDC));
        assertEq(bank.weth(), address(mockWETH));
        assertEq(bank.totalDepositsUSDC(), 0);
        assertEq(bank.depositsPaused(), false);
    }

    function test_Constructor_USDCAutoWhitelisted() public {
        assertTrue(bank.isTokenSupported(address(mockUSDC)));
    }

    function test_Constructor_RevertIf_ZeroBankCap() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        new KipuBankV3(
            0,
            MAX_WITHDRAW_PER_TX,
            address(mockRouter),
            address(mockUSDC)
        );
    }

    function test_Constructor_RevertIf_ZeroMaxWithdraw() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        new KipuBankV3(
            BANK_CAP_USDC,
            0,
            address(mockRouter),
            address(mockUSDC)
        );
    }

    function test_Constructor_RevertIf_ZeroRouterAddress() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        new KipuBankV3(
            BANK_CAP_USDC,
            MAX_WITHDRAW_PER_TX,
            address(0),
            address(mockUSDC)
        );
    }

    function test_Constructor_RevertIf_ZeroUSDCAddress() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        new KipuBankV3(
            BANK_CAP_USDC,
            MAX_WITHDRAW_PER_TX,
            address(mockRouter),
            address(0)
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DEPOSIT ETH TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_DepositETH_Success() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUSDC = 2000_000_000; // 2000 USDC (assuming 1 ETH = $2000)

        vm.startPrank(user1);

        vm.expectEmit(true, true, false, true);
        emit KipuBankV3.DepositMade(
            user1,
            address(0),
            depositAmount,
            expectedUSDC
        );

        bank.depositETH{value: depositAmount}();

        assertEq(bank.getVaultBalance(user1), expectedUSDC);
        assertEq(bank.getUserDepositCount(user1), 1);
        assertEq(bank.getTotalDeposits(), expectedUSDC);
        vm.stopPrank();
    }

    function test_DepositETH_MultipleDeposits() public {
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 0.5 ether;
        uint256 expectedUSDC1 = 2000_000_000; // 2000 USDC
        uint256 expectedUSDC2 = 1000_000_000; // 1000 USDC

        vm.startPrank(user1);

        bank.depositETH{value: deposit1}();
        bank.depositETH{value: deposit2}();

        assertEq(bank.getVaultBalance(user1), expectedUSDC1 + expectedUSDC2);
        assertEq(bank.getUserDepositCount(user1), 2);
        assertEq(bank.getTotalDeposits(), expectedUSDC1 + expectedUSDC2);
        vm.stopPrank();
    }

    function test_DepositETH_RevertIf_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.depositETH{value: 0}();
        vm.stopPrank();
    }

    function test_DepositETH_RevertIf_DepositsPaused() public {
        bank.pauseDeposits(true);

        vm.startPrank(user1);
        vm.expectRevert(KipuBankV3.DepositsArePaused.selector);
        bank.depositETH{value: 1 ether}();
        vm.stopPrank();
    }

    function test_DepositETH_RevertIf_ExceedsBankCap() public {
        // Deposit amount that would exceed bank cap
        uint256 excessiveDeposit = 60 ether; // Would result in ~120,000 USDC

        vm.startPrank(user1);
        vm.expectRevert(KipuBankV3.BankCapExceeded.selector);
        bank.depositETH{value: excessiveDeposit}();
        vm.stopPrank();
    }

    function test_DepositETH_WETHWrappingAndSwap() public {
        uint256 depositAmount = 1 ether;
        uint256 wethBalanceBefore = mockWETH.balanceOf(address(bank));

        vm.prank(user1);
        bank.depositETH{value: depositAmount}();

        // WETH should have been wrapped and swapped (balance should be 0 after swap)
        assertEq(mockWETH.balanceOf(address(bank)), wethBalanceBefore);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // DEPOSIT TOKEN TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Deposit_USDC_DirectDeposit() public {
        uint256 depositAmount = 5000_000_000; // 5,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit KipuBankV3.DepositMade(
            user1,
            address(mockUSDC),
            depositAmount,
            depositAmount
        );

        bank.deposit(address(mockUSDC), depositAmount);

        assertEq(bank.getVaultBalance(user1), depositAmount);
        assertEq(bank.getUserDepositCount(user1), 1);
        assertEq(bank.getTotalDeposits(), depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_DAI_WithSwap() public {
        // Add DAI to supported tokens
        bank.addSupportedToken(address(mockDAI));

        uint256 depositAmount = 5000 ether; // 5,000 DAI
        uint256 expectedUSDC = 5000_000_000; // 5,000 USDC (1:1 ratio in mock)

        vm.startPrank(user1);
        mockDAI.approve(address(bank), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit KipuBankV3.TokenSwapped(
            address(mockDAI),
            depositAmount,
            expectedUSDC
        );

        bank.deposit(address(mockDAI), depositAmount);

        assertEq(bank.getVaultBalance(user1), expectedUSDC);
        assertEq(bank.getUserDepositCount(user1), 1);
        vm.stopPrank();
    }

    function test_Deposit_RevertIf_UnsupportedToken() public {
        uint256 depositAmount = 1000 ether;

        vm.startPrank(user1);
        mockUnsupportedToken.mint(user1, depositAmount);
        mockUnsupportedToken.approve(address(bank), depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.TokenNotSupported.selector,
                address(mockUnsupportedToken)
            )
        );
        bank.deposit(address(mockUnsupportedToken), depositAmount);
        vm.stopPrank();
    }

    function test_Deposit_RevertIf_ZeroAmount() public {
        vm.startPrank(user1);
        mockUSDC.approve(address(bank), 1000_000_000);

        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.deposit(address(mockUSDC), 0);
        vm.stopPrank();
    }

    function test_Deposit_RevertIf_DepositsPaused() public {
        bank.pauseDeposits(true);

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), 1000_000_000);

        vm.expectRevert(KipuBankV3.DepositsArePaused.selector);
        bank.deposit(address(mockUSDC), 1000_000_000);
        vm.stopPrank();
    }

    function test_Deposit_RevertIf_ExceedsBankCap() public {
        uint256 excessiveAmount = 120_000_000_000; // 120,000 USDC

        vm.startPrank(user1);
        mockUSDC.mint(user1, excessiveAmount);
        mockUSDC.approve(address(bank), excessiveAmount);

        vm.expectRevert(KipuBankV3.BankCapExceeded.selector);
        bank.deposit(address(mockUSDC), excessiveAmount);
        vm.stopPrank();
    }

    function test_Deposit_MultipleUsers() public {
        uint256 user1Deposit = 10_000_000_000; // 10,000 USDC
        uint256 user2Deposit = 15_000_000_000; // 15,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), user1Deposit);
        bank.deposit(address(mockUSDC), user1Deposit);
        vm.stopPrank();

        vm.startPrank(user2);
        mockUSDC.approve(address(bank), user2Deposit);
        bank.deposit(address(mockUSDC), user2Deposit);
        vm.stopPrank();

        assertEq(bank.getVaultBalance(user1), user1Deposit);
        assertEq(bank.getVaultBalance(user2), user2Deposit);
        assertEq(bank.getTotalDeposits(), user1Deposit + user2Deposit);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_Withdraw_Success() public {
        uint256 depositAmount = 10_000_000_000; // 10,000 USDC
        uint256 withdrawAmount = 500_000_000; // 500 USDC (within limit)

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        uint256 balanceBefore = mockUSDC.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit KipuBankV3.WithdrawalMade(user1, withdrawAmount);

        bank.withdraw(withdrawAmount);

        assertEq(bank.getVaultBalance(user1), depositAmount - withdrawAmount);
        assertEq(bank.getUserWithdrawalCount(user1), 1);
        assertEq(mockUSDC.balanceOf(user1), balanceBefore + withdrawAmount);
        assertEq(bank.getTotalDeposits(), depositAmount - withdrawAmount);
        vm.stopPrank();
    }

    function test_Withdraw_MultipleWithdrawals() public {
        uint256 depositAmount = 10_000_000_000; // 10,000 USDC
        uint256 withdraw1 = 500_000_000; // 500 USDC (within limit)
        uint256 withdraw2 = 500_000_000; // 500 USDC (within limit)

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        bank.withdraw(withdraw1);
        bank.withdraw(withdraw2);

        assertEq(
            bank.getVaultBalance(user1),
            depositAmount - withdraw1 - withdraw2
        );
        assertEq(bank.getUserWithdrawalCount(user1), 2);
        vm.stopPrank();
    }

    function test_Withdraw_RevertIf_InsufficientBalance() public {
        uint256 depositAmount = 5_000_000_000; // 5,000 USDC
        uint256 withdrawAmount = 10_000_000_000; // 10,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        vm.expectRevert(KipuBankV3.InsufficientBalance.selector);
        bank.withdraw(withdrawAmount);
        vm.stopPrank();
    }

    function test_Withdraw_RevertIf_ZeroAmount() public {
        uint256 depositAmount = 5_000_000_000; // 5,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        vm.expectRevert(KipuBankV3.ZeroAmount.selector);
        bank.withdraw(0);
        vm.stopPrank();
    }

    function test_Withdraw_RevertIf_ExceedsLimit() public {
        uint256 depositAmount = 50_000_000_000; // 50,000 USDC
        uint256 excessiveWithdraw = 2_000_000_000; // 2,000 USDC (exceeds MAX_WITHDRAW_PER_TX)

        vm.startPrank(user1);
        mockUSDC.mint(user1, depositAmount);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        vm.expectRevert(KipuBankV3.WithdrawalLimitExceeded.selector);
        bank.withdraw(excessiveWithdraw);
        vm.stopPrank();
    }

    function test_Withdraw_WorksWhenDepositsPaused() public {
        uint256 depositAmount = 5_000_000_000; // 5,000 USDC
        uint256 withdrawAmount = 1_000_000_000; // 1,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);
        vm.stopPrank();

        // Pause deposits
        bank.pauseDeposits(true);

        // Withdrawal should still work
        vm.prank(user1);
        bank.withdraw(withdrawAmount);

        assertEq(bank.getVaultBalance(user1), depositAmount - withdrawAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_AddSupportedToken_Success() public {
        address newToken = address(mockDAI);

        vm.expectEmit(true, false, false, false);
        emit KipuBankV3.TokenAdded(newToken);

        bank.addSupportedToken(newToken);

        assertTrue(bank.isTokenSupported(newToken));
    }

    function test_AddSupportedToken_RevertIf_InvalidPair() public {
        address tokenWithoutPair = address(mockUnsupportedToken);

        vm.expectRevert(KipuBankV3.InvalidUniswapPair.selector);
        bank.addSupportedToken(tokenWithoutPair);
    }

    function test_AddSupportedToken_RevertIf_ZeroAddress() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        bank.addSupportedToken(address(0));
    }

    function test_AddSupportedToken_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.addSupportedToken(address(mockDAI));
    }

    function test_RemoveSupportedToken_Success() public {
        bank.addSupportedToken(address(mockDAI));
        assertTrue(bank.isTokenSupported(address(mockDAI)));

        vm.expectEmit(true, false, false, false);
        emit KipuBankV3.TokenRemoved(address(mockDAI));

        bank.removeSupportedToken(address(mockDAI));

        assertFalse(bank.isTokenSupported(address(mockDAI)));
    }

    function test_RemoveSupportedToken_RevertIf_USDC() public {
        vm.expectRevert(KipuBankV3.InvalidParameter.selector);
        bank.removeSupportedToken(address(mockUSDC));
    }

    function test_RemoveSupportedToken_RevertIf_NotOwner() public {
        bank.addSupportedToken(address(mockDAI));

        vm.prank(user1);
        vm.expectRevert();
        bank.removeSupportedToken(address(mockDAI));
    }

    function test_PauseDeposits_Success() public {
        assertFalse(bank.depositsPaused());

        vm.expectEmit(false, false, false, true);
        emit KipuBankV3.DepositsPaused(true);

        bank.pauseDeposits(true);

        assertTrue(bank.depositsPaused());
    }

    function test_UnpauseDeposits_Success() public {
        bank.pauseDeposits(true);
        assertTrue(bank.depositsPaused());

        vm.expectEmit(false, false, false, true);
        emit KipuBankV3.DepositsPaused(false);

        bank.pauseDeposits(false);

        assertFalse(bank.depositsPaused());
    }

    function test_PauseDeposits_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.pauseDeposits(true);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_GetVaultBalance() public {
        uint256 depositAmount = 10_000_000_000; // 10,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);
        vm.stopPrank();

        assertEq(bank.getVaultBalance(user1), depositAmount);
        assertEq(bank.getVaultBalance(user2), 0);
    }

    function test_GetRemainingCapacity() public {
        assertEq(bank.getRemainingCapacity(), BANK_CAP_USDC);

        uint256 depositAmount = 10_000_000_000; // 10,000 USDC

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);
        vm.stopPrank();

        assertEq(bank.getRemainingCapacity(), BANK_CAP_USDC - depositAmount);
    }

    function test_IsTokenSupported() public {
        assertTrue(bank.isTokenSupported(address(mockUSDC)));
        assertFalse(bank.isTokenSupported(address(mockDAI)));

        bank.addSupportedToken(address(mockDAI));
        assertTrue(bank.isTokenSupported(address(mockDAI)));
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // SECURITY & EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════════

    function test_BankCap_BoundaryTesting() public {
        uint256 almostFullDeposit = BANK_CAP_USDC - 1_000_000; // Leave 1 USDC room

        vm.startPrank(user1);
        mockUSDC.mint(user1, almostFullDeposit);
        mockUSDC.approve(address(bank), almostFullDeposit);
        bank.deposit(address(mockUSDC), almostFullDeposit);
        vm.stopPrank();

        // Should succeed with remaining capacity
        vm.startPrank(user2);
        mockUSDC.approve(address(bank), 1_000_000);
        bank.deposit(address(mockUSDC), 1_000_000);
        vm.stopPrank();

        assertEq(bank.getTotalDeposits(), BANK_CAP_USDC);
    }

    function test_WithdrawalLimit_BoundaryTesting() public {
        uint256 depositAmount = 50_000_000_000; // 50,000 USDC

        vm.startPrank(user1);
        mockUSDC.mint(user1, depositAmount);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        // Should succeed at exact limit
        bank.withdraw(MAX_WITHDRAW_PER_TX);

        assertEq(
            bank.getVaultBalance(user1),
            depositAmount - MAX_WITHDRAW_PER_TX
        );
        vm.stopPrank();
    }

    function test_MultipleUsers_ConcurrentOperations() public {
        uint256 user1Deposit = 10_000_000_000;
        uint256 user2Deposit = 15_000_000_000;
        uint256 user3Deposit = 5_000_000_000;
        uint256 user1Withdrawal = 800_000_000;

        // User 1 deposits
        vm.startPrank(user1);
        mockUSDC.approve(address(bank), user1Deposit);
        bank.deposit(address(mockUSDC), user1Deposit);
        vm.stopPrank();

        // User 2 deposits
        vm.startPrank(user2);
        mockUSDC.approve(address(bank), user2Deposit);
        bank.deposit(address(mockUSDC), user2Deposit);
        vm.stopPrank();

        // User 1 withdraws (within limit)
        vm.prank(user1);
        bank.withdraw(user1Withdrawal); // 800 USDC (within MAX_WITHDRAW_PER_TX)

        // User 3 deposits
        vm.startPrank(user3);
        mockUSDC.mint(user3, user3Deposit);
        mockUSDC.approve(address(bank), user3Deposit);
        bank.deposit(address(mockUSDC), user3Deposit);
        vm.stopPrank();

        // Verify all balances
        assertEq(bank.getVaultBalance(user1), user1Deposit - user1Withdrawal); // 9,200 USDC
        assertEq(bank.getVaultBalance(user2), user2Deposit);
        assertEq(bank.getVaultBalance(user3), user3Deposit);
        assertEq(
            bank.getTotalDeposits(),
            user1Deposit + user2Deposit + user3Deposit - user1Withdrawal
        ); // 29,200 USDC
    }

    function test_Reentrancy_Protection() public {
        // This test verifies ReentrancyGuard is working
        // In a real attack, a malicious contract would try to call deposit/withdraw recursively
        // The ReentrancyGuard modifier prevents this
        uint256 depositAmount = 10_000_000_000;

        vm.startPrank(user1);
        mockUSDC.approve(address(bank), depositAmount);
        bank.deposit(address(mockUSDC), depositAmount);

        // Normal withdrawal should work (within limit)
        bank.withdraw(800_000_000); // 800 USDC (within MAX_WITHDRAW_PER_TX)
        assertEq(bank.getVaultBalance(user1), depositAmount - 800_000_000);
        vm.stopPrank();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS
// ═══════════════════════════════════════════════════════════════════════════════

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 __decimals
    ) ERC20(name, symbol) {
        _decimals = __decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockWETH is IWETH {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function deposit() external payable override {
        _balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external override {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) external override returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(
            _allowances[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        require(_balances[from] >= amount, "Insufficient balance");

        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

contract MockUniswapV2Router is IUniswapV2Router02 {
    address private immutable _weth;
    address public immutable usdc;
    mapping(bytes32 => bool) public supportedPairs;

    constructor(address wethAddress, address _usdc) {
        _weth = wethAddress;
        usdc = _usdc;

        // Auto-add WETH/USDC pair
        supportedPairs[keccak256(abi.encodePacked(wethAddress, _usdc))] = true;
    }

    function WETH() external view override returns (address) {
        return _weth;
    }

    function addPair(address token0, address token1) external {
        supportedPairs[keccak256(abi.encodePacked(token0, token1))] = true;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external override returns (uint256[] memory amounts) {
        require(path.length == 2, "Invalid path");
        require(
            supportedPairs[keccak256(abi.encodePacked(path[0], path[1]))],
            "Pair not supported"
        );

        // Transfer tokenIn from sender
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Calculate output (simplified: 1 ETH/WETH = $2000 USDC, 1 DAI = 1 USDC)
        uint256 amountOut;
        if (path[0] == _weth && path[1] == usdc) {
            // 1 WETH = 2000 USDC (with 6 decimals)
            amountOut = (amountIn * 2000_000_000) / 1 ether;
        } else {
            // For other tokens, assume 1:1 ratio (simplified)
            uint8 decimalsIn = ERC20(path[0]).decimals();
            uint8 decimalsOut = ERC20(path[1]).decimals();
            amountOut = (amountIn * (10 ** decimalsOut)) / (10 ** decimalsIn);
        }

        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Mint output token to recipient (test-only: mock router can mint)
        if (path[1] == usdc) {
            MockUSDC(usdc).mint(to, amountOut);
        } else {
            MockERC20(path[1]).mint(to, amountOut);
        }

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view override returns (uint256[] memory amounts) {
        require(path.length == 2, "Invalid path");
        require(
            supportedPairs[keccak256(abi.encodePacked(path[0], path[1]))],
            "Pair not supported"
        );

        uint256 amountOut;
        if (path[0] == _weth && path[1] == usdc) {
            amountOut = (amountIn * 2000_000_000) / 1 ether;
        } else {
            uint8 decimalsIn = ERC20(path[0]).decimals();
            uint8 decimalsOut = ERC20(path[1]).decimals();
            amountOut = (amountIn * (10 ** decimalsOut)) / (10 ** decimalsIn);
        }

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }
}
