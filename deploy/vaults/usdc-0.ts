import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';
import { getAddr } from '@sc1/common/utils/address';
import { IChain } from '@sc1/common/utils';

const { parseUnits } = ethers.utils;

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { execute } = deployments;
  const { deployer, manager } = await getNamedAccounts();

  const chain = network.live ? network.name : network.config.tags[0];

  console.log('chain', chain);
  const USDC = getAddr('USDC', chain as IChain);

  const initParams = [
    USDC, // underlying
    deployer, // owner,
    manager,
    parseUnits('0.1'), // performance fee 10% * 1e18
    6 * 60 * 60, // harvest delay sec
    3 * 60 * 60, // harvest window sec
  ];

  const vaultFact = await ethers.getContract('ScionVaultFactory', deployer);
  const vaultAddr = await vaultFact.getVaultFromUnderlying(USDC, 0);
  const isDeployed = await vaultFact.isVaultDeployed(vaultAddr);

  if (isDeployed) {
    console.log('USDC-Vault-0 is already deployed');
    const vault = await deployments.getArtifact('VaultUpgradable');
    await deployments.save('USDC-Vault-0.1', {
      abi: vault.abi,
      address: vaultAddr,
    });
    return;
  }

  const ABI = [
    'function initialize(address _UNDERLYING,address owner, address manager, uint256 _feePercent,  uint64 _harvestDelay, uint128 _harvestWindow)',
  ];
  const iface = new ethers.utils.Interface(ABI);
  const initData = iface.encodeFunctionData('initialize', initParams);

  await execute(
    'ScionVaultFactory',
    { from: deployer, log: true },
    'deployVault',
    USDC,
    0, // usdc vault id
    initData
  );

  const vaultData = await deployments.getArtifact('VaultUpgradable');

  await deployments.save('USDC-Vault-0.1', {
    abi: vaultData.abi,
    address: vaultAddr,
  });

  await execute(
    'USDC-Vault-0.1',
    { from: deployer, log: true },
    'setManager',
    deployer,
    true
  );
};

export default func;
func.tags = ['USDC-Vault-0'];
func.dependencies = ['ScionVaultFactory', 'UpgradeVaults'];
