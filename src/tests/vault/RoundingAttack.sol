// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";
import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";

import "hardhat/console.sol";

contract RoundingAttack is VaultTest {
	function testRoundingAttack() public {
		vault.setPublic(true);
		address attacker = address(4);
		address victim = address(5);
		underlying.mint(attacker, 1.5e18);

		// start of attack
		vm.startPrank(attacker);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);
		uint256 balance = vault.balanceOf(attacker);
		vault.redeem(balance - 1);

		underlying.approve(address(vault), 1e18);
		underlying.transfer(address(vault), 1e18);
		vm.stopPrank();
		// end of attack

		underlying.mint(victim, 2e18);
		vm.startPrank(victim);
		underlying.approve(address(vault), 2e18);
		// if attack is successfull, depositing less than 1e18 will return 0 shares
		vault.deposit(1e18 - 1);
		vm.stopPrank();

		// victim losses should not exceed .1 %
		assertApproxEqAbs(vault.balanceOfUnderlying(victim), 1e18 - 1, 10**(18 - 3));
		assertApproxEqAbs(vault.balanceOfUnderlying(attacker), 0, 10**(18 - 3));
	}
}
