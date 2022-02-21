// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DSTestPlus } from "../utils/DSTestPlus.sol";
import { TestUtils } from "../utils/TestUtils.sol";

import { IUniswapV2Pair } from "../../interfaces/uniswap/IUniswapV2Pair.sol";
import { MockHedgedLP } from "../mocks/MockHedgedLP.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockPair } from "../mocks/MockPair.sol";

import "hardhat/console.sol";

contract StrategyTest is DSTestPlus {
	using TestUtils for MockPair;
	using TestUtils for MockHedgedLP;

	uint256 START_EXCHANGE_RATE = 2.5e18;
	MockHedgedLP strategy;
	MockERC20 underlying;
	MockERC20 short;
	MockPair pair;

	function setUp() public {
		uint256 initialLp = 1e9; // 100M
		underlying = new MockERC20("Mock Underlying Token", "UTKN", 18);
		short = new MockERC20("Mock Short Token", "STKN", 6);
		pair = new MockPair("Mock Pair Token", "PAIR", 18);
		pair.initialize(address(short), address(underlying)); // in alphabetical order
		underlying.mint(address(this), initialLp * START_EXCHANGE_RATE);
		short.mint(address(this), initialLp * 1e18);

		underlying.transfer(address(pair), initialLp * START_EXCHANGE_RATE);
		short.transfer(address(pair), initialLp * 1e18);
		pair.mint(address(0xbeef));
		strategy = new MockHedgedLP(
			address(underlying),
			address(short),
			address(this),
			address(pair),
			START_EXCHANGE_RATE
		);
	}

	/*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testDepositWithdraw() public {
		uint256 amount = 10e18;
		underlying.mint(address(this), amount);
		underlying.approve(address(strategy), amount);
		uint256 preDepositBal = underlying.balanceOf(address(this));
		strategy.mint(amount);
		// price should not be off by more than 1%
		assertApproxEq(strategy.BASE_UNIT(), strategy.getPricePerShare(), 10);
		assertEq(strategy.totalSupply(), amount);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - amount);

		strategy.redeemUnderlying(amount / 2);
		assertApproxEq(strategy.BASE_UNIT(), strategy.getPricePerShare(), 10);
		assertApproxEq(strategy.totalSupply(), amount / 2, 10);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - amount / 2);

		strategy.redeemUnderlying(amount / 2);
		assertApproxEq(strategy.BASE_UNIT(), strategy.getPricePerShare(), 10);
		assertEq(strategy.totalSupply(), 0);
		assertApproxEq(underlying.balanceOf(address(this)), preDepositBal, 10);
	}

	function testDepositFuzz(uint104 fuzz) public {
		underlying.mint(address(this), fuzz);
		underlying.approve(address(strategy), fuzz);
		uint256 preDepositBal = underlying.balanceOf(address(this));
		strategy.mint(fuzz);

		// price should not be off by more than 1%
		assertGe((strategy.BASE_UNIT() * 1000) / strategy.getPricePerShare(), 999);
		assertEq(strategy.totalSupply(), fuzz);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - fuzz);
	}

	function testDepositWithdrawPartial(uint128 fuzz) public {
		uint256 fixedAmt = 1e18;
		uint256 fuzzPartial = (uint256(fuzz) * fixedAmt) / type(uint128).max;

		underlying.mint(address(this), fixedAmt + fuzz);
		underlying.approve(address(strategy), fixedAmt + fuzz);
		uint256 preDepositBal = underlying.balanceOf(address(this));
		strategy.mint(fixedAmt);
		assertEq(strategy.totalSupply(), fixedAmt);
		assertApproxEq(strategy.getPricePerShare(), strategy.BASE_UNIT(), 10000);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - fixedAmt);
		strategy.redeemUnderlying(fuzzPartial);

		assertApproxEq(strategy.totalSupply(), fixedAmt - fuzzPartial, 10000);
		assertApproxEq(strategy.getPricePerShare(), strategy.BASE_UNIT(), 10000);
		assertApproxEq(
			underlying.balanceOf(address(this)),
			preDepositBal - fixedAmt + fuzzPartial,
			1e12
		);
		strategy.redeemUnderlying(fixedAmt - fuzzPartial);

		assertApproxEq(strategy.totalSupply(), 0, 10000);

		// price should not be off by more than 1%
		assertGe((strategy.BASE_UNIT() * 1000) / strategy.getPricePerShare(), 999);
		assertApproxEq(underlying.balanceOf(address(this)), preDepositBal, 1000);
	}

	function testDepositWithdraw99Percent(uint128 fuzz) public {
		// ASSUMES DEPOSIT MINIMUM OF AT LEAST 2
		if (fuzz <= 1) return;
		// deposit fixed amount, withdraw between 99% and 100% of balance
		uint256 fixedAmt = 12345678912345678912;
		uint256 min = (fixedAmt * 99) / 100;
		uint256 fuzz99Percent = TestUtils.toRange(fuzz, min, fixedAmt);

		underlying.mint(address(this), fixedAmt);
		underlying.approve(address(strategy), fixedAmt);

		uint256 preDepositBal = underlying.balanceOf(address(this));

		strategy.mint(fixedAmt);

		// deposit
		assertEq(strategy.totalSupply(), fixedAmt);
		assertApproxEq(strategy.getPricePerShare(), strategy.BASE_UNIT(), 10);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - fixedAmt);

		strategy.redeemUnderlying(fuzz99Percent);

		assertApproxEq(strategy.totalSupply(), fixedAmt - fuzz99Percent, 10);
		assertApproxEq(strategy.getPricePerShare(), strategy.BASE_UNIT(), 10);
		assertApproxEq(
			underlying.balanceOf(address(this)),
			preDepositBal - fixedAmt + fuzz99Percent,
			10
		);

		strategy.redeemUnderlying(fixedAmt - fuzz99Percent); // add a little extra to make sure we get full amount out

		uint256 totalSupply = strategy.totalSupply();
		assertEq(totalSupply, 0);
		assertApproxEq(strategy.getPricePerShare(), strategy.BASE_UNIT(), 10);
		assertApproxEq(underlying.balanceOf(address(this)), preDepositBal, 10);
	}

	// /*///////////////////////////////////////////////////////////////
	//                     DEPOSIT/WITHDRAWAL FAIL CHECKS
	// //////////////////////////////////////////////////////////////*/

	function testFailDepositWithNotEnoughApproval() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);

		strategy.mint(1.5e18);
	}

	function testFailDepositWithNoApproval() public {
		strategy.mint(1e18);
	}

	// function testFailWithdrawWithNoBalance() public {
	// 	strategy.redeemUnderlying(1e18);
	// }

	// function testFailWithdrawMoreThanBalance() public {
	// 	underlying.mint(address(this), 1e18);
	// 	underlying.approve(address(strategy), 1e18);

	// 	strategy.mint(1e18);
	// 	strategy.redeemUnderlying(1.5e18);
	// }

	/*///////////////////////////////////////////////////////////////
	                    REBALANCE TESTS
	//////////////////////////////////////////////////////////////*/
	function testRebalanceSimple() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);

		strategy.mint(1e18);
		// _rebalanceDown price up -> LP down
		assertEq(strategy.getPositionOffset(), 0);
		// 10% price increase should move position offset by more than 4%
		strategy.changePrice(1.1e18);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, 1.1e18);
		assertGt(strategy.getPositionOffset(), 400);

		strategy.rebalance();
		assertLe(strategy.getPositionOffset(), 10);

		// _rebalanceUp price down -> LP up
		strategy.changePrice(.909e18);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, .909e18);
		assertGt(strategy.getPositionOffset(), 400);
		strategy.rebalance();
		assertLe(strategy.getPositionOffset(), 10);
	}

	function testRebalanceFuzz(uint104 fuzz) public {
		uint256 priceAdjust = TestUtils.toRangeUint104(fuzz, uint256(.5e18), uint256(2e18));
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);
		uint256 rebThresh = strategy.rebalanceThreshold();

		strategy.mint(1e18);

		strategy.changePrice(priceAdjust);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, priceAdjust);

		// skip if we don't need to rebalance
		// add some padding so that we can go back easier to account on % change going back
		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance();

		assertApproxEq(strategy.getPositionOffset(), 0, 10);

		// put price back
		strategy.changePrice(1e36 / priceAdjust);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, 1e36 / priceAdjust);
		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance();
		assertApproxEq(strategy.getPositionOffset(), 0, 10);
	}

	function testFailRebalance() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);

		strategy.mint(1e18);
		strategy.rebalance();
	}

	function testRebalanceLendFuzz(uint104 fuzz) public {
		uint256 priceAdjust = TestUtils.toRangeUint104(fuzz, uint256(1e18), uint256(2e18));
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);
		strategy.mint(1e18);
		uint256 rebThresh = strategy.rebalanceThreshold();

		strategy.changePrice(priceAdjust);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, priceAdjust);

		uint256 minLoanHealth = strategy.minLoanHealth();
		if (strategy.loanHealth() <= minLoanHealth) {
			strategy.rebalanceLoan();
			assertGt(strategy.loanHealth(), minLoanHealth);
		}
		// skip if we don't need to rebalance
		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance();
		assertApproxEq(strategy.getPositionOffset(), 0, 11);

		// put price back
		strategy.changePrice(1e36 / priceAdjust);
		TestUtils.movePrice(IUniswapV2Pair(address(pair)), underlying, short, 1e36 / priceAdjust);

		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance();
		// strategy.logTvl();

		assertApproxEq(strategy.getPositionOffset(), 0, 11);
	}

	// test rebalance when loand is 0
	function testRebgalanceEdge() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(strategy), 1e18);
		strategy.mint(1e18);
		strategy.repayLoan();

		assertEq(strategy.getPositionOffset(), 10000);
		strategy.rebalance();
		assertLt(strategy.getPositionOffset(), 10);
	}
}
