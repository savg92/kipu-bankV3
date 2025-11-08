// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";

/// @title DeployKipuBankV3
/// @notice Deployment script for KipuBankV3 contract on Sepolia testnet
/// @dev Uses Foundry's Script contract for deployment automation
contract DeployKipuBankV3 is Script {
    // Sepolia testnet addresses
    address constant SEPOLIA_UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // Deployment parameters
    uint256 constant BANK_CAP_USDC = 100_000_000_000; // 100,000 USDC (6 decimals)
    uint256 constant MAX_WITHDRAW_PER_TX = 1_000_000_000; // 1,000 USDC (6 decimals)

    function run() external returns (KipuBankV3) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("KipuBankV3 Deployment Script");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Sepolia Testnet");
        console.log("========================================");
        console.log("Deployment Parameters:");
        console.log("  Bank Cap (USDC):", BANK_CAP_USDC);
        console.log("  Max Withdrawal/TX:", MAX_WITHDRAW_PER_TX);
        console.log("  Uniswap V2 Router:", SEPOLIA_UNISWAP_V2_ROUTER);
        console.log("  USDC Address:", SEPOLIA_USDC);
        console.log("========================================");

        // Verify deployer has balance
        uint256 balance = deployer.balance;
        console.log("Deployer Balance:", balance);
        require(balance > 0, "Deployer has no ETH for gas");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy KipuBankV3
        KipuBankV3 bank = new KipuBankV3(
            BANK_CAP_USDC,
            MAX_WITHDRAW_PER_TX,
            SEPOLIA_UNISWAP_V2_ROUTER,
            SEPOLIA_USDC
        );

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("Contract Address:", address(bank));
        console.log("Owner:", bank.owner());
        console.log("Bank Cap:", bank.bankCapUSD());
        console.log("Max Withdraw/TX:", bank.MAX_WITHDRAW_PER_TX());
        console.log("Uniswap Router:", address(bank.uniswapV2Router()));
        console.log("USDC Address:", bank.usdc());
        console.log("WETH Address:", bank.weth());
        console.log("USDC Whitelisted:", bank.isTokenSupported(SEPOLIA_USDC));
        console.log("Deposits Paused:", bank.depositsPaused());
        console.log("========================================");
        console.log("Next Steps:");
        console.log("1. Verify contract on Etherscan:");
        console.log("   forge verify-contract", address(bank));
        console.log("   src/KipuBankV3.sol:KipuBankV3");
        console.log("   --chain sepolia --watch");
        console.log("2. Add supported tokens (if needed)");
        console.log("3. Test deposit/withdraw functionality");
        console.log("========================================");

        return bank;
    }
}
