// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./IFarmable.sol";
import "./IUniLp.sol";

abstract contract IIMXFarm is IFarmable {
	enum CallType {
		ADD_LIQUIDITY_AND_MINT,
		BORROWB,
		REMOVE_LIQ_AND_REPAY
	}

	struct CalleeData {
		CallType callType;
		bytes data;
	}
	struct AddLiquidityAndMintCalldata {
		uint256 uAmnt;
		uint256 sAmnt;
	}
	struct BorrowBCalldata {
		uint256 borrowAmount;
		bytes data;
	}
	struct RemoveLiqAndRepayCalldata {
		uint256 liquidity;
		uint256 redeemAmount;
		uint256 repayUnderlying;
		// uint256 amountAMin;
		// uint256 amountBMin;
	}

	// function _depositIntoFarm(uint256 amount) internal virtual;

	// function _withdrawFromFarm(uint256 amount) internal virtual;

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		virtual
		returns (uint256[] memory);

	// function _getFarmLp() internal view virtual returns (uint256);

	// function _addFarmApprovals() internal virtual;

	// function farmRouter() public view virtual returns (IUniswapV2Router01);

	function _isBase(uint8 index) internal virtual returns (bool);

	function _getBorrowBalances()
		internal
		view
		virtual
		returns (uint256 underlyingAmnt, uint256 shortAmnt);

	function _updateAndGetBorrowBalances()
		internal
		virtual
		returns (uint256 underlyingAmnt, uint256 shortAmnt);

	function _getSafetyMarginSqrt() internal view virtual returns (uint256);

	function _underlyingToShort(uint256 amount) internal view virtual returns (uint256);

	function _shortToUnderlying(uint256 amount) internal view virtual returns (uint256);

	function _optimalUBorrow() internal virtual returns (uint256 uBorrow);

	function _removeIMXLiquidity(
		uint256 rmUndelrying,
		uint256 underlyingLp,
		uint256 targetUnderlyingLp
	) internal virtual returns (uint256);

	function _removeAllLp() internal virtual;
}
