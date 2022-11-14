// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { ScionTest } from "../utils/ScionTest.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

import { MockERC20Strategy, MockERC20StrategyBroken, MockERC20StrategyPriceMismatch } from "../mocks/MockERC20Strategy.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "hardhat/console.sol";

contract VaultTest is ScionTest {
	Vault vault;
	MockERC20 underlying;

	MockERC20Strategy strategy1;
	MockERC20Strategy strategy2;
	uint8 DECIMALS = 18;
	MockERC20StrategyBroken strategyBroken;
	MockERC20StrategyPriceMismatch strategyBadPrice;

	uint256 minLp;

	function setUp() public {
		underlying = new MockERC20("Mock Token", "TKN", DECIMALS);

		Vault vaultImp = new Vault();

		UpgradeableBeacon beacon = new UpgradeableBeacon(address(vaultImp));

		VaultFactory factory = new VaultFactory(beacon);

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
		strategyBroken = new MockERC20StrategyBroken(underlying);
		strategyBadPrice = new MockERC20StrategyPriceMismatch(underlying);

		// make sure our timestamp is > harvestDelay
		vm.warp(block.timestamp + vault.harvestDelay());

		// deposit locked lp
		minLp = vault.MIN_LIQUIDITY();
		vault.setAllowed(address(999), true);
		vm.startPrank(address(999));
		deal(address(underlying), address(999), minLp);
		underlying.approve(address(vault), minLp);
		vault.deposit(minLp);
		vm.stopPrank();
	}

	/// UTILS
	function depositIntoStrat(MockERC20Strategy strategy, uint256 amount) internal {
		depositIntoStrat(address(this), strategy, amount);
	}

	function depositIntoStrat(
		address from,
		MockERC20Strategy strategy,
		uint256 amount
	) internal {
		(bool isTrusted, ) = vault.getStrategyData(strategy);
		if (!isTrusted) {
			vault.trustStrategy(strategy);
			vault.pushToWithdrawalQueue(strategy);
		}
		if (!vault.isAllowed(from)) vault.setAllowed(from, true);
		vm.startPrank(from);
		underlying.mint(from, amount);
		underlying.approve(address(vault), amount);
		vault.deposit(amount);
		vm.stopPrank();
		vault.depositIntoStrategy(strategy, amount);
	}

	receive() external payable {}
}
