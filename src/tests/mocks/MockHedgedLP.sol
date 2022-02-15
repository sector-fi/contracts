// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../mixins/ILending.sol";
import "../../strategies/HedgedLP.sol";

import "../../libraries/UniUtils.sol";

import "./MockLending.sol";
import "./MockFarm.sol";
import "./MockPair.sol";

contract MockHedgedLP is HedgedLP, MockLending, MockFarm {
	constructor(
		address _underlying,
		address _short,
		address _vault,
		address pair_,
		uint256 startExchangeRate
	) BaseStrategy(_vault, "MOCK", "MockHedgedLP") {
		__MockFarm_(address(0x0), pair_);
		__MockLending_(startExchangeRate);
		__HedgedLP_init_(_underlying, _short, type(uint256).max);
	}

	// our borrow token is treated as ETH by benqi
	function _isBase(uint8 id) internal pure returns (bool) {
		return id == 1 ? true : false;
	}
}
