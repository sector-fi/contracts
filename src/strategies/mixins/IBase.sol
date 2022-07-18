// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

struct IMXConfig {
	address underlying;
	address short;
	address uniPair;
	address poolToken;
	address farmToken;
	uint256 farmId;
	address farmRouter;
	address vault;
	string symbol;
	string name;
	uint256 maxTvl;
}

struct Config {
	address underlying;
	address short;
	address cTokenLend;
	address cTokenBorrow;
	address uniPair;
	address uniFarm;
	address farmToken;
	uint256 farmId;
	address farmRouter;
	address comptroller;
	address lendRewardRouter;
	address lendRewardToken;
	address vault;
	string symbol;
	string name;
	uint256 maxTvl;
}

// all interfaces need to inherit from base
abstract contract IBase {
	bool public isInitialized;

	modifier initializer() {
		require(isInitialized == false, "INITIALIZED");
		_;
	}

	function short() public view virtual returns (IERC20);

	function underlying() public view virtual returns (IERC20);
}
