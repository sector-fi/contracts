// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../HedgedLP.sol";
import "../adapters/Compound.sol";
import "../adapters/MasterChefFarm.sol";
import "../adapters/CompMultiFarm.sol";

// import "hardhat/console.sol";

contract USDCglmrSTELLAwell is HedgedLP, Compound, CompMultiFarm, MasterChefFarm {
	// HedgedLP should allways be intialized last
	constructor(Config memory config) BaseStrategy(config.vault, config.symbol, config.name) {
		__MasterChefFarm_init_(
			config.uniPair,
			config.uniFarm,
			config.farmRouter,
			config.farmToken,
			config.farmId
		);

		__Compound_init_(config.comptroller, config.cTokenLend, config.cTokenBorrow);

		__CompoundFarm_init_(config.lendRewardRouter, config.lendRewardToken);

		__HedgedLP_init_(config.underlying, config.short, config.maxTvl);
	}

	// if borrow token is treated as ETH
	function _isBase(uint8) internal pure override(ICompound) returns (bool) {
		return true;
	}
}
