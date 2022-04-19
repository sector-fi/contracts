import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

// only deploy this once
const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const beacon = await deployments.get('UpgradeableBeacon');
  console.log('deploy factory');
  await deploy('ScionVaultFactory', {
    from: deployer,
    args: [beacon.address],
    log: true,
    skipIfAlreadyDeployed: true,
  });

  // return true;
};

export default func;
func.id = 'ScionVaultFactory';
func.tags = ['ScionVaultFactory'];
func.dependencies = ['VaultImplementation'];
