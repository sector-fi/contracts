// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./IFarmable.sol";

abstract contract IFarmableLp is IFarmable {
	function _depositIntoFarm(uint256 amount) internal virtual;

	function _withdrawFromFarm(uint256 amount) internal virtual;

	function _harvestFarm(HarvestSwapParms[] calldata swapParams)
		internal
		virtual
		returns (uint256[] memory);

	function _getFarmLp() internal view virtual returns (uint256);

	function _addFarmApprovals() internal virtual;

	function farmRouter() public view virtual returns (IUniswapV2Router01);
}
