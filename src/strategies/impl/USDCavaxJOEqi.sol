// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../HedgedLP.sol";
import "../adapters/Compound.sol";
import "../adapters/MasterChefFarm.sol";
import "../adapters/BenqiFarm.sol";

// import "hardhat/console.sol";

contract USDCavaxJOEqi is HedgedLP, Compound, BenqiFarm, MasterChefFarm {
	constructor(Config memory config) BaseStrategy(config.vault, config.symbol, config.name) {
		__MasterChefFarm_init_(
			config.uniPair,
			config.uniFarm,
			config.lendRewardRouter,
			config.farmToken,
			config.farmId
		);

		__Compound_init_(
			config.comptroller,
			config.cTokenLend,
			config.cTokenBorrow,
			config.safeCollateralRatio
		);
		__BenqiFarm_init_(config.lendRewardRouter, config.lendRewardToken, config.short);

		// HedgedLP should allways be intialized last
		__HedgedLP_init_(config.underlying, config.short, config.maxTvl);
	}

	// our borrow token is treated as ETH by benqi
	function _isBase(uint8 id) internal pure override(ICompound) returns (bool) {
		return id == 1 ? true : false;
	}
}
