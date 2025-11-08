// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Wrapped Ether (WETH) Interface
/// @notice Interface for WETH contract to wrap/unwrap ETH
/// @dev Used for wrapping ETH before swapping via Uniswap
interface IWETH {
    /// @notice Wraps ETH to WETH
    /// @dev Deposits ETH and mints equivalent WETH to sender
    function deposit() external payable;

    /// @notice Unwraps WETH to ETH
    /// @dev Burns WETH and sends equivalent ETH to sender
    /// @param amount Amount of WETH to unwrap
    function withdraw(uint256 amount) external;

    /// @notice Standard ERC20 approve function
    /// @param spender Address to approve
    /// @param amount Amount to approve
    /// @return success True if approval succeeded
    function approve(
        address spender,
        uint256 amount
    ) external returns (bool success);

    /// @notice Standard ERC20 transfer function
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @return success True if transfer succeeded
    function transfer(
        address to,
        uint256 amount
    ) external returns (bool success);

    /// @notice Standard ERC20 balanceOf function
    /// @param account Address to check balance
    /// @return balance Token balance
    function balanceOf(address account) external view returns (uint256 balance);
}
