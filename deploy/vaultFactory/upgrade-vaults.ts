import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { ethers, network } from 'hardhat'
import { schedule, executeScheduled } from '../../utils/timelock'
import { fastForwardDays, updateOwner } from '../../utils'

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { execute } = deployments
  const { deployer } = await getNamedAccounts()

  const impl = await deployments.get('VaultUpgradable')

  const factory = await ethers.getContract('ScionVaultFactory', deployer)
  const beacon = await ethers.getContract('UpgradeableBeacon', deployer)

  const currentImpl = await factory.implementation()

  if (impl.address === currentImpl) {
    console.log('Reusing Vault Implementation')
    return
  }

  console.log('upgrade vault')

  // might need to update ownership of vault factory if we are on local
  if (!network.live) {
    await updateOwner(factory, deployer)
    try {
      const timelock = await ethers.getContract('ScionTimelock', deployer)
      await updateOwner(beacon, timelock.address)
    } catch (err) {}
  }

  const upgradeableBeacon = await ethers.getContract('UpgradeableBeacon')

  console.log('scheduling upgradeTo')
  const tx = await schedule(
    execute,
    { from: deployer, log: true },
    upgradeableBeacon,
    'upgradeTo',
    [impl.address],
  )
  if (!network.live) {
    console.log('fast forwarding...')
    await fastForwardDays(3)
    console.log('executing scheduled upgradeTo')
    await executeScheduled(execute, { from: deployer, log: true }, tx)
  }
}

export default func
func.tags = ['UpgradeVaults']
func.dependencies = ['Setup', 'ScionVaultFactory', 'VaultImplementation']
