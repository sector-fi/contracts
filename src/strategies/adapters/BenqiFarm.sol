// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/forks/IClaimReward.sol";
import "./CompoundFarm.sol";

// import "hardhat/console.sol";

abstract contract BenqiFarm is CompoundFarm {
	// BenQi has two two token rewards
	// pid 0 is Qi token and pid 1 is AVAX (not wrapped)
	function _harvestLending(HarvestSwapParms[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		// qi rewards
		IClaimReward(address(comptroller())).claimReward(0, payable(address(this)));
		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));

		if (harvested[0] > 0) {
			_swap(lendFarmRouter(), swapParams[0], address(_farmToken), harvested[0]);
			emit HarvestedToken(address(_farmToken), harvested[0]);
		}

		// specific to benqi
		// avax rewards - we handle re-deposit here because strategy is not aware of these rewards
		IClaimReward(address(comptroller())).claimReward(1, payable(address(this)));
		uint256 avaxBalance = address(this).balance;

		// use avaxBalance to repay a portion of the loan
		if (avaxBalance > 0) _repayBase(avaxBalance);

		emit HarvestedToken(address(short()), avaxBalance);
	}
}
