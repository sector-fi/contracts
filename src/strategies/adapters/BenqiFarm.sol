// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/forks/IBenqiComptroller.sol";
import "../../mixins/ICompound.sol";
import "../../mixins/IFarmable.sol";
import "../../mixins/IUniLp.sol";
import "../../interfaces/uniswap/IUniswapV2Pair.sol";
import "../../interfaces/uniswap/IWETH.sol";
import "../../libraries/UniUtils.sol";

// import "hardhat/console.sol";

abstract contract BenqiFarm is ICompound, IFarmable, IUniLp {
	using UniUtils for IUniswapV2Pair;
	using SafeERC20 for IERC20;

	IUniswapV2Router01 private _router; // use router here
	IERC20 _farmToken;

	function __BenqiFarm_init_(
		address router_,
		address farmToken1,
		address farmToken2
	) internal {
		_farmToken = IERC20(farmToken1);
		_router = IUniswapV2Router01(router_);
		_farmToken.safeApprove(address(_router), type(uint256).max);
		IERC20(farmToken2).safeApprove(address(_router), type(uint256).max);
	}

	// in case we need to query router used for swapping reward tokens
	function lendFarmRouter() public view override returns (IUniswapV2Router01) {
		return _router;
	}

	// BenQi has two two token rewards
	// pid 0 is Qi token and pid 1 is AVAX (not wrapped)
	function _harvestLending(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		// qi rewards
		IBenqiComptroller(address(comptroller())).claimReward(0, payable(address(this)));
		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));

		if (harvested[0] > 0) {
			_swap(_router, swapParams[0], address(_farmToken), harvested[0]);
			emit HarvestedToken(address(_farmToken), harvested[0]);
		}

		// specific to benqi
		// avax rewards - we handle re-deposit here because strategy is not aware of these rewards
		IBenqiComptroller(address(comptroller())).claimReward(1, payable(address(this)));
		uint256 avaxBalance = address(this).balance;

		// use avaxBalance to repay a portion of the loan
		if (avaxBalance > 0) _repayBase(avaxBalance);

		emit HarvestedToken(address(short()), avaxBalance);
	}
}
