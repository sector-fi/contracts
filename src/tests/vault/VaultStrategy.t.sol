// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockERC20Strategy } from "../mocks/MockERC20Strategy.sol";
import { MockETHStrategy } from "../mocks/MockETHStrategy.sol";

contract VaultStrategyTest is VaultTest {
	/*///////////////////////////////////////////////////////////////
                        ADD STRATEGY TESTS / FAIL
    //////////////////////////////////////////////////////////////*/

	function testAddingStrategy() public {
		vault.addStrategy(strategy1);
		vault.addStrategy(strategy2);

		assertEq(vault.getWithdrawalQueue().length, 2);

		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.depositIntoStrategy(strategy1, 0.5e18);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);
		vault.withdrawFromStrategy(strategy2, 0.5e18);
		vault.popFromWithdrawalQueue();
		vault.popFromWithdrawalQueue();

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.addStrategy(strategy1);
	}

	function testAuthTrustStrategy() public {
		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.trustStrategy(strategy1);
	}

	function testAuthDistrustStrategy() public {
		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.distrustStrategy(strategy1);
	}

	/*///////////////////////////////////////////////////////////////
                        SET MAX TVL & STRAT TVL FAIL
    //////////////////////////////////////////////////////////////*/

	function testFailSetMaxTvl(uint128 fuzz) public {
		assertEq(vault.getMaxTvl(), type(uint256).max);

		vault.setMaxTvl(fuzz);

		assertEq(vault.getMaxTvl(), fuzz);

		underlying.mint(address(this), fuzz);
		underlying.approve(address(vault), fuzz);

		vault.deposit(fuzz + 1);
	}

	function testFailUpdateStratTvl(uint128 fuzz) public {
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy2);

		strategy1.setMaxTvl(fuzz);
		strategy2.setMaxTvl(25e18);
		vault.updateStratTvl();

		underlying.mint(address(this), fuzz + 25e18);
		underlying.approve(address(vault), fuzz + 25e18);

		// fail deposit more than MaxTvl
		vault.deposit(fuzz + 25e18 + 1);
		vault.popFromWithdrawalQueue();
		vault.popFromWithdrawalQueue();
	}

	/*///////////////////////////////////////////////////////////////
                        MIGRATE STRATEGY TESTS / FAIL
    //////////////////////////////////////////////////////////////*/
	function testMigrateStrategy() public {
		vault.addStrategy(strategy1);
		assertEq(vault.getWithdrawalQueue().length, 1);

		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.migrateStrategy(strategy1, strategy2, 0);
		assertEq(address(vault.withdrawalQueue(0)), address(strategy2));
		(bool trusted1, uint256 balance1) = vault.getStrategyData(strategy1);
		(bool trusted2, uint256 balance2) = vault.getStrategyData(strategy2);

		assertFalse(trusted1);
		assertTrue(trusted2);

		assertEq(balance1, 0);
		assertEq(balance2, 1e18);
	}

	function testMigrateStrategyNotInQueue() public {
		vault.trustStrategy(strategy1);
		assertEq(vault.getWithdrawalQueue().length, 0);

		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.migrateStrategy(strategy1, strategy2, 0);
		assertEq(address(vault.withdrawalQueue(0)), address(strategy2));
		(bool trusted1, uint256 balance1) = vault.getStrategyData(strategy1);
		(bool trusted2, uint256 balance2) = vault.getStrategyData(strategy2);

		assertFalse(trusted1);
		assertTrue(trusted2);

		assertEq(balance1, 0);
		assertEq(balance2, 1e18);
	}

	/*///////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

	function testSeizeStrategy() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategyBroken);
		vault.depositIntoStrategy(strategyBroken, 1e18);

		assertEq(strategyBroken.balanceOf(address(vault)), 1e18);
		assertEq(strategyBroken.balanceOf(address(this)), 0);

		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);

		IERC20[] memory tokens = new IERC20[](1);
		tokens[0] = IERC20(underlying);
		vault.seizeStrategy(strategyBroken, tokens);

		assertEq(underlying.balanceOf(address(vault)), 0);
		assertEq(underlying.balanceOf(address(this)), 1e18);

		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalFloat(), 0);

		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalFloat(), 0);

		underlying.transfer(address(vault), 1e18);

		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalFloat(), 1e18);

		vault.withdraw(1e18);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.seizeStrategy(strategy1, tokens);
	}

	function testSeizeStrategyWithBalanceGreaterThanTotalAssets() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategyBroken);
		vault.depositIntoStrategy(strategyBroken, 1e18);

		underlying.transfer(address(strategyBroken), 0.5e18);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategyBroken;

		vault.harvest(strategiesToHarvest);

		assertEq(vault.maxLockedProfit(), 0.45e18);
		(uint256 lockedProfit, ) = vault.lockedProfit();
		assertEq(lockedProfit, 0.45e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		IERC20[] memory tokens = new IERC20[](1);
		tokens[0] = IERC20(underlying);
		vault.seizeStrategy(strategyBroken, tokens);

		assertEq(vault.maxLockedProfit(), 0);
		(lockedProfit, ) = vault.lockedProfit();
		assertEq(lockedProfit, 0);

		underlying.transfer(address(vault), 1.5e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 1428571428571428571);

		vault.withdraw(1428571428571428571);
	}

	// function testFailSeizeWhenPriceMismatch() public {
	// 	underlying.mint(address(this), 1.5e18);

	// 	underlying.approve(address(vault), 1e18);
	// 	vault.deposit(1e18);

	// 	vault.trustStrategy(strategyBadPrice);
	// 	vault.depositIntoStrategy(strategyBadPrice, 1e18);

	// 	underlying.transfer(address(strategyBadPrice), 0.5e18);

	// 	Strategy[] memory strategiesToHarvest = new Strategy[](1);
	// 	strategiesToHarvest[0] = strategyBadPrice;

	// 	vault.harvest(strategiesToHarvest);

	// 	assertEq(vault.maxLockedProfit(), 0.45e18);
	// 	(uint256 lockedProfit, ) = vault.lockedProfit();
	// 	assertEq(lockedProfit, 0.45e18);

	// 	assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

	// 	IERC20[] memory tokens = new IERC20[](1);
	// 	tokens[0] = IERC20(underlying);
	// 	vault.seizeStrategy(strategyBadPrice, tokens);
	// }

	function testFailTrustStrategyWithWrongUnderlying() public {
		MockERC20 wrongUnderlying = new MockERC20("Not The Right Token", "TKN2", 18);

		MockERC20Strategy badStrategy = new MockERC20Strategy(wrongUnderlying);

		vault.trustStrategy(badStrategy);
	}

	function testFailTrustStrategyWithETHUnderlying() public {
		MockETHStrategy ethStrategy = new MockETHStrategy();

		vault.trustStrategy(ethStrategy);
	}

	/// AUTH

	function testAuthDepositIntoStrategy() public {
		vault.addStrategy(strategy1);
		vault.addStrategy(strategy2);

		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		vault.deposit(1e18);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.depositIntoStrategy(strategy2, 0.5e18);
	}

	function testAuthWithdrawFromStrategy() public {
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

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.withdrawFromStrategy(strategy1, 0.5e18);
	}
}
