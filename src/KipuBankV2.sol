// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title KipuBankV2
/// @notice Production-grade multi-token vault with Chainlink price oracles
/// @dev Implements CEI pattern, ReentrancyGuard, and role-based access control
/// @custom:security-contact security@kipubank.example
contract KipuBankV2 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== TYPE DECLARATIONS ==========

    /// @notice Token configuration structure
    /// @param isSupported Whether token is whitelisted
    /// @param decimals Token decimal places
    /// @param priceFeed Chainlink price feed address
    struct TokenInfo {
        bool isSupported;
        uint8 decimals;
        address priceFeed;
    }

    // ========== CONSTANTS ==========

    /// @notice USDC decimal places (standard for USD accounting)
    uint8 private constant USDC_DECIMALS = 6;

    /// @notice ETH decimal places
    uint8 private constant ETH_DECIMALS = 18;

    /// @notice Chainlink price feed decimal places
    uint8 private constant CHAINLINK_DECIMALS = 8;

    /// @notice Address representation for native ETH
    address private constant ETH_ADDRESS = address(0);

    // ========== STATE VARIABLES ==========

    /// @notice Maximum withdrawal per transaction (in wei for ETH)
    uint256 public immutable MAX_WITHDRAW_PER_TX;

    /// @notice Bank capacity in USD (6 decimals)
    uint256 public immutable bankCapUSD;

    /// @notice ETH/USD Chainlink price feed
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    /// @notice Total deposits in USD value (6 decimals)
    uint256 public totalDepositsUSD;

    /// @notice Deposits paused flag
    bool public depositsPaused;

    /// @notice User balances: user => token => balance
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice User deposit counters
    mapping(address => uint256) private depositCount;

    /// @notice User withdrawal counters
    mapping(address => uint256) private withdrawalCount;

    /// @notice Supported token configurations
    mapping(address => TokenInfo) public supportedTokens;

    // ========== CUSTOM ERRORS ==========

    /// @notice Deposit exceeds bank cap
    error BankCapExceeded();

    /// @notice Insufficient user balance
    error InsufficientBalance();

    /// @notice Withdrawal exceeds tx limit
    error WithdrawalLimitExceeded();

    /// @notice ETH transfer failed
    error TransferFailed();

    /// @notice Invalid bank cap (zero)
    error InvalidBankCap();

    /// @notice Invalid max withdraw (zero)
    error InvalidMaxWithdraw();

    /// @notice Zero deposit amount
    error ZeroDepositAmount();

    /// @notice Zero withdrawal amount
    error ZeroWithdrawalAmount();

    /// @notice Token not supported
    /// @param token Token address attempted
    error TokenNotSupported(address token);

    /// @notice Stale price from oracle
    error StalePrice();

    /// @notice Invalid price feed address
    error InvalidPriceFeed();

    /// @notice Deposits are currently paused
    error DepositsArePaused();

    /// @notice Invalid ETH amount sent
    error InvalidETHAmount();

    /// @notice Cannot send ETH with token deposit
    error UnexpectedETHSent();

    // ========== EVENTS ==========

    /// @notice Emitted on successful deposit
    /// @param user Depositor address
    /// @param token Token address (0x0 for ETH)
    /// @param amount Token amount deposited
    /// @param valueUSD USD value of deposit (6 decimals)
    event DepositMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 valueUSD
    );

    /// @notice Emitted on successful withdrawal
    /// @param user Withdrawer address
    /// @param token Token address (0x0 for ETH)
    /// @param amount Token amount withdrawn
    /// @param valueUSD USD value of withdrawal (6 decimals)
    event WithdrawalMade(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 valueUSD
    );

    /// @notice Emitted when bank cap is updated
    /// @param oldCap Previous bank cap in USD
    /// @param newCap New bank cap in USD
    event BankCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Emitted when deposits are paused/unpaused
    /// @param isPaused New paused state
    event DepositsToggled(bool isPaused);

    /// @notice Emitted when a token is added to whitelist
    /// @param token Token address
    /// @param decimals Token decimals
    /// @param priceFeed Chainlink price feed address
    event TokenAdded(address indexed token, uint8 decimals, address priceFeed);

    /// @notice Emitted when a token is removed from whitelist
    /// @param token Token address
    event TokenRemoved(address indexed token);

    // ========== MODIFIERS ==========

    /// @notice Validates token is supported
    /// @param token Token address to validate
    modifier supportedToken(address token) {
        if (token != ETH_ADDRESS && !supportedTokens[token].isSupported) {
            revert TokenNotSupported(token);
        }
        _;
    }

    /// @notice Validates deposits are not paused
    modifier whenNotPaused() {
        if (depositsPaused) revert DepositsArePaused();
        _;
    }

    /// @notice Validates deposit amount is not zero
    /// @param _amount Amount to validate
    modifier validDepositAmount(uint256 _amount) {
        if (_amount == 0) revert ZeroDepositAmount();
        _;
    }

    /// @notice Validates withdrawal amount is not zero
    /// @param _amount Amount to validate
    modifier validWithdrawalAmount(uint256 _amount) {
        if (_amount == 0) revert ZeroWithdrawalAmount();
        _;
    }

    /// @notice Validates deposit doesn't exceed bank cap
    /// @param depositValueUSD USD value of deposit to validate
    modifier withinBankCap(uint256 depositValueUSD) {
        if (totalDepositsUSD + depositValueUSD > bankCapUSD) {
            revert BankCapExceeded();
        }
        _;
    }

    /// @notice Validates user has sufficient balance
    /// @param token Token address
    /// @param amount Amount to validate
    modifier hasBalance(address token, uint256 amount) {
        if (amount > balances[msg.sender][token]) {
            revert InsufficientBalance();
        }
        _;
    }

    /// @notice Validates withdrawal is within transaction limit
    /// @param amount Amount to validate
    modifier withinWithdrawalLimit(uint256 amount) {
        if (amount > MAX_WITHDRAW_PER_TX) {
            revert WithdrawalLimitExceeded();
        }
        _;
    }

    // ========== CONSTRUCTOR ==========

    /// @notice Initializes KipuBankV2 with limits and oracle
    /// @param _bankCapUSD Max total deposits in USD (6 decimals)
    /// @param _maxWithdraw Max per-tx withdrawal in wei
    /// @param _ethUsdPriceFeed Chainlink ETH/USD price feed address
    constructor(
        uint256 _bankCapUSD,
        uint256 _maxWithdraw,
        address _ethUsdPriceFeed
    ) Ownable(msg.sender) {
        if (_bankCapUSD == 0) revert InvalidBankCap();
        if (_maxWithdraw == 0) revert InvalidMaxWithdraw();
        if (_ethUsdPriceFeed == address(0)) revert InvalidPriceFeed();

        bankCapUSD = _bankCapUSD;
        MAX_WITHDRAW_PER_TX = _maxWithdraw;
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
    }

    // ========== EXTERNAL FUNCTIONS ==========

    /// @notice Deposit ETH or ERC-20 tokens to vault
    /// @dev Uses CEI pattern and ReentrancyGuard. All state updates in unchecked blocks for gas efficiency
    /// @param token Token address (use address(0) for ETH)
    /// @param amount Token amount to deposit (must match msg.value for ETH)
    function deposit(
        address token,
        uint256 amount
    )
        external
        payable
        nonReentrant
        supportedToken(token)
        whenNotPaused
        validDepositAmount(amount)
    {
        // Calculate USD value and check bank cap using modifier
        uint256 depositValueUSD = getTokenValueInUSD(token, amount);

        // Validate bank cap before proceeding
        if (totalDepositsUSD + depositValueUSD > bankCapUSD) {
            revert BankCapExceeded();
        }

        // Handle ETH vs ERC-20 (Interactions - but must happen before state changes for tokens)
        if (token == ETH_ADDRESS) {
            if (msg.value != amount) revert InvalidETHAmount();
        } else {
            if (msg.value > 0) revert UnexpectedETHSent();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Effects: Update state with unchecked blocks (safe after validation)
        unchecked {
            balances[msg.sender][token] += amount;
            depositCount[msg.sender] += 1;
            totalDepositsUSD += depositValueUSD;
        }

        emit DepositMade(msg.sender, token, amount, depositValueUSD);
    }

    /// @notice Withdraw ETH or ERC-20 tokens from vault
    /// @dev Uses CEI pattern and ReentrancyGuard. All validations via modifiers, all state updates in unchecked
    /// @param token Token address (use address(0) for ETH)
    /// @param amount Token amount to withdraw
    function withdraw(
        address token,
        uint256 amount
    )
        external
        nonReentrant
        supportedToken(token)
        validWithdrawalAmount(amount)
        hasBalance(token, amount)
        withinWithdrawalLimit(amount)
    {
        // Cache storage read
        uint256 userBalance = balances[msg.sender][token];

        // Calculate USD value for accounting
        uint256 withdrawalValueUSD = getTokenValueInUSD(token, amount);

        // Effects: All state updates in unchecked (safe after modifier validations)
        unchecked {
            // No need to check amount > userBalance again - modifier hasBalance already validated
            balances[msg.sender][token] = userBalance - amount;
            withdrawalCount[msg.sender] += 1;
            // Safe subtraction: totalDepositsUSD accumulated from deposits, withdrawalValueUSD <= user's contribution
            totalDepositsUSD -= withdrawalValueUSD;
        }

        emit WithdrawalMade(msg.sender, token, amount, withdrawalValueUSD);

        // Interactions
        if (token == ETH_ADDRESS) {
            _safeTransferETH(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /// @notice Get user vault balance for specific token
    /// @param user Address to query
    /// @param token Token address
    /// @return User's token balance
    function getVaultBalance(
        address user,
        address token
    ) external view returns (uint256) {
        return balances[user][token];
    }

    /// @notice Get user vault balance in USD
    /// @param user Address to query
    /// @param token Token address
    /// @return User's balance in USD (6 decimals)
    function getVaultBalanceInUSD(
        address user,
        address token
    ) external view returns (uint256) {
        uint256 balance = balances[user][token];
        if (balance == 0) return 0;
        return getTokenValueInUSD(token, balance);
    }

    /// @notice Get user deposit count
    /// @param user Address to query
    /// @return Deposit count
    function getDepositCount(address user) external view returns (uint256) {
        return depositCount[user];
    }

    /// @notice Get user withdrawal count
    /// @param user Address to query
    /// @return Withdrawal count
    function getWithdrawalCount(address user) external view returns (uint256) {
        return withdrawalCount[user];
    }

    /// @notice Get bank utilization percentage
    /// @return Utilization percentage (0-10000, where 10000 = 100.00%)
    function getBankUtilization() external view returns (uint256) {
        if (bankCapUSD == 0) return 0;
        return (totalDepositsUSD * 10000) / bankCapUSD;
    }

    /// @notice Get remaining bank capacity in USD
    /// @return Remaining capacity in USD (6 decimals)
    function getRemainingCapacity() external view returns (uint256) {
        if (totalDepositsUSD >= bankCapUSD) return 0;
        unchecked {
            // Safe: checked above that totalDepositsUSD < bankCapUSD
            return bankCapUSD - totalDepositsUSD;
        }
    }

    // ========== ADMIN FUNCTIONS ==========

    /// @notice Add supported token to whitelist
    /// @param token Token address
    /// @param decimals Token decimals
    /// @param priceFeed Chainlink price feed address
    function addSupportedToken(
        address token,
        uint8 decimals,
        address priceFeed
    ) external onlyOwner {
        if (token == ETH_ADDRESS) revert TokenNotSupported(token);
        if (priceFeed == address(0)) revert InvalidPriceFeed();

        supportedTokens[token] = TokenInfo({
            isSupported: true,
            decimals: decimals,
            priceFeed: priceFeed
        });

        emit TokenAdded(token, decimals, priceFeed);
    }

    /// @notice Remove supported token from whitelist
    /// @param token Token address
    function removeSupportedToken(address token) external onlyOwner {
        if (token == ETH_ADDRESS) revert TokenNotSupported(token);

        delete supportedTokens[token];

        emit TokenRemoved(token);
    }

    /// @notice Pause deposits for emergency
    function pauseDeposits() external onlyOwner {
        depositsPaused = true;
        emit DepositsToggled(true);
    }

    /// @notice Unpause deposits
    function unpauseDeposits() external onlyOwner {
        depositsPaused = false;
        emit DepositsToggled(false);
    }

    // ========== PUBLIC VIEW FUNCTIONS ==========

    /// @notice Get latest ETH price from Chainlink
    /// @return ETH price in USD (8 decimals)
    function getLatestETHPrice() public view returns (int256) {
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();

        if (timeStamp == 0) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();
        if (price <= 0) revert StalePrice();

        return price;
    }

    /// @notice Get ETH value in USD
    /// @param ethAmount Amount of ETH (18 decimals)
    /// @return USD value (6 decimals)
    function getETHValueInUSD(uint256 ethAmount) public view returns (uint256) {
        int256 ethUsdPrice = getLatestETHPrice(); // 8 decimals
        uint256 normalizedETH = normalizeToUSDC(ethAmount, ETH_DECIMALS);

        // ethUsdPrice has 8 decimals, normalize result to USDC decimals
        return
            (normalizedETH * uint256(ethUsdPrice)) / (10 ** CHAINLINK_DECIMALS);
    }

    /// @notice Get token value in USD
    /// @param token Token address (address(0) for ETH)
    /// @param amount Token amount
    /// @return USD value (6 decimals)
    function getTokenValueInUSD(
        address token,
        uint256 amount
    ) public view supportedToken(token) returns (uint256) {
        if (token == ETH_ADDRESS) {
            return getETHValueInUSD(amount);
        }

        TokenInfo memory tokenInfo = supportedTokens[token];
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            tokenInfo.priceFeed
        );

        (
            uint80 roundId,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        if (timeStamp == 0) revert StalePrice();
        if (answeredInRound < roundId) revert StalePrice();
        if (price <= 0) revert StalePrice();

        uint256 normalizedAmount = normalizeToUSDC(amount, tokenInfo.decimals);
        return (normalizedAmount * uint256(price)) / (10 ** CHAINLINK_DECIMALS);
    }

    /// @notice Normalize token amount to USDC base (6 decimals)
    /// @param amount Token amount
    /// @param tokenDecimals Token decimals
    /// @return Normalized amount (6 decimals)
    function normalizeToUSDC(
        uint256 amount,
        uint8 tokenDecimals
    ) public pure returns (uint256) {
        if (tokenDecimals > USDC_DECIMALS) {
            return amount / (10 ** (tokenDecimals - USDC_DECIMALS));
        } else if (tokenDecimals < USDC_DECIMALS) {
            return amount * (10 ** (USDC_DECIMALS - tokenDecimals));
        }
        return amount;
    }

    // ========== PRIVATE FUNCTIONS ==========

    /// @notice Safe ETH transfer
    /// @param to Recipient address
    /// @param amount ETH to transfer
    function _safeTransferETH(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
