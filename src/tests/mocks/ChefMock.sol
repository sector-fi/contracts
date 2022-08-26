// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { MockERC20 as ERC20 } from "./MockERC20.sol";

contract ChefMock {
	mapping(address => uint256) private balances;
	ERC20 token;

	constructor(address _token) {
		token = ERC20(_token);
	}

	function deposit(uint256 amount) public {
		token.transferFrom(msg.sender, address(this), amount);
		balances[msg.sender] += amount;
	}

	function withdraw(uint256 amount) public {
		token.transfer(msg.sender, amount);
		balances[msg.sender] -= amount;
	}

	function balanceOf(address account) public view returns (uint256) {
		return balances[account];
	}
}
