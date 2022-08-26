// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";

contract VaultConfigTest is VaultTest {
	/*///////////////////////////////////////////////////////////////
                        MISC TESTS
    //////////////////////////////////////////////////////////////*/

	function testDecimals() public {
		assertEq(vault.decimals(), DECIMALS);
	}

	function testSetFeePercent() public {
		vault.setFeePercent(0.1e18);
		assertEq(vault.feePercent(), 0.1e18);

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setFeePercent(0.1e18);
	}

	function testFailSetFeePercent() public {
		vault.setFeePercent(1.1e18);
	}

	function testAuthSetUnderlyingIsWETH() public {
		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setUnderlyingIsWETH(true);
	}

	/*///////////////////////////////////////////////////////////////
                        MANAGER TESTS
    //////////////////////////////////////////////////////////////*/

	function testOwnerIsManager() public {
		// owner should be manager
		assertTrue(vault.isManager(address(this)));
	}

	function testManager() public {
		assertFalse(vault.isManager(address(0xcafe)));
		assertFalse(vault.isManager(address(0xface)));

		vault.setManager(address(0xcafe), true);

		assertTrue(vault.isManager(address(0xcafe)));
		assertFalse(vault.isManager(address(0xface)));

		vault.setManager(address(0xcafe), false);
		vault.setManager(address(0xface), true);

		assertFalse(vault.isManager(address(0xcafe)));
		assertTrue(vault.isManager(address(0xface)));
	}

	function testManagerEdge() public {
		vault.setManager(address(0xcafe), false);
		assertFalse(vault.isManager(address(0xface)));

		vault.setManager(address(0xcafe), true);
		vault.setManager(address(0xcafe), true);

		assertTrue(vault.isManager(address(0xcafe)));

		vault.setManager(address(0xcafe), false);
		vault.setManager(address(0xcafe), false);

		assertFalse(vault.isManager(address(0xface)));

		vault.setManager(address(0xcafe), false);
		vault.setManager(address(0xface), true);

		assertFalse(vault.isManager(address(0xcafe)));
		assertTrue(vault.isManager(address(0xface)));

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setManager(address(0xcafe), false);
	}

	/*///////////////////////////////////////////////////////////////
                        SET PUBLIC TESTS
    //////////////////////////////////////////////////////////////*/

	function testIsPublic() public {
		assertFalse(vault.isPublic());

		vault.setPublic(true);

		assertTrue(vault.isPublic());

		vault.setPublic(false);

		assertFalse(vault.isPublic());
	}

	function testIsPublicEdge() public {
		vault.setPublic(false);

		assertFalse(vault.isPublic());

		vault.setPublic(false);

		assertFalse(vault.isPublic());

		vault.setPublic(true);

		assertTrue(vault.isPublic());

		vault.setPublic(true);

		assertTrue(vault.isPublic());

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.setPublic(true);
	}

	/*///////////////////////////////////////////////////////////////
                        SET ALLOWED TESTS
    //////////////////////////////////////////////////////////////*/

	function testOwnerAndManagerAllowed() public {
		// owner should be "allowed"
		assertTrue(vault.isAllowed(address(this)));
		vault.setManager(address(0x123), true);
		assertTrue(vault.isAllowed(address(0x123)));
	}

	function testAllowed() public {
		assertFalse(vault.isAllowed(address(0xcafe)));
		assertFalse(vault.isAllowed(address(0xface)));

		vault.setAllowed(address(0xcafe), true);

		assertTrue(vault.isAllowed(address(0xcafe)));
		assertFalse(vault.isAllowed(address(0xface)));

		vault.setAllowed(address(0xcafe), false);
		vault.setAllowed(address(0xface), true);

		assertFalse(vault.isAllowed(address(0xcafe)));
		assertTrue(vault.isAllowed(address(0xface)));
	}

	function testFailAllowedAuth() public {
		vm.prank(address(1));
		vault.setAllowed(address(0xcafe), false);
	}

	function testBulkAllow() public {
		address[] memory address_array = new address[](4);
		address_array[0] = address(0xa);
		address_array[1] = address(0xb);
		address_array[2] = address(0xc);
		address_array[3] = address(0xd);

		vault.bulkAllow(address_array);

		assertTrue(vault.isAllowed(address(0xa)));
		assertTrue(vault.isAllowed(address(0xb)));
		assertTrue(vault.isAllowed(address(0xc)));
		assertTrue(vault.isAllowed(address(0xd)));
		assertFalse(vault.isAllowed(address(0xcafe)));

		vault.setAllowed(address(0xa), false);
		assertFalse(vault.isAllowed(address(0xa)));
		assertTrue(vault.isAllowed(address(0xb)));
	}

	function testFailBulkAllowAuth() public {
		address[] memory address_array = new address[](3);
		address_array[0] = address(0x1);
		address_array[1] = address(0x2);
		address_array[2] = address(0x3);

		vm.prank(address(1));
		vault.bulkAllow(address_array);
	}

	/*///////////////////////////////////////////////////////////////
                        SET MAX TVL & STRAT TVL TESTS
    //////////////////////////////////////////////////////////////*/

	function testSetMaxTvl() public {
		assertEq(vault.getMaxTvl(), type(uint256).max);

		vault.setMaxTvl(5e18);

		assertEq(vault.getMaxTvl(), 5e18);

		underlying.mint(address(this), 5e18);
		underlying.approve(address(vault), 5e18);

		vault.deposit(5e18);

		vault.setMaxTvl(1e18);

		assertEq(vault.getMaxTvl(), 1e18);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.setMaxTvl(1e18);
	}

	function testSetMaxTvlFuzz(uint128 fuzz) public {
		assertEq(vault.getMaxTvl(), type(uint256).max);

		vault.setMaxTvl(fuzz);

		assertEq(vault.getMaxTvl(), fuzz);

		underlying.mint(address(this), fuzz);
		underlying.approve(address(vault), fuzz);

		vault.deposit(fuzz);

		vault.setMaxTvl(1e18);

		assertEq(vault.getMaxTvl(), 1e18);
	}

	function testUpdateStratTvl() public {
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy2);

		assertEq(vault.getMaxTvl(), type(uint256).max);

		strategy1.setMaxTvl(10e18);
		strategy2.setMaxTvl(5e18);
		vault.updateStratTvl();

		assertEq(vault.getMaxTvl(), 10e18 + 5e18);

		strategy1.setMaxTvl(5e18);
		strategy2.setMaxTvl(25e18);
		vault.updateStratTvl();

		assertEq(vault.getMaxTvl(), 5e18 + 25e18);

		underlying.mint(address(this), 5e18 + 25e18);
		underlying.approve(address(vault), 5e18 + 25e18);

		vault.deposit(5e18 + 25e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 5e18 + 25e18);
		vault.popFromWithdrawalQueue();
		vault.popFromWithdrawalQueue();
	}

	function testUpdateStratTvlFuzz(uint128 fuzz) public {
		fuzz = uint128(toRange(fuzz, 0, type(uint128).max - 25e18));

		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy2);

		assertEq(vault.getMaxTvl(), type(uint256).max);

		// make sure we don't overflow
		strategy1.setMaxTvl(type(uint256).max);
		strategy2.setMaxTvl(type(uint256).max);
		vault.updateStratTvl();

		assertEq(vault.getMaxTvl(), type(uint256).max);

		strategy1.setMaxTvl(fuzz);
		strategy2.setMaxTvl(25e18);
		vault.updateStratTvl();

		assertEq(vault.getMaxTvl(), fuzz + 25e18);

		underlying.mint(address(this), fuzz + 25e18);
		underlying.approve(address(vault), fuzz + 25e18);

		vault.deposit(fuzz + 25e18);

		assertEq(vault.balanceOfUnderlying(address(this)), fuzz + 25e18);
		vault.popFromWithdrawalQueue();
		vault.popFromWithdrawalQueue();

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.updateStratTvl();
	}
}
