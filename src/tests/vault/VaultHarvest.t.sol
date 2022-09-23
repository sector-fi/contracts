// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";
import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";

import "hardhat/console.sol";

contract VaultHarvestTest is VaultTest {
	/*///////////////////////////////////////////////////////////////
                             HARVEST TESTS
    //////////////////////////////////////////////////////////////*/

	function testProfitableHarvest() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		uint256 amount = 1e18 - minLp;
		vault.deposit(amount);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		underlying.transfer(address(strategy1), 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		assertEq(vault.lastHarvest(), 0);
		assertEq(vault.lastHarvestWindowStart(), 0);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		vault.harvest(strategiesToHarvest);

		uint256 startingTimestamp = block.timestamp;

		assertEq(vault.lastHarvest(), startingTimestamp);
		assertEq(vault.lastHarvestWindowStart(), startingTimestamp);

		(, uint256 strategyBalance) = vault.getStrategyData(strategy1);
		uint256 totalSupply = vault.totalSupply();
		uint256 exRate = (1e18 * strategyBalance) / totalSupply;
		assertEq(vault.exchangeRate(), exRate);
		assertEq(vault.exchangeRateLock(Vault.PnlLock.Withdraw), 1e18);

		assertEq(vault.totalStrategyHoldings(), 1.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldingsLock(Vault.PnlLock.Withdraw), 1.05e18);
		assertEq(vault.totalHoldings(), 1.5e18);

		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount);
		assertEq(vault.totalSupply(), 1.05e18);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0.05e18);

		vm.warp(block.timestamp + (vault.harvestDelay() / 2));

		assertEq(vault.exchangeRate(), exRate);
		// TODO rm magic numbers
		assertEq(vault.exchangeRateLock(Vault.PnlLock.Withdraw), 1214285714285714285);

		assertEq(vault.totalHoldingsLock(Vault.PnlLock.Withdraw), 1.275e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1214285714285713070);
		assertEq(vault.balanceOfUnderlying(address(vault)), 60714285714285714);

		vm.warp(block.timestamp + vault.harvestDelay());

		assertEq(vault.exchangeRateLock(Vault.PnlLock.Withdraw), 1428571428571428571);
		assertEq(vault.balanceOfUnderlying(address(this)), 1428571428571427142);
		assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571428);

		vault.redeem(amount);

		assertEq(underlying.balanceOf(address(this)), 1428571428571428142);

		assertEq(vault.exchangeRate(), 1428571428571428568);
		assertEq(vault.totalStrategyHoldings(), 70714285714287130);
		assertEq(vault.totalFloat(), 714285714285728);
		assertEq(vault.totalHoldings(), 71428571428572857);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(vault.totalSupply(), 0.05e18 + minLp);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571428);
	}

	function testUnprofitableHarvest() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		uint256 amount = 1e18 - minLp;
		vault.deposit(amount);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		strategy1.simulateLoss(0.5e18);

		assertEq(vault.exchangeRate(), 0.5e18);

		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount / 2);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		assertEq(vault.lastHarvest(), 0);
		assertEq(vault.lastHarvestWindowStart(), 0);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		vault.harvest(strategiesToHarvest);

		uint256 startingTimestamp = block.timestamp;

		assertEq(vault.lastHarvest(), startingTimestamp);
		assertEq(vault.lastHarvestWindowStart(), startingTimestamp);

		// this is because of the LockedLoss
		assertEq(vault.exchangeRate(), .5e18);
		assertEq(vault.exchangeRateLock(Vault.PnlLock.Withdraw), .5e18);

		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), amount);
		assertEq(vault.balanceOfUnderlying(address(this)), amount / 2);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		vault.redeem(amount);

		assertEq(underlying.balanceOf(address(this)), .5e18 + minLp / 2);

		assertEq(vault.exchangeRate(), .5e18);
		assertApproxEqAbs(vault.totalStrategyHoldings(), 0, minLp);
		assertApproxEqAbs(vault.totalFloat(), 0, minLp);
		assertApproxEqAbs(vault.totalHoldings(), 0, minLp);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertApproxEqAbs(vault.totalSupply(), 0, minLp);
		assertApproxEqAbs(vault.balanceOf(address(vault)), 0, minLp);
		assertApproxEqAbs(vault.balanceOfUnderlying(address(vault)), 0, minLp);
	}

	function testMultipleHarvestsInWindow() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		underlying.transfer(address(strategy1), 0.25e18);
		underlying.transfer(address(strategy2), 0.25e18);

		assertEq(vault.lastHarvest(), 0);
		assertEq(vault.lastHarvestWindowStart(), 0);

		Strategy[] memory strategiesToHarvest = new Strategy[](2);
		strategiesToHarvest[0] = strategy1;
		strategiesToHarvest[1] = strategy2;

		uint256 startingTimestamp = block.timestamp;

		console.log(vault.harvestWindow(), startingTimestamp);

		vault.harvest(strategiesToHarvest);

		console.log(vault.lastHarvest(), vault.lastHarvestWindowStart(), startingTimestamp);
		assertEq(vault.lastHarvest(), startingTimestamp);
		assertEq(vault.lastHarvestWindowStart(), startingTimestamp);

		vm.warp(block.timestamp + (vault.harvestWindow() / 2));

		uint256 exchangeRateBeforeHarvest = vault.exchangeRate();

		vault.harvest(strategiesToHarvest);

		assertEq(vault.exchangeRate(), exchangeRateBeforeHarvest);

		assertEq(vault.lastHarvest(), block.timestamp);
		assertEq(vault.lastHarvestWindowStart(), startingTimestamp);
	}

	function testUpdatingHarvestDelay() public {
		assertEq(vault.harvestDelay(), 6 hours);
		assertEq(vault.nextHarvestDelay(), 0);

		vault.setHarvestDelay(12 hours);

		assertEq(vault.harvestDelay(), 6 hours);
		assertEq(vault.nextHarvestDelay(), 12 hours);

		vault.trustStrategy(strategy1);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		vault.harvest(strategiesToHarvest);

		assertEq(vault.harvestDelay(), 12 hours);
		assertEq(vault.nextHarvestDelay(), 0);

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setHarvestDelay(100 hours);
	}

	function testUpdatingHarvestWindow() public {
		assertEq(vault.harvestWindow(), 300);

		vault.setHarvestWindow(500);

		assertEq(vault.harvestWindow(), 500);

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setHarvestWindow(100 hours);
	}

	function testClaimFees() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.transfer(address(vault), 1e18);

		assertEq(vault.balanceOf(address(vault)), 1e18);
		assertEq(vault.balanceOf(address(this)), 0);

		vault.claimFees(1e18);

		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOf(address(this)), 1e18);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.claimFees(1e18);
	}

	/*///////////////////////////////////////////////////////////////
                        HARVEST SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testAuthHarvest() public {
		Strategy[] memory strategiesToHarvest = new Strategy[](2);
		strategiesToHarvest[0] = strategy1;
		strategiesToHarvest[1] = strategy2;

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.harvest(strategiesToHarvest);
	}

	function testFailHarvestAfterWindowBeforeDelay() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		Strategy[] memory strategiesToHarvest = new Strategy[](2);
		strategiesToHarvest[0] = strategy1;
		strategiesToHarvest[1] = strategy2;

		vault.harvest(strategiesToHarvest);

		vm.warp(block.timestamp + vault.harvestWindow() + 1);

		vault.harvest(strategiesToHarvest);
	}

	function testFailHarvestUntrustedStrategy() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.distrustStrategy(strategy1);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategy1;

		vault.harvest(strategiesToHarvest);
	}

	function testFailUpdatingHarvestWindow() public {
		vault.setHarvestDelay(12 hours);
		vault.setHarvestWindow(10 hours);
		// WINDOW_TOO_LONG
		assertEq(vault.harvestWindow(), 10 hours);
	}
}
