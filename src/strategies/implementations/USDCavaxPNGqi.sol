// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../HedgedLP.sol";
import "../adapters/Compound.sol";
import "../adapters/MiniChefFarm.sol";
import "../adapters/CompMultiFarm.sol";

// import "hardhat/console.sol";

contract USDCavaxPNGqi is HedgedLP, Compound, CompMultiFarm, MiniChefFarm {
	constructor(Config memory config) BaseStrategy(config.vault, config.symbol, config.name) {
		__MiniChefFarm_init_(
			config.uniPair,
			config.uniFarm,
			config.farmRouter,
			config.farmToken,
			config.farmId
		);

		__Compound_init_(config.comptroller, config.cTokenLend, config.cTokenBorrow);

		__CompoundFarm_init_(config.lendRewardRouter, config.lendRewardToken);

		// HedgedLP should allways be intialized last
		__HedgedLP_init_(config.underlying, config.short, config.maxTvl);
	}

	// if borrow token is treated as ETH
	function _isBase(uint8 id) internal pure override(ICompound) returns (bool) {
		return id == 1 ? true : false;
	}
}
