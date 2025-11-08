# 🏦 KipuBank V2

> Production-grade multi-token vault with Chainlink price oracles and role-based access control

## Overview

**KipuBank V2** is an advanced decentralized vault showcasing professional Solidity development. It supports ETH and ERC-20 token deposits with USD-denominated bank caps enforced via Chainlink price oracles, demonstrating production-ready security patterns and architectural best practices.

### Key Features

- **Multi-Token Support**: Deposit and withdraw ETH and whitelisted ERC-20 tokens
- **Chainlink Oracle Integration**: Real-time ETH/USD price feeds for accurate USD valuation
- **USD-Denominated Accounting**: Bank cap enforced in USD across all supported assets
- **Role-Based Access Control**: Owner-managed token whitelist and emergency controls
- **Decimal Normalization**: Automatic handling of 6, 8, and 18 decimal tokens
- **Advanced Security**: ReentrancyGuard, SafeERC20, CEI pattern, comprehensive custom errors
- **Gas Optimizations**: Storage caching, unchecked arithmetic, immutable variables
- **Complete Documentation**: NatSpec on all public/external functions, comprehensive README

## Technology Stack

- **Language**: Solidity ^0.8.24
- **Framework**: Foundry (forge, anvil, cast)
- **Dependencies**: OpenZeppelin Contracts, Chainlink Contracts
- **Network**: Sepolia Testnet (Chain ID: 11155111)
- **License**: MIT

## 🚀 Deployment

✅ **Deployed to Sepolia Testnet - Fully Verified**

