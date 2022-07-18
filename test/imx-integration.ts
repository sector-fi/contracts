import { expect } from 'chai';
import { ethers, getNamedAccounts, deployments, network } from 'hardhat';
import {
  forkNetwork,
  approve,
  fundAccount,
  mockChainlink,
  getTvl,
  getExpectedAmounts,
  setupAccount,
  setMiningInterval,
  movePriceBy,
  disableBandFeed,
  deadline,
  getVault,
} from '../utils';
import { getUniAddr } from '@sc1/common/utils/address';
import { getErc20, IChain, getAddr } from '@sc1/common';
import { getHarvestParams, strategies, IStrat } from '@sc1/common/strategies';

const { getSigner, utils } = ethers;
const { parseUnits, formatUnits } = utils;

const { FORK_CHAIN = '' } = process.env;
const chain = FORK_CHAIN as IChain;

const DEPOSIT_AMT = '100';

const forkBlock = {
  avalanche: 11348089,
  fantom: 35491571,
  moonriver: 1522451,
};

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['InitVault', 'Strategies']);
  await setMiningInterval(0);
  const { deployer, manager } = await getNamedAccounts();
  const vault = await getVault();
  vault.bulkAllow([deployer, manager]);
  await setupAccount(deployer);
  await fundAccount(deployer, '1000000000');
  return { vault };
});

const initStrat = async (strat: IStrat, vault) => {
  const { deployer } = await getNamedAccounts();

  await approve(strat.underlying, deployer, vault.address);

  const router = getUniAddr('UNISWAP_ROUTER', strat.swap);
  await approve(strat.underlying, deployer, router);

  await mockChainlink(strat);
  const strategy = await ethers.getContract(strat.symbol, deployer);
  await disableBandFeed(strat); // additional oracle for fantom
  const dec = await strategy.decimals();
  return { strategy, dec };
};

// runs tests for all strategies
strategies
  .filter((s) => s.chain === chain && !s.skip)
  // .slice(0, 1)
  // .filter((s) => s.symbol === 'USDCavaxPNGqi')
  .forEach((strat) => {
    describe.skip(strat.symbol, function () {
      this.timeout(120000); // fantom is slow

      let owner;
      let managerSig;
      let vault;
      let strategy;
      let dec;

      before(async () => {
        await forkNetwork(chain as IChain, forkBlock[chain]);
        const { deployer, manager } = await getNamedAccounts();
        owner = deployer;
        managerSig = await getSigner(manager);
      });

      describe('flow', async () => {
        before(async () => {
          ({ vault } = await setupTest());
          ({ strategy, dec } = await initStrat(strat, vault));
        });

        it('should init', async function () {
          expect(await vault.UNDERLYING()).to.be;
        });

        it('should deposit', async function () {
          const amountUsd = parseUnits(DEPOSIT_AMT, dec);
          const usdc = await getErc20(
            getAddr('USDC', chain),
            await getSigner(owner)
          );
          const usdcB = await usdc.balanceOf(owner);
          console.log('balance', usdc.address, owner, usdcB.toString());

          await vault.deposit(amountUsd);
          await vault
            .connect(managerSig)
            .depositIntoStrategy(strategy.address, amountUsd);

          const { tvl: depCollateral } = await getTvl(strategy);
          expect(depCollateral).to.be.gte(amountUsd.mul(99).div(100));

          const { shortPosition, lpBalance } = await getTvl(strategy);

          // expect(lpBalance).to.be.closeTo(amountUsd.mul(2), 10);

          const liq = await strategy.getIMXLiquidity();
          // expect(shortPosition).to.be.closeTo(amountUsd, 10);
        });

        // it('should not rebalance', async function () {
        //   await expect(strategy.connect(managerSig).rebalance()).to.be.reverted;
        // });

        it('should withdraw', async function () {
          const { deployer } = await getNamedAccounts();
          const balance = await vault.balanceOf(deployer);
          await vault.withdraw(balance.div('2'));
          const { shortPosition, lpBalance } = await getTvl(strategy);

          const liq = await strategy.getIMXLiquidity();
        });

        // it('should re-deposit', async function () {
        //   const amount = parseUnits(DEPOSIT_AMT, dec);
        //   await vault.deposit(amount);
        //   await vault
        //     .connect(managerSig)
        //     .depositIntoStrategy(strategy.address, amount);
        // });

        // it('should harvest', async function () {
        //   await network.provider.send('evm_increaseTime', [90 * 24 * 60 * 60]);
        //   await network.provider.send('evm_mine');
        //   const { tvl: startTvl } = await getTvl(strategy);

        //   const harvestArgs = await getHarvestParams(
        //     strategy,
        //     strat,
        //     managerSig,
        //     deadline(),
        //     true
        //   );
        //   console.log('harvest args', harvestArgs);
        //   const tx = await strategy.connect(managerSig).harvest(...harvestArgs);
        //   const res = await tx.wait();

        //   const harvestLog = res.events.find((e) => e.event === 'Harvest');
        //   const harvestToken = res.events.filter(
        //     (e) => e.event === 'HarvestedToken'
        //   );

        //   console.log(
        //     'HarvestedToken',
        //     harvestToken.map((h) => h.args.map((b) => b.toString()))
        //   );

        //   const { tvl } = await getTvl(strategy);

        //   console.log(
        //     'harvested',
        //     formatUnits(tvl.sub(harvestLog.args.harvested), dec)
        //   );
        //   await vault.connect(managerSig).harvest([strategy.address]);
        //   expect(tvl).to.be.gt(startTvl);
        // });

        // it('should adjust price down', async function () {
        //   await movePriceBy(0.9, strat, owner, strategy);
        // });

        // it('should withdraw when not in balance', async function () {
        //   // await getTvl(hlp);
        //   const balance = await vault.balanceOf(owner);
        //   console.log('balance', formatUnits(balance, 6));
        //   await vault.withdraw(parseUnits('1', 6));
        //   await getTvl(strategy);
        // });

        // it('should rebalance up', async function () {
        //   await movePriceBy(0.9, strat, owner, strategy);
        //   await strategy.connect(managerSig).rebalance();
        //   await getTvl(strategy);
        // });

        // it('should rebalance down', async function () {
        //   await movePriceBy(1.23, strat, owner, strategy);
        //   // await getTvl(hlp);
        //   await strategy.connect(managerSig).rebalance();
        //   await getTvl(strategy);
        // });

        // it('should close position', async function () {
        //   // edge case is when there has been a slight loss and no harvest
        //   await vault.connect(managerSig).harvest([strategy.address]);
        //   const balance = await vault.balanceOf(owner);
        //   console.log('balance', formatUnits(balance, 6));
        //   await vault.redeem(balance);
        //   await getTvl(strategy);
        // });
      });
    });
  });
