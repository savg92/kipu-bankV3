// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockWETH
/// @notice Mock WETH contract for testing
contract MockWETH is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf(msg.sender) >= wad, "Insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }
}

/// @title MockUSDC
/// @notice Mock USDC contract for testing (6 decimals)
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockERC20
/// @notice Generic mock ERC20 for testing other tokens
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title MockUniswapV2Router
/// @notice Mock Uniswap V2 Router for testing swaps
/// @dev Simplified router that simulates swaps with fixed exchange rates
contract MockUniswapV2Router {
    address private immutable _weth;
    address private immutable _usdc;

    constructor(address weth_, address usdc_) {
        _weth = weth_;
        _usdc = usdc_;
    }

    function WETH() external view returns (address) {
        return _weth;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external returns (uint256[] memory amounts) {
        require(path.length == 2, "Invalid path");
        require(path[1] == _usdc, "Output must be USDC");

        // Transfer input token from sender
        ERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Calculate output amount (simulate 1 ETH = $2000, 1 DAI = $1)
        uint256 amountOut;
        if (path[0] == _weth) {
            // WETH → USDC: 1 ETH = 2000 USDC
            amountOut = (amountIn * 2000) / 1e18 * 1e6; // Convert 18 decimals to 6
        } else {
            // Assume other tokens are 1:1 with USDC (18 decimals → 6 decimals)
            amountOut = amountIn / 1e12; // Convert 18 decimals to 6
        }

        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Mint USDC to recipient (simplified - real router would transfer)
        MockUSDC(_usdc).mint(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        require(path.length == 2, "Invalid path");
        require(path[1] == _usdc, "Output must be USDC");

        uint256 amountOut;
        if (path[0] == _weth) {
            // WETH → USDC: 1 ETH = 2000 USDC
            amountOut = (amountIn * 2000) / 1e18 * 1e6;
        } else {
            // Other tokens 1:1 with USDC
            amountOut = amountIn / 1e12;
        }

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }
}

/// @title DeployComplete
/// @notice Complete deployment script that deploys all contracts including mocks
/// @dev Deploys WETH, USDC, Router, DAI, and KipuBankV3 in correct order
contract DeployComplete is Script {
    // Deployment parameters
    uint256 constant BANK_CAP_USDC = 100_000_000_000; // 100,000 USDC (6 decimals)
    uint256 constant MAX_WITHDRAW_PER_TX = 1_000_000_000; // 1,000 USDC (6 decimals)

    struct DeploymentAddresses {
        address weth;
        address usdc;
        address router;
        address dai;
        address bank;
    }

    function run() external returns (DeploymentAddresses memory) {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("KipuBankV3 Complete Deployment");
        console.log("========================================");
        console.log("Deployer:", deployer);
        console.log("Network: Sepolia Testnet");
        console.log("========================================");
        console.log("Deployer Balance:", deployer.balance);
        require(deployer.balance > 0, "Deployer has no ETH for gas");
        console.log("========================================");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying mock contracts...");

        // 1. Deploy WETH
        MockWETH weth = new MockWETH();
        console.log("  WETH deployed:", address(weth));

        // 2. Deploy USDC
        MockUSDC usdc = new MockUSDC();
        console.log("  USDC deployed:", address(usdc));

        // 3. Deploy Uniswap V2 Router
        MockUniswapV2Router router = new MockUniswapV2Router(
            address(weth),
            address(usdc)
        );
        console.log("  Router deployed:", address(router));

        // 4. Deploy DAI (for testing token swaps)
        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        console.log("  DAI deployed:", address(dai));

        console.log("========================================");
        console.log("Deploying KipuBankV3...");

        // 5. Deploy KipuBankV3
        KipuBankV3 bank = new KipuBankV3(
            BANK_CAP_USDC,
            MAX_WITHDRAW_PER_TX,
            address(router),
            address(usdc)
        );
        console.log("  KipuBankV3 deployed:", address(bank));

        // 6. Add DAI to supported tokens
        bank.addSupportedToken(address(dai));
        console.log("  DAI added to whitelist");

        // 7. Mint some test tokens to deployer
        usdc.mint(deployer, 1000_000_000); // 1,000 USDC
        dai.mint(deployer, 1000 ether); // 1,000 DAI
        console.log("  Test tokens minted to deployer");

        vm.stopBroadcast();

        // Post-deployment verification
        console.log("========================================");
        console.log("Deployment Successful!");
        console.log("========================================");
        console.log("Contract Addresses:");
        console.log("  WETH:", address(weth));
        console.log("  USDC:", address(usdc));
        console.log("  Uniswap Router:", address(router));
        console.log("  DAI:", address(dai));
        console.log("  KipuBankV3:", address(bank));
        console.log("========================================");
        console.log("KipuBankV3 Configuration:");
        console.log("  Owner:", bank.owner());
        console.log("  Bank Cap:", bank.bankCapUSD());
        console.log("  Max Withdraw/TX:", bank.MAX_WITHDRAW_PER_TX());
        console.log("  WETH Address:", bank.weth());
        console.log("  USDC Address:", bank.usdc());
        console.log("  USDC Whitelisted:", bank.isTokenSupported(address(usdc)));
        console.log("  DAI Whitelisted:", bank.isTokenSupported(address(dai)));
        console.log("  Deposits Paused:", bank.depositsPaused());
        console.log("========================================");
        console.log("Test Token Balances (Deployer):");
        console.log("  USDC:", usdc.balanceOf(deployer));
        console.log("  DAI:", dai.balanceOf(deployer));
        console.log("========================================");
        console.log("Next Steps:");
        console.log("1. Verify contracts on Etherscan:");
        console.log("   forge verify-contract", address(bank));
        console.log("   src/KipuBankV3.sol:KipuBankV3 --chain sepolia");
        console.log("");
        console.log("2. Test deposits:");
        console.log("   - depositETH: Send ETH to swap for USDC");
        console.log("   - deposit(USDC): Direct USDC deposit");
        console.log("   - deposit(DAI): DAI swap to USDC");
        console.log("");
        console.log("3. Test withdrawals:");
        console.log("   - withdraw(amount): Withdraw USDC (max 1000 USDC/tx)");
        console.log("========================================");

        return
            DeploymentAddresses({
                weth: address(weth),
                usdc: address(usdc),
                router: address(router),
                dai: address(dai),
                bank: address(bank)
            });
    }
}
