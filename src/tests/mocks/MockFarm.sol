// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../mixins/IBase.sol";
import "../../mixins/IUniLp.sol";
import "../../mixins/IFarmableLp.sol";

import "hardhat/console.sol";

abstract contract MockFarm is IBase, IFarmableLp, IUniLp {
	using UniUtils for IUniswapV2Pair;
	address private _harvestTo;
	address private _pair;

	function __MockFarm_(address harvestTo_, address pair_) internal initializer {
		_harvestTo = harvestTo_;
		_pair = pair_;
	}

	function _addFarmApprovals() internal override {}

	function farmRouter() public view override returns (IUniswapV2Router01) {}

	function _depositIntoFarm(uint256) internal override {}

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory)
	{}

	function _withdrawFromFarm(uint256 amount) internal override {}

	function pair() public view override(IUniLp) returns (IUniswapV2Pair) {
		return IUniswapV2Pair(_pair);
	}

	function _getFarmLp() internal view override returns (uint256) {}

	function _getLiquidity() internal view override returns (uint256) {
		uint256 farmLp = 0;
		uint256 poolLp = pair().balanceOf(address(this));
		return farmLp + poolLp;
	}
}
