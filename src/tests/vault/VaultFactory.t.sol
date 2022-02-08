// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { DSTestPlus } from "../utils/DSTestPlus.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract VaultFactoryTest is DSTestPlus {
	VaultFactory vaultFactory;

	MockERC20 underlying;

	function setUp() public {
		underlying = new MockERC20("Mock Token", "TKN", 18);
		Vault vaultImp = new Vault();
		vaultFactory = new VaultFactory(address(vaultImp));
	}

	function testDeployVault() public {
		bytes memory data = abi.encodeWithSignature(
			"initialize(address,address,address,uint256,uint64,uint128)",
			underlying,
			address(this),
			address(this),
			uint256(0),
			uint64(2),
			uint128(1)
		);

		BeaconProxy vault = vaultFactory.deployVault(underlying, 0, data);
		address vaultAddr = address(payable(vault));

		assertTrue(vaultFactory.isVaultDeployed(vaultAddr));
		assertEq(address(vaultFactory.getVaultFromUnderlying(underlying, 0)), vaultAddr);
		assertEq(address(Vault(payable(vaultAddr)).UNDERLYING()), address(underlying));
	}

	function testFailNoDuplicateVaults() public {
		bytes memory data1 = abi.encodeWithSignature(
			"initialize(address,address,address,uint256,uint64,uint128)",
			underlying,
			address(this),
			address(this),
			1,
			3,
			1
		);
		bytes memory data2 = abi.encodeWithSignature(
			"initialize(address,address,address,uint256,uint64,uint128)",
			underlying,
			address(this),
			address(this),
			2,
			3,
			1
		);
		vaultFactory.deployVault(underlying, 0, data1);
		vaultFactory.deployVault(underlying, 0, data2);
	}
}
