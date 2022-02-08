// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.10;

import { DSTestPlus } from "../utils/DSTestPlus.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockERC20Strategy } from "../mocks/MockERC20Strategy.sol";

import { Strategy } from "../../interfaces/Strategy.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";

contract IntegrationTest is DSTestPlus {
	MockERC20 underlying;
	Vault vault;

	MockERC20Strategy strategy1;
	MockERC20Strategy strategy2;

	function setUp() public {
		underlying = new MockERC20("Mock Token", "TKN", 18);

		Vault vaultImp = new Vault();

		VaultFactory factory = new VaultFactory(address(vaultImp));

		bytes memory data = abi.encodeWithSignature(
			"initialize(address,address,address,uint256,uint64,uint128)",
			underlying,
			address(this),
			address(this),
			0.1e18,
			6 hours,
			5 minutes
		);

		vault = Vault(payable(address(factory.deployVault(underlying, 0, data))));

		vault.setTargetFloatPercent(0.01e18);

		strategy1 = new MockERC20Strategy(underlying);
		strategy2 = new MockERC20Strategy(underlying);
	}

	function testIntegration() public {
		// TODO init & test user roles

		// TEST setting configs

		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);
		vault.pushToWithdrawalQueue(strategy1);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);
		vault.pushToWithdrawalQueue(strategy2);

		vault.setFeePercent(0.2e18);
		assertEq(vault.feePercent(), 0.2e18);

		underlying.transfer(address(strategy1), 0.25e18);

		Strategy[] memory strategiesToHarvest = new Strategy[](2);
		strategiesToHarvest[0] = strategy1;
		strategiesToHarvest[1] = strategy2;

		underlying.transfer(address(strategy2), 0.25e18);
		vault.harvest(strategiesToHarvest);

		hevm.warp(block.timestamp + vault.harvestDelay());

		vault.withdraw(1363636363636363636);
		assertEq(vault.balanceOf(address(this)), 0);
	}
}
