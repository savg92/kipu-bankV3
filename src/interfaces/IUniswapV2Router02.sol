// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Uniswap V2 Router02 Interface
/// @notice Interface for Uniswap V2 Router with token swapping functionality
/// @dev Used for swapping tokens to USDC on deposits
interface IUniswapV2Router02 {
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible
    /// @param amountIn The amount of input tokens to send
    /// @param amountOutMin The minimum amount of output tokens that must be received
    /// @param path An array of token addresses representing the swap path
    /// @param to Recipient of the output tokens
    /// @param deadline Unix timestamp after which the transaction will revert
    /// @return amounts The input token amount and all subsequent output token amounts
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Given an input amount of an asset and pair reserves, returns the maximum output amount
    /// @param amountIn The amount of input tokens
    /// @param path An array of token addresses representing the swap path
    /// @return amounts The input token amount and all subsequent output token amounts
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    /// @notice Returns the address of the WETH contract
    /// @return The WETH contract address
    function WETH() external pure returns (address);
}
