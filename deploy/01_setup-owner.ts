import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { updateOwner } from '../utils';
import { ethers } from 'hardhat';
import { strategies } from '@sc1/common';

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
}: HardhatRuntimeEnvironment) {
  if (network.live) return;

  const { deployer, manager } = await getNamedAccounts();

  const vaultFactory = await ethers.getContract('ScionVaultFactory', deployer);
  await updateOwner(vaultFactory, deployer);

  // set owner of contracts to curren DEPLOYER addrs
  const vault = await ethers.getContract('USDC-Vault-0.1', deployer);
  await updateOwner(vault, deployer);
  const isManager = await vault.isManager(manager);

  // TODO this won't work - need to go through timelock
  // if (!isManager) await vault.setManager(manager, true);

  for (let i = 0; i < strategies.length; i++) {
    const strat = strategies[i];
    if (!network.tags[strat.chain]) continue;
    const strategy = await ethers.getContract(strat.symbol, deployer);
    await updateOwner(strategy, deployer);
    const isManager = await strategy.isManager(manager);
    // TODO this won't work - need to go through timelock
    // if (!isManager) await strategy.setManager(manager, true);
  }
};

export default func;
func.tags = ['DevOwner'];
func.dependencies = ['Strategies'];
