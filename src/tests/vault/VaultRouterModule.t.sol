// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { WETH } from "../../tokens/WETH.sol";
import { DSTestPlus } from "../utils/DSTestPlus.sol";

import { VaultRouterModule } from "../../vault/modules/VaultRouterModule.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract VaultRouterModuleTest is DSTestPlus {
	Vault wethVault;
	WETH weth;

	VaultRouterModule vaultRouterModule;

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

		vaultRouterModule = new VaultRouterModule();

		wethVault.setAllowed(address(vaultRouterModule), true);
	}

	/*///////////////////////////////////////////////////////////////
                      ETH DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testAtomicDepositWithdrawETH() public {
		wethVault.setUnderlyingIsWETH(true);

		uint256 startingETHBal = address(this).balance;

		vaultRouterModule.depositETHIntoVault{ value: 1 ether }(wethVault);

		assertEq(address(this).balance, startingETHBal - 1 ether);

		assertEq(wethVault.balanceOf(address(this)), 1e18);
		assertEq(wethVault.balanceOfUnderlying(address(this)), 1 ether);

		wethVault.approve(address(vaultRouterModule), 1e18);
		vaultRouterModule.withdrawETHFromVault(wethVault, 1 ether);

		assertEq(address(this).balance, startingETHBal);
	}

	function testAtomicDepositRedeemETH() public {
		wethVault.setUnderlyingIsWETH(true);

		uint256 startingETHBal = address(this).balance;

		vaultRouterModule.depositETHIntoVault{ value: 69 ether }(wethVault);

		assertEq(address(this).balance, startingETHBal - 69 ether);

		assertEq(wethVault.balanceOf(address(this)), 69e18);
		assertEq(wethVault.balanceOfUnderlying(address(this)), 69 ether);

		wethVault.approve(address(vaultRouterModule), 69e19);
		vaultRouterModule.redeemETHFromVault(wethVault, 69e18);

		assertEq(address(this).balance, startingETHBal);
	}

	/*///////////////////////////////////////////////////////////////
               ETH DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testFailDepositIntoNotWETHVault() public {
		vaultRouterModule.depositETHIntoVault{ value: 1 ether }(wethVault);
	}

	function testFailWithdrawFromNotWETHVault() public {
		wethVault.setUnderlyingIsWETH(true);

		vaultRouterModule.depositETHIntoVault{ value: 1 ether }(wethVault);

		wethVault.setUnderlyingIsWETH(false);

		wethVault.approve(address(vaultRouterModule), 1e18);

		vaultRouterModule.withdrawETHFromVault(wethVault, 1 ether);
	}

	function testFailRedeemFromNotWETHVault() public {
		wethVault.setUnderlyingIsWETH(true);

		vaultRouterModule.depositETHIntoVault{ value: 1 ether }(wethVault);

		wethVault.setUnderlyingIsWETH(false);

		wethVault.approve(address(vaultRouterModule), 1e18);

		vaultRouterModule.redeemETHFromVault(wethVault, 1e18);
	}

	receive() external payable {}
}
