// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/forks/IClaimReward.sol";
import "./CompoundFarm.sol";
import "../../interfaces/uniswap/IWETH.sol";

import "hardhat/console.sol";

abstract contract MoonwellFarm is CompoundFarm {
	// BenQi has two two token rewards
	// pid 0 is Qi token and pid 1 is AVAX (not wrapped)
	function _harvestLending(HarvestSwapParms[] calldata)
		internal
		override
		returns (uint256[] memory harvested)
	{
		// Moonwell rewards MOVR on id 1
		IClaimReward(address(comptroller())).claimReward(1, payable(address(this)));
		harvested = new uint256[](1);
		harvested[0] = address(this).balance;

		if (harvested[0] == 0) return harvested;

		// use useShortBalance to repay a portion of the loan
		IWETH(address(short())).deposit{ value: harvested[0] }();
		emit HarvestedToken(address(short()), harvested[0]);
	}
}
