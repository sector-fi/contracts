import { expect } from 'chai';
import { ethers, getNamedAccounts, network, deployments } from 'hardhat';
import {
  forkNetwork,
  setupAccount,
  setMiningInterval,
  copyDeployments,
  getTvl,
} from '../../utils';
import { IChain } from '@sc1/common/utils';

const { utils } = ethers;

Error.stackTraceLimit = Infinity;

const { FORK_CHAIN = '' } = process.env;

const forkBlock = {
  avalanche: 11347155,
  fantom: 31449850,
  moonriver: 1665475,
};

describe('Strat Debug', function () {
  this.timeout(220000); // fantom is slow

  before(async () => {
    await forkNetwork(FORK_CHAIN as IChain, forkBlock[FORK_CHAIN]);
    await copyDeployments(FORK_CHAIN as IChain);
    await setMiningInterval(0);
    const { deployer, manager } = await getNamedAccounts();
    await setupAccount(deployer);
    await setupAccount(manager);
  });

  it('debug', async function () {
    const { deployer, manager } = await getNamedAccounts();

    const strategy = await ethers.getContract('USDCmovrSOLARwell', deployer);
    // const strategy = await ethers.getContract('USDCmovrSOLARwell', deployer);

    const offset = await strategy.getPositionOffset();
    const loanHealth = await strategy.loanHealth();

    console.log('offset', offset.toNumber(), utils.formatUnits(loanHealth));
    await getTvl(strategy);
    // await strategy.connect(await ethers.getSigner(manager)).rebalance();
  });
});
