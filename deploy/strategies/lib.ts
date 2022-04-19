import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deployer } = await getNamedAccounts();

  const { deploy } = deployments;

  await deploy('UniUtils', {
    from: deployer,
    log: true,
    // skipIfAlreadyDeployed: true,
  });
};

export default func;
func.tags = ['UniUtils'];
