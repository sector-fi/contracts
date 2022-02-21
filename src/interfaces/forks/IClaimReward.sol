// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract IClaimReward {
	function claimReward(uint8 rewardType, address payable holder) external virtual;
}
