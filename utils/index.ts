import { getNamedAccounts, ethers } from 'hardhat';
import { Contract } from 'ethers';

export * from './hedgeHelpers';
export * from './uni';
export * from './network';
export * from './mocks';
export * from './timelock';

export const waitFor = (delay: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delay));

export const getVault = async (account?: string): Promise<Contract> => {
  const { deployer } = await getNamedAccounts();
  return ethers.getContract('USDC-Vault-0.1', account || deployer);
};
