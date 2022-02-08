// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "../../mixins/ILending.sol";
import "../../mixins/IBase.sol";
import "../../interfaces/uniswap/IUniswapV2Pair.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

import "hardhat/console.sol";

abstract contract MockLending is ILending {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	uint256 borrowAmount = 0;
	uint256 lendAmount = 0;
	uint256 exchangeRate;
	uint256 maxBorrow = 2 * uint256(type(uint128).max);

	function __MockLending_(uint256 startExchangeRate) internal initializer {
		exchangeRate = startExchangeRate;
	}

	function _addLendingApprovals() internal override {}

	function lendFarmRouter() public view override returns (IUniswapV2Router01) {}

	function changePrice(uint256 fraction) public {
		if (fraction == 1e18) return;
		exchangeRate = (fraction * exchangeRate) / 1e18;
	}

	function _maxBorrow() internal view override returns (uint256) {
		return maxBorrow;
	}

	function setLendingMaxBorrow(uint256 maxBorrow_) internal {
		maxBorrow = maxBorrow_;
	}

	function _oraclePriceOfShort(uint256 amount) internal view virtual override returns (uint256) {
		return (amount * exchangeRate) / 1e18;
	}

	function _oraclePriceOfUnderlying(uint256 amount)
		internal
		view
		virtual
		override
		returns (uint256)
	{
		return (amount * 1e18) / exchangeRate;
	}

	function _getCollateralFactor() internal view virtual override(ILending) returns (uint256) {
		return 0.8e18;
	}

	function safeCollateralRatio() public pure virtual override(ILending) returns (uint256) {
		return 9000;
	}

	function _getCollateralBalance() internal view virtual override returns (uint256) {
		return lendAmount;
	}

	function _lend(uint256 amount) internal virtual override {
		MockERC20(address(underlying())).burn(address(this), amount);
		lendAmount += amount;
	}

	function _redeem(uint256 amount) internal virtual override {
		require(lendAmount >= amount, "REDEEM EXCEEDS LEND BAL");
		enforceCollateralFactor(lendAmount - amount, borrowAmount);
		MockERC20(address(underlying())).mint(address(this), amount);
		lendAmount -= amount;
	}

	function _borrow(uint256 amount) internal virtual override {
		enforceCollateralFactor(lendAmount, (amount + borrowAmount));
		MockERC20(address(short())).mint(address(this), amount);
		borrowAmount += amount;
	}

	function enforceCollateralFactor(uint256 _lendAmt, uint256 _borrowAmnt) internal view {
		uint256 borrowUnderlying = ((_oraclePriceOfShort(_borrowAmnt) * 1e18) /
			_getCollateralFactor());
		require(_lendAmt >= borrowUnderlying, "OVER COLLATERAL");
	}

	function _repay(uint256 amount) internal virtual override {
		require(borrowAmount >= amount, "REPAY EXCEEDS BORROW BAL");
		MockERC20(address(short())).burn(address(this), amount);
		borrowAmount -= amount;
	}

	function _getBorrowBalance() internal view virtual override returns (uint256) {
		return borrowAmount;
	}

	function _updateAndGetBorrowBalance() internal view virtual override returns (uint256) {
		return borrowAmount;
	}

	function _updateAndGetCollateralBalance() internal virtual override returns (uint256) {
		return lendAmount;
	}

	function _harvestLending(HarvestSwapParms[] calldata swapParams)
		internal
		virtual
		override
		returns (uint256[] memory)
	{}
}
