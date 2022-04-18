process.env.MAX_TX_TIME = '500';
process.env.NODE_ENV = 'test';

import { expect } from 'chai';
import { ethers, getNamedAccounts, deployments } from 'hardhat';
import { init as harvester } from '@sc1/server/harvester';
import { BigNumber } from 'ethers';

import {
  forkNetwork,
  buyUnderlying,
  getErc20,
  fundAccount,
  setupAccount,
  setMiningInterval,
  waitFor,
  forkBlock,
  approve,
  movePriceBy,
  mockChainlink,
  getVault,
  chain,
  setOraclePriceOffset,
  copyDeployments,
  disableBandFeed,
} from '../utils';
import { mockServer, mockStrat } from '../utils/mocks/server';
import { getAddr, getUniAddr } from '@sc1/common/utils/address';
import { sendTx, rebalanceBot } from '@sc1/server/keeper';
import { strategies } from '@sc1/common';
import { getGasPrice } from '@sc1/server/keeper/gas';

const { utils, getSigner } = ethers;
const { parseUnits, getAddress } = utils;
const { MaxUint256 } = ethers.constants;

const { MAX_TX_TIME } = process.env;

const USDC = getAddr('USDC', chain);
const BASE = getAddr('BASE', chain);

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['Mocks', 'Strategies']);
  await setMiningInterval(0);
  const { manager, deployer } = await getNamedAccounts();
  await setupAccount(deployer);
  await fundAccount(deployer, '1000000000');
  await setupAccount(manager);

  const vault = await getVault();
  const underlying = await vault.UNDERLYING();
  await approve(underlying, deployer, vault.address);
  return { vault };
});

