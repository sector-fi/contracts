// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "../../interfaces/uniswap/IUniswapV2Pair.sol";
import "../mixins/IBase.sol";
import "../mixins/IIMXFarm.sol";
import "../mixins/IUniLp.sol";

import "../../libraries/UniUtils.sol";

import "hardhat/console.sol";

import { ICollateral, IPoolToken, IBorrowable } from "../../interfaces/imx/IImpermax.sol";

abstract contract IMXFarm is IBase, IIMXFarm, IUniLp {
	using SafeERC20 for IERC20;
	using UniUtils for IUniswapV2Pair;
	using FixedPointMathLib for uint256;

	IUniswapV2Pair public uniPair;
	ICollateral public collateralToken;
	IBorrowable public uBorrowable;
	IBorrowable public sBorrowable;
	IPoolToken private stakedToken;

	bool private _flip;

	function __IMX_init_(
		address uniPair_,
		address collateralToken_,
		address underlying_
	) internal {
		uniPair = IUniswapV2Pair(uniPair_);
		collateralToken = ICollateral(collateralToken_);
		uBorrowable = IBorrowable(collateralToken.borrowable0());
		sBorrowable = IBorrowable(collateralToken.borrowable1());
		if (underlying_ != uBorrowable.underlying()) {
			_flip = true;
			(uBorrowable, sBorrowable) = (sBorrowable, uBorrowable);
		}
		stakedToken = IPoolToken(collateralToken.underlying());
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return uniPair;
	}

	function _addLiquidity(uint256 amntUnderlying, uint256 amntShort)
		internal
		virtual
		override
		returns (uint256)
	{
		uint256 borrowU = (_optimalUBorrow() * amntUnderlying) / 1e18;
		uint256 borrowS = amntShort + _underlyingToShort(borrowU);

		bytes memory data = abi.encode(amntUnderlying);
		sBorrowable.borrowApprove(address(sBorrowable), amntShort);

		// mint collateral
		bytes memory borrowBData = abi.encode(
			CalleeData({
				callType: CallType.ADD_LIQUIDITY_AND_MINT,
				data: abi.encode(
					AddLiquidityAndMintCalldata({ uAmnt: amntUnderlying + borrowU, sAmnt: borrowS })
				)
			})
		);
		// borrow borrowableB
		bytes memory borrowAData = abi.encode(
			CalleeData({
				callType: CallType.BORROWB,
				data: abi.encode(BorrowBCalldata({ borrowAmount: borrowU, data: borrowBData }))
			})
		);

		// flashloan borrow then add lp
		sBorrowable.borrow(address(this), address(this), borrowS, borrowAData);
	}

	function impermaxBorrow(
		address,
		address,
		uint256,
		bytes calldata data
	) external {
		// ensure that msg.sender is correct
		require(
			msg.sender == address(sBorrowable) || msg.sender == address(uBorrowable),
			"IMXFarm: NOT_BORROWABLE"
		);
		CalleeData memory calleeData = abi.decode(data, (CalleeData));

		if (calleeData.callType == CallType.ADD_LIQUIDITY_AND_MINT) {
			AddLiquidityAndMintCalldata memory d = abi.decode(
				calleeData.data,
				(AddLiquidityAndMintCalldata)
			);
			_addLp(d.uAmnt, d.sAmnt);
		} else if (calleeData.callType == CallType.BORROWB) {
			BorrowBCalldata memory d = abi.decode(calleeData.data, (BorrowBCalldata));
			uBorrowable.borrow(address(this), address(this), d.borrowAmount, d.data);
		}
	}

	function _addLp(uint256 uAmnt, uint256 sAmnt) internal {
		console.log("add lp", uAmnt, sAmnt);
		underlying().safeTransfer(address(uniPair), uAmnt);
		short().safeTransfer(address(uniPair), sAmnt);

		uint256 liquidity = uniPair.mint(address(this));

		// first we create staked token, then collateral token
		IERC20(address(uniPair)).safeTransfer(address(stakedToken), liquidity);
		stakedToken.mint(address(collateralToken));
		collateralToken.mint(address(this));
	}

	function _removeAllLp() internal override {
		console.log("remove all");
		(uint256 underlyingLp, ) = _getLPBalances();
		(uint256 uBorrow, ) = _getBorrowBalances();
		_removeIMXLiquidity(uBorrow >= underlyingLp ? 0 : underlyingLp - uBorrow, underlyingLp, 0);
	}

	function _removeIMXLiquidity(
		uint256 rmUndelrying,
		uint256 underlyingLp,
		uint256 targetUnderlyingLp
	) internal override returns (uint256 remainingUnderlyingLP) {
		uint256 liquidity = _getLiquidity();
		uint256 targetLiquidity = (liquidity * targetUnderlyingLp) / underlyingLp;
		uint256 removeLp = liquidity - targetLiquidity;

		console.log("r u t", rmUndelrying, underlyingLp, targetUnderlyingLp);

		uint256 redeemAmount = (removeLp * 1e18) / stakedToken.exchangeRate() + 1;

		// tar
		uint256 uRepay = underlyingLp - targetUnderlyingLp - rmUndelrying;
		uint256 sRepay = _underlyingToShort(underlyingLp - targetUnderlyingLp);

		bytes memory data = abi.encode(
			RemoveLiqAndRepayCalldata({
				liquidity: removeLp,
				redeemAmount: redeemAmount,
				repayUnderlying: uRepay
				// amountAMin: amountAMin,
				// amountBMin: amountBMin
			})
		);

		collateralToken.flashRedeem(address(this), redeemAmount, data);
		remainingUnderlyingLP = underlyingLp - targetUnderlyingLp;
	}

	function impermaxRedeem(
		address,
		uint256 redeemAmount,
		bytes calldata data
	) external {
		require(msg.sender == address(collateralToken), "IMXFarm: NOT_COLLATERAL");

		RemoveLiqAndRepayCalldata memory d = abi.decode(data, (RemoveLiqAndRepayCalldata));

		// redeem withdrawn staked coins
		IERC20(address(stakedToken)).transfer(address(stakedToken), redeemAmount);
		stakedToken.redeem(address(this));

		// TODO this is not flash-swap safe!!!
		// remove collateral
		(uint256 underlyingAmnt, uint256 shortAmnt) = IUniLp._removeLiquidity(d.liquidity);

		console.log("u s", underlyingAmnt, shortAmnt);

		// TODO check if we have enought short and buy more if needed

		(uint256 uBorrow, uint256 sBorrow) = _getBorrowBalances();
		uint256 uRepay = uBorrow > shortAmnt ? shortAmnt : uBorrow;

		// if(uBorrow > )

		// repay loan
		short().safeTransfer(address(sBorrowable), shortAmnt);
		sBorrowable.borrow(address(this), address(0), 0, new bytes(0));

		// TODO don't repay more than loan, sell extra underlying
		// TODO check if we have enought underlyinglying and buy more if needed

		underlying().safeTransfer(address(uBorrowable), d.repayUnderlying);
		uBorrowable.borrow(address(this), address(0), 0, new bytes(0));

		uint256 cAmount = (redeemAmount * 1e18) / collateralToken.exchangeRate() + 1;

		// return collateral token
		IERC20(address(collateralToken)).transfer(address(collateralToken), cAmount);
	}

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{}

	function _getLiquidity() internal view override returns (uint256) {
		return
			(stakedToken.exchangeRate() *
				(collateralToken.exchangeRate() * collateralToken.balanceOf(address(this)))) /
			1e18 /
			1e18;
	}

	function _getBorrowBalances() internal view override returns (uint256, uint256) {
		return (uBorrowable.borrowBalance(address(this)), sBorrowable.borrowBalance(address(this)));
	}

	function _updateAndGetBorrowBalances() internal override returns (uint256, uint256) {
		sBorrowable.accrueInterest();
		uBorrowable.accrueInterest();
		return _getBorrowBalances();
	}

	// borrow amount of underlying for every 1e18 of deposit
	function _optimalUBorrow() internal override returns (uint256 uBorrow) {
		(uint256 price0, uint256 price1) = collateralToken.getPrices();
		if (_flip) (price0, price1) = (price1, price0);

		uint256 l = collateralToken.liquidationIncentive();
		// this is the adjusted safety margin - how far we stay from liquidation
		uint256 s = (collateralToken.safetyMarginSqrt() * _getSafetyMarginSqrt()) / 1e18;
		uBorrow = (1e18 * (2e18 - (l * s) / 1e18)) / ((l * 1e18) / s + (l * s) / 1e18 - 2e18);
	}

	function getIMXLiquidity()
		external
		returns (
			// view
			uint256 collateral,
			uint256 price0,
			uint256 price1,
			uint256 amount0,
			uint256 amount1
		)
	{
		collateral =
			(collateralToken.exchangeRate() * collateralToken.balanceOf(address(this))) /
			1e18;

		(uint256 liquidity, ) = collateralToken.accountLiquidity(address(this));

		amount0 = IBorrowable(collateralToken.borrowable0()).borrowBalance(address(this));
		amount1 = IBorrowable(collateralToken.borrowable1()).borrowBalance(address(this));

		(price0, price1) = ICollateral(address(collateralToken)).getPrices();

		uint256 value0 = (amount0 * price0) / 1e18;
		uint256 value1 = (amount1 * price1) / 1e18;

		console.log("liq c", liquidity, collateral);
		console.log("col 0 1", collateral, (amount0 * price0) / 1e18, (amount1 * price1) / 1e18);

		console.log("leverage", (collateral * 1e18) / (collateral - value0 - value1 + 1));

		console.log(
			"safty/liq",
			collateralToken.safetyMarginSqrt(),
			collateralToken.liquidationIncentive()
		);
	}

	// function _removeLiquidity(uint256) internal override returns (uint256, uint256) {}
}
