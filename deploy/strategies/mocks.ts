import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { strategies } from '@sc1/common';
import { utils } from 'ethers';

const { parseUnits } = utils;

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  network,
}: HardhatRuntimeEnvironment) {
  if (network.name != 'hardhat') return;

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  for (let i = 0; i < strategies.length; i++) {
    const strat = strategies[i];
    if (!('mocks' in strat)) return;
    const mocks = strat.mocks;
    await deploy('MockV3Aggregator', {
      from: deployer,
      log: true,
      args: [mocks.chainlinkDec, parseUnits('0', mocks.chainlinkDec)],
    });
  }
};

export default func;
func.tags = ['Mocks'];
func.dependencies = ['Setup'];