describe('Server Test', function () {
  this.timeout(200000); // fantom is slow
  let testStrat;

  before(async () => {
    await forkNetwork(chain, forkBlock[chain]);
    await copyDeployments(chain);

    testStrat = strategies.filter((s) => s.chain === chain)[0];
    const { deployer } = await getNamedAccounts();
    await setupAccount(deployer);
    const router = getUniAddr('UNISWAP_ROUTER', testStrat.swap);
    await approve(testStrat.underlying, deployer, router);
    await disableBandFeed(testStrat); // additional oracle for fantom
  });

  describe('tx', async () => {
    let usdc;

    before(async () => {
      await setupTest();
      const { manager } = await getNamedAccounts();
      usdc = await getErc20(USDC, manager);
      await buyUnderlying(
        manager,
        USDC,
        BASE,
        parseUnits('200', 6),
        testStrat.swap,
        chain
      );
      await setMiningInterval(3000);
    });

    it('should resubmit tx after timeout', async function () {
      const { deployer, manager } = await getNamedAccounts();
      const signer = await getSigner(manager);
      const nonce = await signer.getTransactionCount();

      const balance = await usdc.balanceOf(manager);
      console.log(balance.toString());

      const gasPrice = await getGasPrice(chain, 'normal', ethers.provider);
      const tx1 = sendTx(chain, usdc, 'transfer', [
        manager,
        parseUnits('10', 6),
      ]);

      // wait slightly longer than our MAX_TX_TIME to enable replacement of tx
      await waitFor(parseInt(MAX_TX_TIME, 10) + 500);

      const tx2Res = await sendTx(chain, usdc, 'transfer', [
        deployer,
        parseUnits('10', 6),
      ]);

      // wait for second tx to execute
      await waitFor(3000);

      const t1Reciept = await signer?.provider?.getTransactionReceipt(
        (await tx1)?.transactionHash || ''
      );

      const t2Reciept = await signer?.provider?.getTransactionReceipt(
        tx2Res?.transactionHash || ''
      );

      // tx1 should be replaced and revert
      expect(t1Reciept?.status).to.not.be.equal(1);
      expect(t2Reciept?.status).to.be.equal(1);
      expect(t2Reciept?.effectiveGasPrice).to.be.eq(
        BigNumber.from(Math.round(gasPrice * 1.11))
      );
      const updatedNonce = await signer.getTransactionCount();
      expect(updatedNonce).to.be.equal(nonce + 1);
    });
  });

  describe('Rebalance', async () => {
    let vault;

    before(async () => {
      await setMiningInterval(0);
      ({ vault } = await setupTest());
      await setMiningInterval(0);
      await mockStrat(Math.round(Date.now() / 1000) - 60 * 60 * 24);
    });

    it('should rebalance', async function () {
      const amnt = parseUnits('100', 6);
      await vault.setMaxTvl(MaxUint256);
      await vault.deposit(amnt);

      const { deployer, manager } = await getNamedAccounts();
      const strategy = await ethers.getContract(testStrat.symbol, manager);
      await vault.depositIntoStrategy(strategy.address, amnt);

      await mockChainlink(testStrat);

      // REBALANCE ONCE
      await movePriceBy(0.9, testStrat, deployer, strategy);
      const reciept = await rebalanceBot(strategy, chain);
      expect(reciept?.status == 1).to.be.true;

      const gasPrice = await getGasPrice(chain, 'fast', ethers.provider);
      expect(reciept?.effectiveGasPrice).to.be.eq(gasPrice);

      const offset = await strategy.getPositionOffset();
      expect(offset).to.be.closeTo('0', 1);
    });

    it('rebalanceLoan', async function () {
      const { manager } = await getNamedAccounts();

      const strategy = await ethers.getContract(testStrat.symbol, manager);

      await mockChainlink(testStrat);

      await setOraclePriceOffset(1.2, strategy, testStrat);

      const loanHealth = await strategy.loanHealth();
      const minLoanHealth = await strategy.minLoanHealth();
      expect(loanHealth).to.be.lt(minLoanHealth);

      const positionOffset = await strategy.getPositionOffset();
      expect(positionOffset).to.be.eq(0);

      const reciept = await rebalanceBot(strategy, chain);
      expect(reciept?.status == 1).to.be.true;

      const gasPrice = await getGasPrice(chain, 'fast', ethers.provider);
      expect(reciept?.effectiveGasPrice).to.be.eq(gasPrice);

      {
        const loanHealth = await strategy.loanHealth();
        const minLoanHealth = await strategy.minLoanHealth();
        expect(loanHealth).to.be.gt(minLoanHealth);

        const positionOffset = await strategy.getPositionOffset();
        expect(positionOffset).to.be.eq(0);
      }
    });
    it('should not rebalance when not necessary', async function () {
      const { manager } = await getNamedAccounts();
      const strategy = await ethers.getContract(testStrat.symbol, manager);
      const reciept = await rebalanceBot(strategy, chain);
      expect(reciept).to.be.null;
    });
  });

  describe('vaultBot', async () => {
    let vault;
    let stratData;
    let strategies;

    before(async () => {
      const { deployer } = await getNamedAccounts();
      await setMiningInterval(0);
      ({ vault } = await setupTest());
      ({ stratData, strategies } = await mockServer(chain));
    });

    it('should not rebalance empty strat', async function () {
      const { manager } = await getNamedAccounts();
      const strategy = await ethers.getContract(testStrat.symbol, manager);

      await mockChainlink(testStrat);
      const reciept = await rebalanceBot(strategy, chain);

      expect(reciept).to.be.null;
    });

    it('should deposit float', async function () {
      const amnt = parseUnits('100', 6);
      await vault.setMaxTvl(MaxUint256);
      await vault.deposit(amnt);
      expect(await vault.totalFloat()).to.be.equal(amnt);
      await harvester(ethers.provider);
      expect(await vault.totalFloat()).to.be.equal('0');
      const minTvl = strategies.find(
        (s) => s.symbol === stratData[1].symbol
      ).minTvl;
      const { balance: highBal } = await vault.getStrategyData(stratData[0].id);
      const { balance: lowBal } = await vault.getStrategyData(stratData[1].id);
      const q = await vault.getWithdrawalQueue();

      expect(highBal).to.be.closeTo(amnt.sub(minTvl), 100);
      expect(lowBal).to.be.closeTo(minTvl, 1);

      expect(q[0]).to.be.equal(getAddress(stratData[1].id));
      expect(q[1]).to.be.equal(getAddress(stratData[0].id));
    });

    it('should track trigger', async function () {
      const testStrat = strategies.filter((s) => s.chain === chain)[0];
      const amnt = parseUnits('100', 6);
      await vault.setMaxTvl(MaxUint256);
      await vault.deposit(amnt);

      const { deployer, manager } = await getNamedAccounts();
      const strategy = await ethers.getContract(testStrat.symbol, manager);
      await vault.depositIntoStrategy(strategy.address, amnt);

      await mockChainlink(testStrat);

      await movePriceBy(0.9, testStrat, deployer, strategy);
      const reciept = await rebalanceBot(strategy, chain);
      expect(reciept?.status == 1).to.be.true;
    });

    // it('should not rebalance after close to last', async function () {
    // await mockStrat(Math.round(Date.now() / 1000));
    //   const testStrat = strategies.filter((s) => s.chain === chain)[0];
    //   const amnt = parseUnits('100', 6);
    //   await vault.setMaxTvl(MaxUint256);
    //   await vault.deposit(amnt);

    //   const { deployer, manager } = await getNamedAccounts();
    //   const strategy = await ethers.getContract(testStrat.symbol, manager);
    //   await vault.depositIntoStrategy(strategy.address, amnt);

    //   await mockChainlink(testStrat);

    //   await movePriceBy(0.9, testStrat, deployer, strategy);
    //   const didRebalance = await rebalanceBot(strategy, chain);

    //   expect(didRebalance).to.be.false;

    //   const offset = await strategy.getPositionOffset();
    //   expect(offset).to.be.gt('400');
    // });
  });
});
