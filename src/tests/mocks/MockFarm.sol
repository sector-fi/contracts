// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";
import { IBase } from "../../strategies/mixins/IBase.sol";
import { IUniLp, IUniswapV2Pair } from "../../strategies/mixins/IUniLp.sol";
import { IFarmableLp, IUniswapV2Router01, HarvestSwapParms } from "../../strategies/mixins/IFarmableLp.sol";
import { MockERC20, ERC20 } from "../mocks/MockERC20.sol";
import { UniUtils } from "../../libraries/UniUtils.sol";
import { ChefMock } from "./ChefMock.sol";

import "hardhat/console.sol";

abstract contract MockFarm is IBase, IFarmableLp, IUniLp, Test {
	using UniUtils for IUniswapV2Pair;
	address private _harvestTo;
	address private _pair;
	ChefMock private _farm;

	function __MockFarm_(address harvestTo_, address pair_) internal initializer {
		_harvestTo = harvestTo_;
		_pair = pair_;
		_farm = new ChefMock(address(pair()));
		pair().approve(address(_farm), type(uint256).max);
	}

	function _addFarmApprovals() internal override {}

	function farmRouter() public view override returns (IUniswapV2Router01) {}

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		// return some random harvested amount
		MockERC20(swapParams[0].path[1]).mint(address(this), 0.1e18);
		MockERC20(swapParams[1].path[1]).mint(address(this), 0.4e17);
		harvested = new uint256[](1);
		harvested[0] = 4.56e18;
	}

	function _depositIntoFarm(uint256 amount) internal override {
		_farm.deposit(amount);
	}

	function _withdrawFromFarm(uint256 amount) internal override {
		_farm.withdraw(amount);
	}

	function _getFarmLp() internal view override returns (uint256) {
		return _farm.balanceOf(address(this));
	}

	function pair() public view override(IUniLp) returns (IUniswapV2Pair) {
		return IUniswapV2Pair(_pair);
	}

	function _getLiquidity() internal view override returns (uint256) {
		uint256 farmLp = _getFarmLp();
		uint256 poolLp = pair().balanceOf(address(this));
		return farmLp + poolLp;
	}
}
