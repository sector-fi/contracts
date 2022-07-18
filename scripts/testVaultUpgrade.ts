import { ethers, getNamedAccounts } from 'hardhat';
import { setupAccount } from '../utils';

async function main() {
  const { deployer } = await getNamedAccounts();
  await setupAccount(deployer);

  const imp = await ethers.getContract('USDCVaultUpgradable', deployer);
  const vault = await ethers.getContractAt(
    'VaultUpgradable',
    imp.address,
    deployer
  );

  const underlying = await vault.UNDERLYING();

  const test = await vault.test();

  console.log(underlying, test);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
