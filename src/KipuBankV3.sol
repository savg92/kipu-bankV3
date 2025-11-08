// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title KipuBankV3
/// @author savg92
/// @notice A decentralized vault that accepts any Uniswap V2 supported token and automatically converts to USDC
/// @dev Implements Module 4 patterns (modifiers-only validation, unchecked blocks) + V3 Uniswap integration
/// @custom:security-contact [email protected]
contract KipuBankV3 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTANTS & IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice USDC token has 6 decimal places
    uint8 public constant USDC_DECIMALS = 6;

    /// @notice Slippage tolerance: 98% means 2% maximum slippage allowed
    uint256 public constant SLIPPAGE_TOLERANCE = 98;

    /// @notice Maximum withdrawal amount per transaction (in USDC with 6 decimals)
    uint256 public immutable MAX_WITHDRAW_PER_TX;

    /// @notice Maximum total USDC deposits allowed in the bank (bank capacity)
    uint256 public immutable bankCapUSD;

    /// @notice Uniswap V2 Router for token swapping
    IUniswapV2Router02 public immutable uniswapV2Router;

    /// @notice WETH contract address for ETH wrapping
    address public immutable weth;

    /// @notice USDC contract address (target accounting token)
    address public immutable usdc;

    // ═══════════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Total USDC deposited across all users
    uint256 public totalDepositsUSDC;

    /// @notice Pause state for deposits (withdrawals always enabled)
    bool public depositsPaused;

    /// @notice User USDC balances (simplified from V2)
    mapping(address => uint256) private balances;

    /// @notice Number of deposits per user
    mapping(address => uint256) private depositCount;

    /// @notice Number of withdrawals per user
    mapping(address => uint256) private withdrawalCount;

    /// @notice Whitelist of supported tokens (true = supported)
    mapping(address => bool) private supportedTokens;

    // ═══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a deposit is successfully processed
    /// @param user The address of the depositor
    /// @param token The token deposited (address(0) for ETH)
    /// @param tokenAmount The amount of token deposited
    /// @param usdcReceived The amount of USDC received after swap
    event DepositMade(
        address indexed user,
        address indexed token,
        uint256 tokenAmount,
        uint256 usdcReceived
    );

    /// @notice Emitted when a token is swapped to USDC
    /// @param token The token that was swapped
    /// @param amountIn The amount of token swapped
    /// @param usdcOut The amount of USDC received
    event TokenSwapped(
        address indexed token,
        uint256 amountIn,
        uint256 usdcOut
    );

    /// @notice Emitted when a withdrawal is successfully processed
    /// @param user The address of the withdrawer
    /// @param usdcAmount The amount of USDC withdrawn
    event WithdrawalMade(address indexed user, uint256 usdcAmount);

    /// @notice Emitted when a token is added to the whitelist
    /// @param token The token address added
    event TokenAdded(address indexed token);

    /// @notice Emitted when a token is removed from the whitelist
    /// @param token The token address removed
    event TokenRemoved(address indexed token);

    /// @notice Emitted when deposit pause state changes
    /// @param paused True if deposits are paused, false if unpaused
    event DepositsPaused(bool paused);

    // ═══════════════════════════════════════════════════════════════════════════════
    // CUSTOM ERRORS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when deposit or withdrawal amount is zero
    error ZeroAmount();

    /// @notice Thrown when a token is not whitelisted
    /// @param token The unsupported token address
    error TokenNotSupported(address token);

    /// @notice Thrown when deposit would exceed bank capacity
    error BankCapExceeded();

    /// @notice Thrown when user has insufficient USDC balance
    error InsufficientBalance();

    /// @notice Thrown when withdrawal exceeds per-transaction limit
    error WithdrawalLimitExceeded();

    /// @notice Thrown when deposits are paused
    error DepositsArePaused();

    /// @notice Thrown when Uniswap swap fails
    error SwapFailed();

    /// @notice Thrown when no Uniswap pair exists for token/USDC
    error InvalidUniswapPair();

    /// @notice Thrown when ETH or token transfer fails
    error TransferFailed();

    /// @notice Thrown when constructor receives invalid parameters
    error InvalidParameter();

    /// @notice Thrown when swap returns zero USDC
    error ZeroSwapOutput();

    // ═══════════════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Validates that deposits are not paused
    modifier whenNotPaused() {
        if (depositsPaused) revert DepositsArePaused();
        _;
    }

    /// @notice Validates that amount is greater than zero
    /// @param _amount The amount to validate
    modifier validAmount(uint256 _amount) {
        if (_amount == 0) revert ZeroAmount();
        _;
    }

    /// @notice Validates that token is whitelisted or ETH
    /// @param token The token address to validate (address(0) for ETH)
    modifier supportedToken(address token) {
        if (token != address(0) && !supportedTokens[token]) {
            revert TokenNotSupported(token);
        }
        _;
    }

    /// @notice Validates that user has sufficient USDC balance
    /// @param amount The amount to check
    modifier hasBalance(uint256 amount) {
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        _;
    }

    /// @notice Validates that withdrawal is within per-transaction limit
    /// @param amount The withdrawal amount to validate
    modifier withinWithdrawalLimit(uint256 amount) {
        if (amount > MAX_WITHDRAW_PER_TX) revert WithdrawalLimitExceeded();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Initializes KipuBankV3 with deployment parameters
    /// @param _bankCapUSD Maximum total USDC deposits allowed (with 6 decimals)
    /// @param _maxWithdrawPerTx Maximum withdrawal per transaction (with 6 decimals)
    /// @param _uniswapV2Router Address of Uniswap V2 Router02
    /// @param _usdc Address of USDC token contract
    /// @dev All parameters are validated to be non-zero, USDC is auto-whitelisted
    constructor(
        uint256 _bankCapUSD,
        uint256 _maxWithdrawPerTx,
        address _uniswapV2Router,
        address _usdc
    ) Ownable(msg.sender) {
        // Validate constructor parameters
        if (
            _bankCapUSD == 0 ||
            _maxWithdrawPerTx == 0 ||
            _uniswapV2Router == address(0) ||
            _usdc == address(0)
        ) {
            revert InvalidParameter();
        }

        // Set immutable variables
        bankCapUSD = _bankCapUSD;
        MAX_WITHDRAW_PER_TX = _maxWithdrawPerTx;
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        usdc = _usdc;
        weth = uniswapV2Router.WETH();

        // Auto-whitelist USDC (no swap needed for direct USDC deposits)
        supportedTokens[_usdc] = true;
        emit TokenAdded(_usdc);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - DEPOSITS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Deposits ETH into the caller's vault, automatically converting to USDC
    /// @dev Wraps ETH to WETH, swaps via Uniswap V2, credits USDC balance
    /// @dev Emits DepositMade event on success, reverts if bank cap exceeded or swap fails
    function depositETH()
        external
        payable
        nonReentrant
        whenNotPaused
        validAmount(msg.value)
    {
        // 1. Checks & Interactions: Wrap ETH to WETH
        IWETH(weth).deposit{value: msg.value}();

        // 2. Interactions: Swap WETH → USDC
        uint256 usdcReceived = _swapToUSDC(weth, msg.value);

        // 3. Checks: Validate bank cap AFTER swap (calculated value check allowed)
        if (totalDepositsUSDC + usdcReceived > bankCapUSD) {
            revert BankCapExceeded();
        }

        // 4. Effects: Update state in unchecked block (CEI pattern)
        unchecked {
            balances[msg.sender] += usdcReceived;
            depositCount[msg.sender] += 1;
            totalDepositsUSDC += usdcReceived;
        }

        emit DepositMade(msg.sender, address(0), msg.value, usdcReceived);
    }

    /// @notice Deposits ERC-20 tokens into the caller's vault, converting to USDC if needed
    /// @param token The ERC-20 token address to deposit (must be whitelisted)
    /// @param amount The amount of tokens to deposit
    /// @dev If token is USDC, no swap occurs. Otherwise swaps via Uniswap V2
    /// @dev Emits DepositMade event on success, reverts if bank cap exceeded or swap fails
    function deposit(
        address token,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        validAmount(amount)
        supportedToken(token)
    {
        uint256 usdcReceived;

        // 1. Checks: Transfer token from user to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // 2. Conditional swap logic
        if (token == usdc) {
            // Direct USDC deposit - no swap needed (gas optimization)
            usdcReceived = amount;
        } else {
            // Swap token → USDC via Uniswap
            usdcReceived = _swapToUSDC(token, amount);
        }

        // 3. Checks: Validate bank cap AFTER swap (calculated value check allowed)
        if (totalDepositsUSDC + usdcReceived > bankCapUSD) {
            revert BankCapExceeded();
        }

        // 4. Effects: Update state in unchecked block (CEI pattern)
        unchecked {
            balances[msg.sender] += usdcReceived;
            depositCount[msg.sender] += 1;
            totalDepositsUSDC += usdcReceived;
        }

        emit DepositMade(msg.sender, token, amount, usdcReceived);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - WITHDRAWALS
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Withdraws USDC from the caller's vault
    /// @param usdcAmount The amount of USDC to withdraw (with 6 decimals)
    /// @dev Withdrawals are always enabled (not affected by pause state)
    /// @dev Emits WithdrawalMade event on success, reverts if insufficient balance or limit exceeded
    function withdraw(
        uint256 usdcAmount
    )
        external
        nonReentrant
        validAmount(usdcAmount)
        hasBalance(usdcAmount)
        withinWithdrawalLimit(usdcAmount)
    {
        // 1. Effects: Update state BEFORE external call (CEI pattern)
        unchecked {
            balances[msg.sender] -= usdcAmount;
            withdrawalCount[msg.sender] += 1;
            totalDepositsUSDC -= usdcAmount;
        }

        // 2. Interactions: Transfer USDC to user
        IERC20(usdc).safeTransfer(msg.sender, usdcAmount);

        emit WithdrawalMade(msg.sender, usdcAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - ADMIN
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Adds a token to the whitelist after validating Uniswap pair exists
    /// @param token The ERC-20 token address to whitelist
    /// @dev Only owner can call. Validates that token/USDC pair exists on Uniswap
    /// @dev Emits TokenAdded event on success, reverts if invalid pair
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert InvalidParameter();

        // Validate Uniswap pair exists (skip for USDC)
        if (token != usdc) {
            _validateUniswapPair(token);
        }

        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    /// @notice Removes a token from the whitelist
    /// @param token The ERC-20 token address to remove
    /// @dev Only owner can call. Cannot remove USDC from whitelist
    /// @dev Emits TokenRemoved event on success
    function removeSupportedToken(address token) external onlyOwner {
        if (token == usdc) revert InvalidParameter();

        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }

    /// @notice Pauses or unpauses deposits (withdrawals always enabled)
    /// @param pause True to pause deposits, false to unpause
    /// @dev Only owner can call. Emits DepositsPaused event
    function pauseDeposits(bool pause) external onlyOwner {
        depositsPaused = pause;
        emit DepositsPaused(pause);
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // EXTERNAL FUNCTIONS - VIEW
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Returns the USDC balance of a user
    /// @param user The address to query
    /// @return The user's USDC balance (with 6 decimals)
    function getVaultBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /// @notice Returns the number of deposits made by a user
    /// @param user The address to query
    /// @return The deposit count
    function getUserDepositCount(address user) external view returns (uint256) {
        return depositCount[user];
    }

    /// @notice Returns the number of withdrawals made by a user
    /// @param user The address to query
    /// @return The withdrawal count
    function getUserWithdrawalCount(
        address user
    ) external view returns (uint256) {
        return withdrawalCount[user];
    }

    /// @notice Returns the remaining deposit capacity before hitting bank cap
    /// @return The remaining USDC capacity (with 6 decimals)
    function getRemainingCapacity() external view returns (uint256) {
        unchecked {
            return bankCapUSD - totalDepositsUSDC;
        }
    }

    /// @notice Checks if a token is whitelisted
    /// @param token The token address to check
    /// @return True if token is supported, false otherwise
    function isTokenSupported(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    /// @notice Returns the total USDC deposited in the bank
    /// @return The total USDC deposits (with 6 decimals)
    function getTotalDeposits() external view returns (uint256) {
        return totalDepositsUSDC;
    }

    // ═══════════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS - UNISWAP INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════════

    /// @notice Swaps a token to USDC via Uniswap V2 with slippage protection
    /// @param tokenIn The token to swap from
    /// @param amountIn The amount of tokenIn to swap
    /// @return usdcReceived The amount of USDC received from the swap
    /// @dev Approves exact amount → swaps → resets approval to 0 (security pattern)
    /// @dev Uses 2% slippage tolerance and 15-minute deadline
    function _swapToUSDC(
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 usdcReceived) {
        // Build swap path: tokenIn → USDC
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = usdc;

        // 1. Approve exact amount only (security: avoid infinite approval)
        IERC20(tokenIn).safeIncreaseAllowance(
            address(uniswapV2Router),
            amountIn
        );

        // 2. Calculate minimum output with slippage protection
        uint256 amountOutMin = _calculateMinOutput(tokenIn, amountIn);

        // 3. Execute swap with deadline protection
        uint256[] memory amounts = uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 900 // 15-minute deadline
        );

        usdcReceived = amounts[1];

        // 4. Validate swap output
        if (usdcReceived == 0) revert ZeroSwapOutput();

        // 5. Reset approval to 0 (security best practice)
        // Note: Router consumes exact allowance, so we explicitly set to 0
        IERC20(tokenIn).forceApprove(address(uniswapV2Router), 0);

        emit TokenSwapped(tokenIn, amountIn, usdcReceived);
    }

    /// @notice Calculates the minimum USDC output with slippage tolerance
    /// @param tokenIn The token to swap from
    /// @param amountIn The amount of tokenIn to swap
    /// @return minOutput The minimum acceptable USDC output (98% of expected)
    /// @dev Uses Uniswap's getAmountsOut to estimate output, applies 2% slippage
    function _calculateMinOutput(
        address tokenIn,
        uint256 amountIn
    ) internal view returns (uint256 minOutput) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = usdc;

        uint256[] memory amounts = uniswapV2Router.getAmountsOut(
            amountIn,
            path
        );
        uint256 expectedOutput = amounts[1];

        // Apply slippage tolerance: 98% of expected output
        unchecked {
            minOutput = (expectedOutput * SLIPPAGE_TOLERANCE) / 100;
        }
    }

    /// @notice Validates that a Uniswap V2 pair exists for token/USDC
    /// @param token The token to validate
    /// @dev Reverts with InvalidUniswapPair if pair doesn't exist or has no liquidity
    function _validateUniswapPair(address token) internal view {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = usdc;

        try uniswapV2Router.getAmountsOut(1e18, path) returns (
            uint256[] memory
        ) {
            // Pair exists and has liquidity
        } catch {
            revert InvalidUniswapPair();
        }
    }
}
