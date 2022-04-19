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
import { IChain } from '@sc1/common';
import { getHarvestParams, strategies, IStrat } from '@sc1/common/strategies';

Error.stackTraceLimit = Infinity;

const { getSigner, utils } = ethers;
const { parseUnits, formatUnits } = utils;

const { FORK_CHAIN = '' } = process.env;

const DEPOSIT_AMT = '100';

const forkBlock = {
  avalanche: 11348089,
  fantom: 28960075,
  moonriver: 1522451,
};

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['InitVault', 'Strategies']);
  await setMiningInterval(0);
  const { deployer } = await getNamedAccounts();
  const vault = await getVault();
  await setupAccount(deployer);
  await fundAccount(deployer, '1000000000');
  return { vault };
});

const initStrat = async (strat: IStrat, vault) => {
  const { deployer } = await getNamedAccounts();

  await approve(strat.underlying, deployer, vault.address);

  const router = getUniAddr('UNISWAP_ROUTER', strat.swap);
  await approve(strat.underlying, deployer, router);

  const strategy = await ethers.getContract(strat.symbol, deployer);
  const dec = await strategy.decimals();
  return { strategy, dec };
};

// runs tests for all strategies
strategies
  .filter((s) => s.chain === FORK_CHAIN)
  .slice(0, 1)
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
        await forkNetwork(FORK_CHAIN as IChain, forkBlock[FORK_CHAIN]);
        const { deployer, manager } = await getNamedAccounts();
        owner = deployer;
        managerSig = await getSigner(manager);

        ({ vault } = await setupTest());
        ({ strategy, dec } = await initStrat(strat, vault));
      });

      it('should test permissions', async function () {
        console.log(strategy.functions);
      });
    });
  });
