// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ERC20 that supports configurable decimals
contract ERC20Dec is IERC20, ERC20 {
	uint8 _decimals;

	constructor(
		string memory _name,
		string memory _symbol,
		uint8 decimals_
	) ERC20(_name, _symbol) {
		_decimals = decimals_;
	}

	function decimals() public view override returns (uint8) {
		return _decimals;
	}
}
