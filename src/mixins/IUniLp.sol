// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/uniswap/IUniswapV2Pair.sol";
import "../libraries/UniUtils.sol";

import "./IBase.sol";
import "./ILp.sol";

// import "hardhat/console.sol";

abstract contract IUniLp is IBase, ILp {
	using SafeERC20 for IERC20;
	using UniUtils for IUniswapV2Pair;

	function pair() public view virtual returns (IUniswapV2Pair);

	function _getLiquidity() internal view virtual returns (uint256);

	// should only be called after oracle or user-input swap price check
	function _addLiquidity(uint256 amountToken0, uint256 amountToken1)
		internal
		override
		returns (uint256 liquidity)
	{
		underlying().safeTransfer(address(pair()), amountToken0);
		short().safeTransfer(address(pair()), amountToken1);
		liquidity = pair().mint(address(this));
	}

	function _removeLiquidity(uint256 liquidity) internal override returns (uint256, uint256) {
		IERC20(address(pair())).safeTransfer(address(pair()), liquidity);
		(address tokenA, ) = UniUtils._sortTokens(address(underlying()), address(short()));
		(uint256 amountToken0, uint256 amountToken1) = pair().burn(address(this));
		return
			tokenA == address(underlying())
				? (amountToken0, amountToken1)
				: (amountToken1, amountToken0);
	}

	function _quote(
		uint256 amount,
		address token0,
		address token1
	) internal view virtual override returns (uint256 price) {
		if (amount == 0) return 0;
		(uint256 reserve0, uint256 reserve1) = pair()._getPairReserves(token0, token1);
		price = UniUtils._quote(amount, reserve0, reserve1);
	}

	// fetches and sorts the reserves for a uniswap pair
	function getUnderlyingShortReserves() public view returns (uint256 reserveA, uint256 reserveB) {
		(reserveA, reserveB) = pair()._getPairReserves(address(underlying()), address(short()));
	}

	function _getLPBalances()
		internal
		view
		override
		returns (uint256 underlyingBalance, uint256 shortBalance)
	{
		uint256 totalLp = _getLiquidity();
		(uint256 totalUnderlyingBalance, uint256 totalShortBalance) = getUnderlyingShortReserves();
		uint256 total = pair().totalSupply();
		underlyingBalance = (totalUnderlyingBalance * totalLp) / total;
		shortBalance = (totalShortBalance * totalLp) / total;
	}
}
