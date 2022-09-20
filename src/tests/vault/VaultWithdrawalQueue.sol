// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { VaultTest } from "./Vault.t.sol";
import { Strategy } from "../../interfaces/Strategy.sol";

contract VaultWithdrawalQueueTest is VaultTest {
	/*///////////////////////////////////////////////////////////////
                        WITHDRAWAL QUEUE TESTS
    //////////////////////////////////////////////////////////////*/

	function testPushingToWithdrawalQueue() public {
		vault.pushToWithdrawalQueue(Strategy(address(69)));
		vault.pushToWithdrawalQueue(Strategy(address(420)));
		vault.pushToWithdrawalQueue(Strategy(address(1337)));
		vault.pushToWithdrawalQueue(Strategy(address(69420)));

		assertEq(vault.getWithdrawalQueue().length, 4);

		assertEq(address(vault.withdrawalQueue(0)), address(69));
		assertEq(address(vault.withdrawalQueue(1)), address(420));
		assertEq(address(vault.withdrawalQueue(2)), address(1337));
		assertEq(address(vault.withdrawalQueue(3)), address(69420));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.pushToWithdrawalQueue(Strategy(address(69)));
	}

	function testPoppingFromWithdrawalQueue() public {
		vault.pushToWithdrawalQueue(Strategy(address(69)));
		vault.pushToWithdrawalQueue(Strategy(address(420)));
		vault.pushToWithdrawalQueue(Strategy(address(1337)));
		vault.pushToWithdrawalQueue(Strategy(address(69420)));

		vault.popFromWithdrawalQueue();
		assertEq(vault.getWithdrawalQueue().length, 3);

		vault.popFromWithdrawalQueue();
		assertEq(vault.getWithdrawalQueue().length, 2);

		vault.popFromWithdrawalQueue();
		assertEq(vault.getWithdrawalQueue().length, 1);

		vault.popFromWithdrawalQueue();
		assertEq(vault.getWithdrawalQueue().length, 0);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.popFromWithdrawalQueue();
	}

	function testReplaceWithdrawalQueueIndex() public {
		Strategy[] memory newQueue = new Strategy[](4);
		newQueue[0] = Strategy(address(1));
		newQueue[1] = Strategy(address(2));
		newQueue[2] = Strategy(address(3));
		newQueue[3] = Strategy(address(4));

		vault.setWithdrawalQueue(newQueue);

		vault.replaceWithdrawalQueueIndex(1, Strategy(address(420)));

		assertEq(vault.getWithdrawalQueue().length, 4);
		assertEq(address(vault.withdrawalQueue(1)), address(420));
	}

	function testReplaceWithdrawalQueueIndexWithTip() public {
		Strategy[] memory newQueue = new Strategy[](4);
		newQueue[0] = Strategy(address(1001));
		newQueue[1] = Strategy(address(1002));
		newQueue[2] = Strategy(address(1003));
		newQueue[3] = Strategy(address(1004));

		vault.setWithdrawalQueue(newQueue);

		vault.replaceWithdrawalQueueIndexWithTip(1);

		assertEq(vault.getWithdrawalQueue().length, 3);
		assertEq(address(vault.withdrawalQueue(2)), address(1003));
		assertEq(address(vault.withdrawalQueue(1)), address(1004));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.replaceWithdrawalQueueIndexWithTip(1);
	}

	function testSwapWithdrawalQueueIndexes() public {
		Strategy[] memory newQueue = new Strategy[](4);
		newQueue[0] = Strategy(address(1001));
		newQueue[1] = Strategy(address(1002));
		newQueue[2] = Strategy(address(1003));
		newQueue[3] = Strategy(address(1004));

		vault.setWithdrawalQueue(newQueue);

		vault.swapWithdrawalQueueIndexes(1, 2);

		assertEq(vault.getWithdrawalQueue().length, 4);
		assertEq(address(vault.withdrawalQueue(1)), address(1003));
		assertEq(address(vault.withdrawalQueue(2)), address(1002));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.swapWithdrawalQueueIndexes(1, 2);
	}

	function testFailPushQueueFull() public {
		Strategy[] memory fullStack = new Strategy[](32);

		vault.setWithdrawalQueue(fullStack);

		vault.pushToWithdrawalQueue(Strategy(address(69)));
	}

	function testFailSetQueueTooBig() public {
		Strategy[] memory tooBigStack = new Strategy[](33);

		vault.setWithdrawalQueue(tooBigStack);
	}

	function testFailPopStackEmpty() public {
		vault.popFromWithdrawalQueue();
	}

	function testCleanWithdrawalQueue() public {
		vault.pushToWithdrawalQueue(Strategy(address(69)));
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(Strategy(address(1337)));
		vault.pushToWithdrawalQueue(Strategy(address(1337)));
		vault.pushToWithdrawalQueue(Strategy(address(69420)));

		vault.trustStrategy(strategy1);

		assertEq(vault.getWithdrawalQueue().length, 7);

		vm.prank(address(1));
		vault.cleanWithdrawalQueue();

		assertEq(vault.getWithdrawalQueue().length, 1);
		assertEq(address(vault.withdrawalQueue(0)), address(strategy1));
	}

	function testPushToWithdrawalQueueValidated() public {
		vault.trustStrategy(strategy1);
		vm.prank(address(1));
		vault.pushToWithdrawalQueueValidated(strategy1);
		vault.pushToWithdrawalQueueValidated(strategy1);
		assertEq(vault.getWithdrawalQueue().length, 1);
		assertEq(address(vault.withdrawalQueue(0)), address(strategy1));
	}

	function testFailPushToWithdrawalQueueValidated() public {
		vm.prank(address(1));
		vault.pushToWithdrawalQueue(Strategy(address(2)));
	}

	/// AUTH

	function testAuthSetWithdrawalQueue() public {
		Strategy[] memory newQueue = new Strategy[](4);
		newQueue[0] = Strategy(address(1));
		newQueue[1] = Strategy(address(2));
		newQueue[2] = Strategy(address(3));
		newQueue[3] = Strategy(address(4));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.setWithdrawalQueue(newQueue);
	}

	function testAuthReplaceWithdrawalQueueIndex() public {
		Strategy[] memory newQueue = new Strategy[](4);
		newQueue[0] = Strategy(address(1));
		newQueue[1] = Strategy(address(2));
		newQueue[2] = Strategy(address(3));
		newQueue[3] = Strategy(address(4));

		vault.setWithdrawalQueue(newQueue);

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.replaceWithdrawalQueueIndex(1, Strategy(address(420)));
	}
}
