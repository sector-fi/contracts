// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../IMX.sol";
import "../adapters/IMXFarm.sol";

// import "hardhat/console.sol";

contract USDCimxWEVE is IMX, IMXFarm {
	constructor(IMXConfig memory config) BaseStrategy(config.vault, config.symbol, config.name) {
		__IMX_init_(config.uniPair, config.poolToken, config.underlying);

		// HedgedLP should allways be intialized last
		__HedgedLP_init_(config.underlying, config.short, config.maxTvl);
	}

	function _addLiquidity(uint256 amntUnderlying, uint256 amntShort)
		internal
		override(IUniLp, IMXFarm)
		returns (uint256)
	{
		return IMXFarm._addLiquidity(amntUnderlying, amntShort);
	}

	// if borrow token is treated as ETH
	function _isBase(uint8 id) internal pure override returns (bool) {
		return id == 1 ? true : false;
	}
}
