// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {KipuBankV2} from "../src/KipuBankV2.sol";

/// @title DeployKipuBankV2
/// @notice Foundry script to deploy KipuBankV2 to Sepolia testnet
/// @dev Uses forge script with --broadcast flag for deployment
contract DeployKipuBankV2 is Script {
    // Deployment parameters
    uint256 public constant BANK_CAP_USD = 100_000 * 10 ** 6; // 100,000 USDC (6 decimals)
    uint256 public constant MAX_WITHDRAW_PER_TX = 1 ether; // 1 ETH

    // Sepolia Chainlink ETH/USD price feed
    // Source: https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1#sepolia-testnet
    address public constant SEPOLIA_ETH_USD_FEED =
        0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external returns (KipuBankV2) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("========================================");
        console2.log("Deploying KipuBankV2 to Sepolia Testnet");
        console2.log("========================================");
        console2.log("Deployer address:", vm.addr(deployerPrivateKey));
        console2.log("Bank Cap (USD):", BANK_CAP_USD / 10 ** 6, "USDC");
        console2.log(
            "Max Withdraw Per TX:",
            MAX_WITHDRAW_PER_TX / 1 ether,
            "ETH"
        );
        console2.log("ETH/USD Price Feed:", SEPOLIA_ETH_USD_FEED);
        console2.log("");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy KipuBankV2
        KipuBankV2 bank = new KipuBankV2(
            BANK_CAP_USD,
            MAX_WITHDRAW_PER_TX,
            SEPOLIA_ETH_USD_FEED
        );

        // Stop broadcasting
        vm.stopBroadcast();

        console2.log("========================================");
        console2.log("Deployment Successful!");
        console2.log("========================================");
        console2.log("KipuBankV2 Address:", address(bank));
        console2.log("");
        console2.log("Next steps:");
        console2.log("1. Verify contract on Etherscan:");
        console2.log(
            "   forge verify-contract",
            address(bank),
            "KipuBankV2 --chain sepolia"
        );
        console2.log(
            "2. Add supported ERC-20 tokens using addSupportedToken()"
        );
        console2.log("3. Test deposits and withdrawals via Etherscan");
        console2.log("========================================");

        return bank;
    }
}
