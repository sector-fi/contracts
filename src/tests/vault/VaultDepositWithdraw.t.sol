// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";
import { MockERC20Strategy } from "../mocks/MockERC20Strategy.sol";
import "hardhat/console.sol";

contract VaultDepositWithdrawTest is VaultTest {
	/*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testAtomicDepositWithdraw() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		uint256 preDepositBal = underlying.balanceOf(address(this));

		vault.deposit(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - 1e18);

		vault.withdraw(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(underlying.balanceOf(address(this)), preDepositBal);
	}

	function testAtomicDepositRedeem() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		uint256 preDepositBal = underlying.balanceOf(address(this));

		vault.deposit(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - 1e18);

		vault.redeem(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(underlying.balanceOf(address(this)), preDepositBal);
	}

	function testWithdrawQueueEdgecase() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		Strategy[] memory strats = new Strategy[](2);
		strats[0] = strategy1;
		strats[1] = strategy2;

		// add underlying - this will return less when withdrawing
		underlying.mint(address(strategy1), 0.01e18);

		// remove underlying - this will return less when withdrawing
		underlying.burn(address(strategy1), 0.01e18);

		vault.setWithdrawalQueue(strats);

		vault.withdraw(0.8e18);

		(, uint256 balanceMore) = vault.getStrategyData(strategy2);
		assertEq(balanceMore, 0);

		vault.withdraw(0.2e18);

		(, uint256 balanceLess) = vault.getStrategyData(strategy1);
		assertEq(balanceLess, 0);
	}

	function testWithdrawAfterLoss() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		Strategy[] memory strats = new Strategy[](1);
		strats[0] = strategy1;
		vault.setWithdrawalQueue(strats);

		(, uint256 strategyBalance) = vault.getStrategyData(strategy1);
		strategy1.simulateLoss(strategyBalance - .5e18);

		vault.withdraw(.4e18);

		uint256 balance = vault.balanceOf(address(this));
		assertEq(balance, .2e18);
	}

	/*///////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testFailDepositWithNotEnoughApproval() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(1e18);
	}

	function testFailWithdrawWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.withdraw(1e18);
	}

	function testFailRedeemWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.redeem(1e18);
	}

	function testFailRedeemWithNoBalance() public {
		vault.redeem(1e18);
	}

	function testFailWithdrawWithNoBalance() public {
		vault.withdraw(1e18);
	}

	function testFailDepositWithNoApproval() public {
		vault.deposit(1e18);
	}

	/*///////////////////////////////////////////////////////////////
                     STRATEGY DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testAtomicEnterExitSinglePool() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
	}

	function testAtomicEnterExitMultiPool() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.trustStrategy(strategy2);

		vault.depositIntoStrategy(strategy2, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy2, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
	}

	function testSetTargetFloatPercent() public {
		vault.setTargetFloatPercent(0.5e18);

		assertEq(vault.targetFloatPercent(), 0.5e18);

		vault.setTargetFloatPercent(1e15);

		assertEq(vault.targetFloatPercent(), 1e15);
	}

	/*///////////////////////////////////////////////////////////////
              STRATEGY DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testFailDepositIntoStrategyWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);
		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithoutTrust() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		vault.deposit(1e18);
		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.distrustStrategy(strategy1);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailDepositIntoStrategyWithNoBalance() public {
		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithNoBalance() public {
		vault.trustStrategy(strategy1);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailSetTargetFloatPercentOver100() public {
		vault.setTargetFloatPercent(1.1e18);

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setTargetFloatPercent(0.5e18);
	}

	// EDGE Cases

	function testFailWithdrawWithEmptyQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.withdraw(.9e18);
	}

	function testFailWithdrawWithIncompleteQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.pushToWithdrawalQueue(strategy1);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		vault.withdraw(.6e18);
	}

	function testWithdrawingWithUntrustedStrategyInQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		vault.pushToWithdrawalQueue(strategy2);
		vault.pushToWithdrawalQueue(strategy2);
		vault.pushToWithdrawalQueue(new MockERC20Strategy(underlying));
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.getWithdrawalQueue().length, 5);

		vault.redeem(1e18);

		assertEq(vault.getWithdrawalQueue().length, 1);

		assertEq(address(vault.withdrawalQueue(0)), address(strategy2));
	}

	function testWithdrawingWithDuplicateStrategiesInQueue() public {
		depositIntoStrat(strategy1, 0.5e18);
		vault.pushToWithdrawalQueue(strategy1);

		depositIntoStrat(strategy2, 0.5e18);

		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.getWithdrawalQueue().length, 5);

		vault.redeem(1e18);

		assertEq(vault.getWithdrawalQueue().length, 2);

		assertEq(address(vault.withdrawalQueue(0)), address(strategy1));
		assertEq(address(vault.withdrawalQueue(1)), address(strategy1));
	}

	function testDepositAfterHarvestProfit() public {
		vault.setFeePercent(0);
		depositIntoStrat(strategy1, 1e18);

		underlying.mint(address(strategy1), 1e18);

		// harvest should not inflate deposits
		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		uint256 balance = vault.balanceOfUnderlying(address(this));
		// profits are locked
		assertEq(balance, 1e18, "profits are locked");

		vault.harvest(strategiesToHarvest);

		address user = address(2);
		depositIntoStrat(user, strategy1, 1e18);

		vm.warp(block.timestamp + vault.harvestDelay());

		uint256 balanceWProfits = vault.balanceOfUnderlying(address(this));
		assertEq(balanceWProfits, 2e18, "no more lock");

		uint256 userBalance = vault.balanceOfUnderlying(user);

		assertEq(userBalance, 1e18, "should not front-run deposits after profits");
	}

	function testDepositAfterHarvestLoss() public {
		vault.setFeePercent(0);
		depositIntoStrat(strategy1, 1e18);

		underlying.burn(address(strategy1), 0.5e18);
		assertEq(underlying.balanceOf(address(strategy1)), 0.5e18);

		// harvest should not inflate deposits
		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		uint256 balance = vault.balanceOfUnderlying(address(this));
		assertEq(balance, 0.5e18, "balance should reflect loss");

		vault.harvest(strategiesToHarvest);

		address user = address(2);
		depositIntoStrat(user, strategy1, 1e18);

		vm.warp(block.timestamp + vault.harvestDelay());

		uint256 balanceAfterHarvest = vault.balanceOfUnderlying(address(this));
		assertEq(balanceAfterHarvest, .75e18, "unlocked loss");

		uint256 userBalance = vault.balanceOfUnderlying(user);

		assertEq(userBalance, .75e18, "loss unlocked");
	}
}
