// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMiniChefV2 } from "../../interfaces/uniswap/IStakingRewards.sol";
import "../../interfaces/uniswap/IUniswapV2Pair.sol";

import "../mixins/IFarmableLp.sol";
import "../mixins/IUniLp.sol";

// import "hardhat/console.sol";

abstract contract MiniChefFarm is IFarmableLp, IUniLp {
	using UniUtils for IUniswapV2Pair;
	using SafeERC20 for IERC20;

	IMiniChefV2 private _farm;
	IUniswapV2Router01 private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;

	function __MiniChefFarm_init_(
		address pair_,
		address farm_,
		address router_,
		address farmToken_,
		uint256 farmPid_
	) internal initializer {
		_farm = IMiniChefV2(farm_);
		_router = IUniswapV2Router01(router_);
		_farmToken = IERC20(farmToken_);
		_pair = IUniswapV2Pair(pair_);
		_farmId = farmPid_;
	}

	function _addFarmApprovals() internal override {
		// farm approvals
		IERC20(address(_pair)).safeApprove(address(_farm), type(uint256).max);
		_farmToken.safeApprove(address(_router), type(uint256).max);
	}

	function farmRouter() public view override returns (IUniswapV2Router01) {
		return _router;
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return _pair;
	}

	function _withdrawFromFarm(uint256 amount) internal override {
		_farm.withdraw(_farmId, amount, address(this));
	}

	function _depositIntoFarm(uint256 amount) internal override {
		_farm.deposit(_farmId, amount, address(this));
	}

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		_farm.harvest(_farmId, address(this));
		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));
		if (harvested[0] == 0) return harvested;

		_swap(_router, swapParams[0], address(_farmToken), harvested[0]);
		emit HarvestedToken(address(_farmToken), harvested[0]);
	}

	function _getFarmLp() internal view override returns (uint256) {
		(uint256 lp, ) = _farm.userInfo(_farmId, address(this));
		return lp;
	}

	function _getLiquidity() internal view override returns (uint256) {
		uint256 farmLp = _getFarmLp();
		uint256 poolLp = _pair.balanceOf(address(this));
		return farmLp + poolLp;
	}
}
