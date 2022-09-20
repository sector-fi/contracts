// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { ScionTest } from "../utils/ScionTest.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import { MockERC20Strategy } from "../mocks/MockERC20Strategy.sol";
import { MockETHStrategy } from "../mocks/MockETHStrategy.sol";

import { WETH } from "../mocks/WETH.sol";

contract VaultsETHTest is ScionTest {
	Vault wethVault;
	WETH weth;

	MockETHStrategy ethStrategy;
	MockERC20Strategy erc20Strategy;

	function setUp() public {
		weth = new WETH();

		Vault vaultImp = new Vault();
		UpgradeableBeacon beacon = new UpgradeableBeacon(address(vaultImp));

		VaultFactory factory = new VaultFactory(beacon);

		bytes memory data = abi.encodeWithSignature(
			"initialize(address,address,address,uint256,uint64,uint128)",
			weth,
			address(this),
			address(this),
			0.1e18,
			6 hours,
			5 minutes
		);

		wethVault = Vault(payable(address(factory.deployVault(weth, 0, data))));

		wethVault.setTargetFloatPercent(0.01e18);

		wethVault.setUnderlyingIsWETH(true);

		ethStrategy = new MockETHStrategy();
		erc20Strategy = new MockERC20Strategy(weth);
	}

	function testTrustStrategyWithETHUnderlying() public {
		wethVault.trustStrategy(ethStrategy);

		(bool trusted, ) = wethVault.getStrategyData(ethStrategy);
		assertTrue(trusted);
	}

	function testTrustStrategyWithWETHUnderlying() public {
		wethVault.trustStrategy(erc20Strategy);

		(bool trusted, ) = wethVault.getStrategyData(erc20Strategy);
		assertTrue(trusted);
	}
}
