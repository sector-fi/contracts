// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "../../contracts/libraries/UQ112x112.sol";
import "../interfaces/uniswap/IUniswapV2Pair.sol";
import "../interfaces/uniswap/ISimpleUniswapOracle.sol";
import "hardhat/console.sol";

contract MockUniswapOracle is ISimpleUniswapOracle {
	// using UQ112x112 for uint224;

	uint32 public constant MIN_T = 3600;
	struct Pair {
		uint256 priceCumulativeA;
		uint256 priceCumulativeB;
		uint32 updateA;
		uint32 updateB;
		bool lastIsA;
		bool initialized;
	}
	mapping(address => Pair) public getPair;

	mapping(address => uint224) public mockPrice;

	function initialize(address uniswapV2Pair) external {
		require(!getPair[uniswapV2Pair].initialized, "AssertError: pair is already initialized");
		getPair[uniswapV2Pair].initialized = true;
		mockPrice[uniswapV2Pair] = 2**112;
	}

	function getResult(address uniswapV2Pair) external view returns (uint224 price, uint32 T) {
		price = mockPrice[uniswapV2Pair];
		T = 3600;
	}

	function setPrice(address uniswapV2Pair, uint224 price) external {
		mockPrice[uniswapV2Pair] = price;
	}

	/*** Utilities ***/

	function getBlockTimestamp() public view returns (uint32) {
		return uint32(block.timestamp % 2**32);
	}
}
