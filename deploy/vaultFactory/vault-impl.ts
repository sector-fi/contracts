import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const implementation = await deploy('VaultUpgradable', {
    from: deployer,
    log: true,
  });

  await deploy('UpgradeableBeacon', {
    from: deployer,
    log: true,
    args: [implementation.address],
    skipIfAlreadyDeployed: true,
  });
};

export default func;
func.tags = ['VaultImplementation'];
func.dependencies = ['Setup'];
