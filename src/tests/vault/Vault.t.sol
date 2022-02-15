// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { WETH } from "../../tokens/WETH.sol";
import { DSTestPlus } from "../utils/DSTestPlus.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MockETHStrategy } from "../mocks/MockETHStrategy.sol";
import { MockERC20Strategy, MockERC20StrategyBroken, MockERC20StrategyPriceMismatch } from "../mocks/MockERC20Strategy.sol";

import { Strategy } from "../../interfaces/Strategy.sol";

import { VaultUpgradable as Vault } from "../../vault/VaultUpgradable.sol";
import { ScionVaultFactory as VaultFactory } from "../../vault/ScionVaultFactory.sol";

import "hardhat/console.sol";

interface Vm {
	function prank(address) external;

	function expectRevert(bytes calldata) external;
}

contract VaultsTest is DSTestPlus {
	Vault vault;
	MockERC20 underlying;
	Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

	MockERC20Strategy strategy1;
	MockERC20Strategy strategy2;
	uint8 DECIMALS = 18;
	MockERC20StrategyBroken strategyBroken;
	MockERC20StrategyPriceMismatch strategyBadPrice;

	function setUp() public {
		underlying = new MockERC20("Mock Token", "TKN", DECIMALS);

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
		strategyBroken = new MockERC20StrategyBroken(underlying);
		strategyBadPrice = new MockERC20StrategyPriceMismatch(underlying);
	}

	/*///////////////////////////////////////////////////////////////
                        MISC TESTS
    //////////////////////////////////////////////////////////////*/

	function testDecimals() public {
		assertEq(vault.decimals(), DECIMALS);
	}

	function testAuthSetUnderlyingIsWETH() public {
		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setUnderlyingIsWETH(true);
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

	function testAllowedEdge() public {
		vault.setAllowed(address(0xcafe), false);
		assertFalse(vault.isAllowed(address(0xface)));

		vault.setAllowed(address(0xcafe), true);
		vault.setAllowed(address(0xcafe), true);

		assertTrue(vault.isAllowed(address(0xcafe)));

		vault.setAllowed(address(0xcafe), false);
		vault.setAllowed(address(0xcafe), false);

		assertFalse(vault.isAllowed(address(0xface)));

		vault.setAllowed(address(0xcafe), false);
		vault.setAllowed(address(0xface), true);

		assertFalse(vault.isAllowed(address(0xcafe)));
		assertTrue(vault.isAllowed(address(0xface)));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
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

	function testBulkAllowEdge() public {
		address[] memory address_array = new address[](4);
		address_array[0] = address(0x1);
		address_array[1] = address(0x2);
		address_array[2] = address(0x3);
		address_array[3] = address(0x4);

		vault.setAllowed(address(0x1), true);
		vault.bulkAllow(address_array);

		assertTrue(vault.isAllowed(address(0x1)));
		assertTrue(vault.isAllowed(address(0x2)));
		assertTrue(vault.isAllowed(address(0x3)));
		assertTrue(vault.isAllowed(address(0x4)));

		vault.setAllowed(address(0x1), false);

		assertFalse(vault.isAllowed(address(0x1)));

		vault.setAllowed(address(0x1), true);
		vault.bulkAllow(address_array);

		assertTrue(vault.isAllowed(address(0x1)));
		assertTrue(vault.isAllowed(address(0x2)));
		assertTrue(vault.isAllowed(address(0x3)));
		assertTrue(vault.isAllowed(address(0x4)));

		vm.prank(address(1));
		vm.expectRevert("Vault: NO_AUTH");
		vault.bulkAllow(address_array);
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
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testAtomicDepositWithdraw() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		uint256 preDepositBal = underlying.balanceOf(address(this));

		vault.deposit(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - 1e18);

		vault.withdraw(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(underlying.balanceOf(address(this)), preDepositBal);
	}

	function testAtomicDepositRedeem() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		uint256 preDepositBal = underlying.balanceOf(address(this));

		vault.deposit(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(underlying.balanceOf(address(this)), preDepositBal - 1e18);

		vault.redeem(1e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(underlying.balanceOf(address(this)), preDepositBal);
	}

	/*///////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testFailDepositWithNotEnoughApproval() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(1e18);
	}

	function testFailWithdrawWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.withdraw(1e18);
	}

	function testFailRedeemWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.redeem(1e18);
	}

	function testFailRedeemWithNoBalance() public {
		vault.redeem(1e18);
	}

	function testFailWithdrawWithNoBalance() public {
		vault.withdraw(1e18);
	}

	function testFailDepositWithNoApproval() public {
		vault.deposit(1e18);
	}

	/*///////////////////////////////////////////////////////////////
                     STRATEGY DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testAtomicEnterExitSinglePool() public {
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

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
	}

	function testAtomicEnterExitMultiPool() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.trustStrategy(strategy2);

		vault.depositIntoStrategy(strategy2, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy1, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		vault.withdrawFromStrategy(strategy2, 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.totalFloat(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
	}

	function testSetTargetFloatPercent() public {
		vault.setTargetFloatPercent(0.5e18);

		assertEq(vault.targetFloatPercent(), 0.5e18);

		vault.setTargetFloatPercent(1e15);

		assertEq(vault.targetFloatPercent(), 1e15);
	}

	/*///////////////////////////////////////////////////////////////
              STRATEGY DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

	function testFailDepositIntoStrategyWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);

		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithNotEnoughBalance() public {
		underlying.mint(address(this), 0.5e18);
		underlying.approve(address(vault), 0.5e18);

		vault.deposit(0.5e18);
		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithoutTrust() public {
		underlying.mint(address(this), 1e18);
		underlying.approve(address(vault), 1e18);

		vault.deposit(1e18);
		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.distrustStrategy(strategy1);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailDepositIntoStrategyWithNoBalance() public {
		vault.trustStrategy(strategy1);

		vault.depositIntoStrategy(strategy1, 1e18);
	}

	function testFailWithdrawFromStrategyWithNoBalance() public {
		vault.trustStrategy(strategy1);

		vault.withdrawFromStrategy(strategy1, 1e18);
	}

	function testFailSetTargetFloatPercentOver100() public {
		vault.setTargetFloatPercent(1.1e18);

		vm.prank(address(1));
		vm.expectRevert("Ownable: caller is not the owner");
		vault.setTargetFloatPercent(0.5e18);
	}

	/*///////////////////////////////////////////////////////////////
                             HARVEST TESTS
    //////////////////////////////////////////////////////////////*/

	function testProfitableHarvest() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		underlying.transfer(address(strategy1), 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
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

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1.05e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(vault.totalSupply(), 1.05e18);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0.05e18);

		hevm.warp(block.timestamp + (vault.harvestDelay() / 2));

		assertEq(vault.exchangeRate(), 1214285714285714285);
		assertEq(vault.totalStrategyHoldings(), 1.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1.275e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1214285714285714285);
		assertEq(vault.totalSupply(), 1.05e18);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 60714285714285714);

		hevm.warp(block.timestamp + vault.harvestDelay());

		assertEq(vault.exchangeRate(), 1428571428571428571);
		assertEq(vault.totalStrategyHoldings(), 1.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1428571428571428571);
		assertEq(vault.totalSupply(), 1.05e18);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571428);

		vault.redeem(1e18);

		assertEq(underlying.balanceOf(address(this)), 1428571428571428571);

		assertEq(vault.exchangeRate(), 1428571428571428580);
		assertEq(vault.totalStrategyHoldings(), 70714285714285715);
		assertEq(vault.totalFloat(), 714285714285714);
		assertEq(vault.totalHoldings(), 71428571428571429);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(vault.totalSupply(), 0.05e18);
		assertEq(vault.balanceOf(address(vault)), 0.05e18);
		assertEq(vault.balanceOfUnderlying(address(vault)), 71428571428571429);
	}

	function testUnprofitableHarvest() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		strategy1.simulateLoss(0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 1e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 1e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);
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

		assertEq(vault.exchangeRate(), 0.5e18);
		assertEq(vault.totalStrategyHoldings(), 0.5e18);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 0.5e18);
		assertEq(vault.balanceOf(address(this)), 1e18);
		assertEq(vault.balanceOfUnderlying(address(this)), 0.5e18);
		assertEq(vault.totalSupply(), 1e18);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);

		vault.redeem(1e18);

		assertEq(underlying.balanceOf(address(this)), 0.5e18);

		assertEq(vault.exchangeRate(), 1e18);
		assertEq(vault.totalStrategyHoldings(), 0);
		assertEq(vault.totalFloat(), 0);
		assertEq(vault.totalHoldings(), 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.balanceOfUnderlying(address(this)), 0);
		assertEq(vault.totalSupply(), 0);
		assertEq(vault.balanceOf(address(vault)), 0);
		assertEq(vault.balanceOfUnderlying(address(vault)), 0);
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

		vault.harvest(strategiesToHarvest);

		uint256 startingTimestamp = block.timestamp;

		assertEq(vault.lastHarvest(), startingTimestamp);
		assertEq(vault.lastHarvestWindowStart(), startingTimestamp);

		hevm.warp(block.timestamp + (vault.harvestWindow() / 2));

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

		hevm.warp(block.timestamp + vault.harvestWindow() + 1);

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

	/*///////////////////////////////////////////////////////////////
                            EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

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

	function testWithdrawingWithDuplicateStrategiesInQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy2);
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.getWithdrawalQueue().length, 5);

		vault.redeem(1e18);

		assertEq(vault.getWithdrawalQueue().length, 2);

		assertEq(address(vault.withdrawalQueue(0)), address(strategy1));
		assertEq(address(vault.withdrawalQueue(1)), address(strategy1));
	}

	function testWithdrawingWithUntrustedStrategyInQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		vault.pushToWithdrawalQueue(strategy2);
		vault.pushToWithdrawalQueue(strategy2);
		vault.pushToWithdrawalQueue(new MockERC20Strategy(underlying));
		vault.pushToWithdrawalQueue(strategy1);
		vault.pushToWithdrawalQueue(strategy1);

		assertEq(vault.getWithdrawalQueue().length, 5);

		vault.redeem(1e18);

		assertEq(vault.getWithdrawalQueue().length, 1);

		assertEq(address(vault.withdrawalQueue(0)), address(strategy2));
	}

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
		assertEq(vault.lockedProfit(), 0.45e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		IERC20[] memory tokens = new IERC20[](1);
		tokens[0] = IERC20(underlying);
		vault.seizeStrategy(strategyBroken, tokens);

		assertEq(vault.maxLockedProfit(), 0);
		assertEq(vault.lockedProfit(), 0);

		underlying.transfer(address(vault), 1.5e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 1428571428571428571);

		vault.withdraw(1428571428571428571);
	}

	function testFailSeizeWhenPriceMismatch() public {
		underlying.mint(address(this), 1.5e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategyBadPrice);
		vault.depositIntoStrategy(strategyBadPrice, 1e18);

		underlying.transfer(address(strategyBadPrice), 0.5e18);

		Strategy[] memory strategiesToHarvest = new Strategy[](1);
		strategiesToHarvest[0] = strategyBadPrice;

		vault.harvest(strategiesToHarvest);

		assertEq(vault.maxLockedProfit(), 0.45e18);
		assertEq(vault.lockedProfit(), 0.45e18);

		assertEq(vault.balanceOfUnderlying(address(this)), 1e18);

		IERC20[] memory tokens = new IERC20[](1);
		tokens[0] = IERC20(underlying);
		vault.seizeStrategy(strategyBadPrice, tokens);
	}

	function testFailTrustStrategyWithWrongUnderlying() public {
		MockERC20 wrongUnderlying = new MockERC20("Not The Right Token", "TKN2", 18);

		MockERC20Strategy badStrategy = new MockERC20Strategy(wrongUnderlying);

		vault.trustStrategy(badStrategy);
	}

	function testFailTrustStrategyWithETHUnderlying() public {
		MockETHStrategy ethStrategy = new MockETHStrategy();

		vault.trustStrategy(ethStrategy);
	}

	function testFailWithdrawWithEmptyQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 1e18);

		vault.redeem(1e18);
	}

	function testFailWithdrawWithIncompleteQueue() public {
		underlying.mint(address(this), 1e18);

		underlying.approve(address(vault), 1e18);
		vault.deposit(1e18);

		vault.trustStrategy(strategy1);
		vault.depositIntoStrategy(strategy1, 0.5e18);

		vault.pushToWithdrawalQueue(strategy1);

		vault.trustStrategy(strategy2);
		vault.depositIntoStrategy(strategy2, 0.5e18);

		vault.redeem(1e18);
	}
}

contract VaultsETHTest is DSTestPlus {
	Vault wethVault;
	WETH weth;

	MockETHStrategy ethStrategy;
	MockERC20Strategy erc20Strategy;

	function setUp() public {
		weth = new WETH();

		Vault vaultImp = new Vault();
		VaultFactory factory = new VaultFactory(address(vaultImp));

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

	function testAtomicDepositWithdrawIntoETHStrategies() public {
		uint256 startingETHBal = address(this).balance;

		weth.deposit{ value: 1 ether }();

		assertEq(address(this).balance, startingETHBal - 1 ether);

		weth.approve(address(wethVault), 1e18);
		wethVault.deposit(1e18);

		wethVault.trustStrategy(ethStrategy);
		wethVault.depositIntoStrategy(ethStrategy, 0.5e18);
		wethVault.pushToWithdrawalQueue(ethStrategy);

		wethVault.trustStrategy(erc20Strategy);
		wethVault.depositIntoStrategy(erc20Strategy, 0.5e18);
		wethVault.pushToWithdrawalQueue(erc20Strategy);

		wethVault.withdrawFromStrategy(ethStrategy, 0.25e18);
		wethVault.withdrawFromStrategy(erc20Strategy, 0.25e18);

		wethVault.redeem(1e18);

		weth.withdraw(1 ether);

		assertEq(address(this).balance, startingETHBal);
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

	receive() external payable {}
}
