// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../strategies/mixins/ILending.sol";
import { HedgedLP } from "../../strategies/HedgedLP.sol";
import { BaseStrategy } from "../../strategies/HedgedLP.sol";
import { UniUtils } from "../../libraries/UniUtils.sol";
import { MockLending } from "./MockLending.sol";
import { MockFarm } from "./MockFarm.sol";
import { MockPair } from "./MockPair.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

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
