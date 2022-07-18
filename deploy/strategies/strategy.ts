import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { strategies, IStrat, getHarvestParams, getAddr } from '@sc1/common';
import { buyUnderlying, fastForwardDays, updateOwner } from '../../utils';
import { schedule, executeScheduled } from '../../utils/timelock';
import { network, ethers, getNamedAccounts } from 'hardhat';
import { Contract } from 'ethers';

const { getSigner } = ethers;
const { parseUnits } = ethers.utils;

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deploy, execute } = deployments;
  const { deployer, manager } = await getNamedAccounts();

  const utils = await deployments.get('UniUtils');
  const vault = await ethers.getContract('USDC-Vault-0.2', manager);

  // deploy or upgrade all strategies
  for (let i = 0; i < strategies.length; i++) {
    const stratConf = strategies[i];
    if (stratConf.skip) continue;
    if (!network.tags[stratConf.chain]) continue;

    // WARNING this flow is fragile
    let prevDeployment;
    try {
      prevDeployment = await deployments.get(stratConf.symbol);
    } catch (err) {
      prevDeployment = null;
      console.log('new deployment of', stratConf.symbol);
    }

    const res = await deploy(stratConf.symbol, {
      from: deployer,
      args: [stratConf.args(vault.address)],
      libraries: { UniUtils: utils.address },
      skipIfAlreadyDeployed:
        process.env.NODE_ENV !== 'test' && !stratConf.shouldUpdate,
      log: true,
    });

    const strategy = await ethers.getContract(stratConf.symbol, deployer);
    await initStrategy(execute, vault, strategy, stratConf);

    if (!prevDeployment) {
      // no need to migrate anything, just add strat to vault
      await addNewStratToVault(execute, vault, strategy);
      continue;
    }

    if (prevDeployment.address !== res.address)
      await deployments.save(`${stratConf.symbol}-prev`, prevDeployment);

    try {
      prevDeployment = await ethers.getContract(
        `${stratConf.symbol}-prev`,
        manager
      );
    } catch (err) {
      // no prev deployment - nothing to do
      continue;
    }

    const prevVault = await prevDeployment.vault();

    if (prevVault !== vault.address) {
      console.log('previous deployment doesnt match current vault');
      continue;
    }

    const { trusted } = await vault.getStrategyData(strategy.address);

    const { trusted: prevTrusted } = await vault.getStrategyData(
      prevDeployment.address
    );

    // check if we need to run our migration tx
    if (!trusted || prevTrusted) {
      console.log(
        stratConf.symbol,
        'migrating',
        prevDeployment.address,
        'to',
        strategy.address
      );
      // only deploy strategies that match the network tag
      await migrateStrategy(execute, vault, strategy, prevDeployment);
    }
  }
};

export default func;
func.tags = ['Strategies'];
func.dependencies = [
  'Setup',
  'UniUtils',
  'USDC-Vault-0',
  'UpgradeVaults',
  'Timelock',
];

// utils
async function migrateStrategy(
  execute: any,
  vault: Contract,
  strategy: Contract,
  prevDeployment: Contract
) {
  const { deployer } = await getNamedAccounts();
  if (!network.live) {
    await updateOwner(prevDeployment, deployer);
    await updateOwner(vault, deployer);
  }
  // using ethers + manual gasLimit because moonriver fails at gasEstimate
  // await harvestPrev(vault, prevDeployment, strat);

  const queue = await vault.getWithdrawalQueue();
  const index = queue.findIndex((s) => s === prevDeployment.address);

  if (prevDeployment.address !== strategy.address) {
    console.log('migrateStrategy');
    const tx = await schedule(
      execute,
      { from: deployer, log: true },
      vault,
      'migrateStrategy',
      [
        prevDeployment.address,
        strategy.address,
        index > -1 ? index : queue.length,
      ]
    );

    if (!network.live) {
      await fastForwardDays(3);
      await executeScheduled(execute, { from: deployer, log: true }, tx);
    }
  }
}

async function initStrategy(
  execute: any,
  vault: Contract,
  strategy: Contract,
  strat: IStrat
) {
  const { deployer, manager, team1 } = await getNamedAccounts();

  // pre-fill wallets
  if (!network.live) {
    await buyUnderlying(
      deployer,
      strat.underlying,
      getAddr('BASE', strat.chain),
      parseUnits('200', 6),
      strat.swap,
      strat.chain
    );
    await buyUnderlying(
      manager,
      strat.underlying,
      getAddr('BASE', strat.chain),
      parseUnits('200', 6),
      strat.swap,
      strat.chain
    );
  }

  const stratOwner = await strategy.owner();
  if (deployer !== stratOwner) {
    console.log('Deployer is not the owner of', strat.symbol);
    return;
  }

  if (!(await strategy.isManager(manager)))
    await execute(
      strat.symbol,
      { from: deployer, log: true },
      'setManager',
      manager,
      true
    );

  const isTeamManager = await strategy.isManager(team1);

  if (!isTeamManager)
    await execute(
      strat.symbol,
      { from: deployer, log: true },
      'setManager',
      team1,
      true
    );

  // should be set already
  if ((await strategy.vault()) !== vault.address)
    await execute(
      strat.name,
      { from: deployer, log: true },
      'setVault',
      vault.address
    );
}

async function addNewStratToVault(
  execute: any,
  vault: Contract,
  strategy: Contract
) {
  console.log('Add new strat to vault');
  const { deployer, manager } = await getNamedAccounts();

  // TODO replace with addStrategy once we are updated
  const { trusted } = await vault.getStrategyData(strategy.address);
  if (!trusted) {
    const tx = await schedule(
      execute,
      { from: deployer, log: true },
      vault,
      'trustStrategy',
      [strategy.address]
    );
    if (!network.live) {
      await fastForwardDays(3);
      await executeScheduled(execute, { from: deployer, log: true }, tx);
    }
  }

  const queue = await vault.getWithdrawalQueue();
  if (!queue.find((s) => s === strategy.address)) {
    console.log('pushToWithdrawalQueue', strategy.address);
    await execute(
      'USDC-Vault-0.2',
      { from: manager, log: true },
      'pushToWithdrawalQueue',
      strategy.address
    );
  }
}

async function harvestPrev(
  vault: Contract,
  prevDeployment: Contract,
  strat: IStrat
) {
  const { manager } = await getNamedAccounts();

  // harvest prev deployment strat
  const harvestArgs = await getHarvestParams(
    prevDeployment,
    strat,
    await getSigner(manager),
    undefined,
    true
  );

  {
    console.log('harvest prev deployment');
    const tx = await prevDeployment.harvest(...harvestArgs, {
      gasLimit: 3000000,
    });
    const res = await tx.wait();
    if (res.status !== 1) {
      console.log(res);
      throw new Error('failed tx');
    }
  }

  {
    console.log('harvest vault');
    const tx = await vault.harvest([prevDeployment.address], {
      gasLimit: 3000000,
    });
    const res = await tx.wait();
    if (res.status !== 1) {
      console.log(res);
      throw new Error('failed tx');
    }
  }
}