| Property                   | Value                                                                                                                           |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Contract Address**       | [`0xe1b858d11bbbd3565a883a83352521765645b19f`](https://sepolia.etherscan.io/address/0xe1b858d11bbbd3565a883a83352521765645b19f) |
| **Network**                | Sepolia (Chain ID: 11155111)                                                                                                    |
| **Deployment Tx**          | [`0xc172a48c...`](https://sepolia.etherscan.io/tx/0xc172a48c046535f51c3e92698e0e4024c53b20c998f9206b239935372dc5d38c)           |
| **Etherscan Verification** | ✅ [Verified Source Code](https://sepolia.etherscan.io/address/0xe1b858d11bbbd3565a883a83352521765645b19f#code)                 |
| **Bank Cap**               | 100,000 USDC (USD-denominated)                                                                                                  |
| **Max Withdrawal**         | 1 ETH per transaction                                                                                                           |
| **Price Feed**             | Chainlink ETH/USD (Sepolia)                                                                                                     |

### 📊 Contract Specifications

```
Constructor Parameters:
├── bankCapUSD: 100,000,000,000 (100,000 USDC with 6 decimals)
├── maxWithdrawPerTx: 1,000,000,000,000,000,000 (1 ETH in wei)
└── ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306

Contract Features:
├── Multi-token support (ETH + ERC-20 whitelist)
├── USD-denominated accounting (6 decimal normalization)
├── Real-time price feeds (Chainlink oracles)
├── Role-based access control (Ownable)
└── Advanced security (ReentrancyGuard, SafeERC20)
```

### 🔗 Interact with Contract

**Option 1: Etherscan Interface** (Recommended for beginners)

1. Visit the [Contract on Etherscan](https://sepolia.etherscan.io/address/0xe1b858d11bbbd3565a883a83352521765645b19f)
2. Go to **"Read Contract"** tab to query balances and settings
3. Go to **"Write Contract"** tab to deposit/withdraw (requires connected wallet with Sepolia ETH)

## 💻 Usage Examples

### Deposit ETH (Using cast)

```bash
# Deposit 0.1 ETH to your vault
cast send 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "deposit(address,uint256)" \
  "0x0000000000000000000000000000000000000000" \
  "100000000000000000" \
  --value 0.1ether \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

**Parameters**:

- `token`: `0x0000000000000000000000000000000000000000` (ETH address, not applicable for ETH)
- `amount`: `100000000000000000` (amount in wei, must match `--value`)
- `--value`: ETH to deposit (0.1 ETH in this example)

### Check Your Balance

```bash
# Query your vault balance for ETH
cast call 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "getVaultBalance(address,address)(uint256)" \
  "YOUR_ADDRESS" \
  "0x0000000000000000000000000000000000000000" \
  --rpc-url sepolia
```

**Returns**: Your ETH balance in wei (6-decimal USDC-normalized value)

### Withdraw ETH

```bash
# Withdraw 0.05 ETH from your vault
cast send 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "withdraw(address,uint256)" \
  "0x0000000000000000000000000000000000000000" \
  "50000000000000000" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

### Check Bank Status

```bash
# Get current bank cap in USD
cast call 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "bankCapUSD()(uint256)" \
  --rpc-url sepolia

# Get total deposits in USD
cast call 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "totalDepositsUSD()(uint256)" \
  --rpc-url sepolia

# Get current ETH price in USD
cast call 0xe1b858d11bbbd3565a883a83352521765645b19f \
  "getLatestETHPrice()(int256)" \
  --rpc-url sepolia
```

## 🛠️ Development & Testing

### Prerequisites

```bash
# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and install dependencies
git clone https://github.com/savg92/kipu-bankV2.git
cd kipu-bankV2
forge install
```

### Build

```bash
# Compile all contracts
forge build

# Compile with optimizer settings
forge build --optimize
```

### Test

```bash
# Run all tests with verbose output
forge test -vv

# Run specific test
forge test --match-test testDepositETH -vv

# Generate gas report
forge test --gas-report
```

### Format Code

```bash
# Format Solidity files
forge fmt

# Check formatting without modifying
forge fmt --check
```

### Deploy Locally (Anvil)

```bash
# Terminal 1: Start local blockchain
anvil

# Terminal 2: Deploy contract
forge script script/DeployKipuBankV2.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb476cad82b3cd5e4f002b2fdbf7e
```

### Deploy to Sepolia

```bash
# Prerequisites: Set environment variables
export PRIVATE_KEY=your_sepolia_private_key
export ETHERSCAN_API_KEY=your_etherscan_api_key

# Deploy and verify
forge script script/DeployKipuBankV2.s.sol \
  --rpc-url sepolia \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --private-key $PRIVATE_KEY
```

## 🏗️ Project Structure

```
kipu-bankV2/
├── src/
│   └── KipuBankV2.sol            # Main contract (Foundry standard)
├── script/
│   └── DeployKipuBankV2.s.sol    # Foundry deployment script
├── test/
│   └── KipuBankV2.t.sol          # Comprehensive test suite (43 tests)
├── lib/
│   └── forge-std/                # Foundry standard library
├── foundry.toml                   # Foundry configuration
└── README.md                      # This file
```

**Note**: This project uses Foundry's standard directory structure with contracts in `/src/`.

## 🔐 Security Features

### Module 4 Compliance (Production-Grade Patterns)

- ✅ **Modifiers-Only Validation**: All input validation through modifiers (zero inline checks)
- ✅ **Comprehensive Unchecked Blocks**: All safe arithmetic wrapped for gas optimization
- ✅ **Zero Redundancy**: No duplicate validation checks
- ✅ **Single Source Location**: Contract in `/src/` following Foundry standards

### Access Control

- ✅ **Ownable**: Only contract owner can manage token whitelist and emergency controls
- ✅ **OnlyOwner Modifier**: Restricts administrative functions to owner

### Safe Transfers

- ✅ **SafeERC20**: Safe ERC-20 token transfers with revert handling
- ✅ **\_safeTransferETH**: Custom ETH transfer with validation

### Reentrancy Protection

- ✅ **ReentrancyGuard**: Prevents reentrancy attacks on deposit/withdraw
- ✅ **CEI Pattern**: Checks-Effects-Interactions ordering

### Error Handling

- ✅ **Custom Errors Only**: Gas-efficient error codes (no strings)
- ✅ **15 Custom Errors**: Comprehensive error coverage including context-specific validation
- ✅ **Stale Price Detection**: Validates Chainlink oracle data freshness

### Validation Architecture

- ✅ **7 Validation Modifiers**: `validDepositAmount`, `validWithdrawalAmount`, `hasBalance`, `withinWithdrawalLimit`, `withinBankCap`, `supportedToken`, `whenNotPaused`
- ✅ **Clean Function Bodies**: All validation delegated to modifiers
- ✅ **Single Responsibility**: Each modifier validates one specific concern

### Gas Optimizations

- ✅ **Immutable Variables**: `bankCapUSD`, `MAX_WITHDRAW_PER_TX`, `ethUsdPriceFeed`
- ✅ **Unchecked Arithmetic**: Safe unchecked operations for gas savings
- ✅ **Storage Caching**: Minimize state variable reads

## 📊 Testing & Verification

**Test Coverage**: 43/43 tests passing (100% success rate)

```
Test Categories:
├── Deployment Tests (3 tests)
├── Deposit Tests (8 tests)
├── Withdrawal Tests (6 tests)
├── Balance Tracking (4 tests)
├── Multi-Token Tests (5 tests)
├── Oracle Integration (4 tests)
├── Access Control (3 tests)
├── Error Handling (7 tests)
├── Edge Cases (3 tests)
└── Gas Optimization Validation (Module 4)
```

**Gas Optimization**: ~3-5% improvement from unchecked arithmetic after validation

**Verification**: ✅ [Etherscan Verified](https://sepolia.etherscan.io/address/0xe1b858d11bbbd3565a883a83352521765645b19f#code)
