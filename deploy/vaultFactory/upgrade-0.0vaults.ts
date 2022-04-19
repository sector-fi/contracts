import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { ethers, network } from 'hardhat'
import { updateOwner } from '../../utils'

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { execute, deploy } = deployments
  const { deployer } = await getNamedAccounts()

  return

  const impl = await deploy('VaultUpgradable', {
    from: deployer,
    log: true,
  })

  const factory = await ethers.getContract('ScionVaultFactoryV0', deployer)
  const currentImpl = await factory.implementation()

  if (impl.address === currentImpl) {
    console.log('Reusing Vault Implementation')
    return
  }

  console.log('upgrade vault')

  // might need to update ownership of vault factory if we are on local
  if (!network.live) await updateOwner(factory, deployer)

  await execute(
    'ScionVaultFactoryV0',
    { from: deployer, log: true },
    'upgradeTo',
    impl.address,
  )
}

export default func
func.tags = ['UpgradeVaults-0.0']
// func.dependencies = ['Setup', 'ScionVaultFactory', 'VaultImplementation'];
