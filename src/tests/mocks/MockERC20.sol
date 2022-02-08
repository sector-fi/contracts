// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20Dec as ERC20 } from "../../tokens/ERC20Dec.sol";

contract MockERC20 is ERC20 {
	constructor(
		string memory _name,
		string memory _symbol,
		uint8 decimals_
	) ERC20(_name, _symbol, decimals_) {
		_decimals = _decimals;
	}

	function mint(address to, uint256 value) public virtual {
		_mint(to, value);
	}

	function burn(address from, uint256 value) public virtual {
		_burn(from, value);
	}
}
