import { ethers, getNamedAccounts, deployments } from 'hardhat';
import { strategies } from '@sc1/common';
import { schedule, getErc20 } from '../utils';

const { MaxUint256 } = ethers.constants;

async function main() {
  const { deployer, manager } = await getNamedAccounts();
  const { execute } = deployments;
  const signer = await ethers.getSigner(manager);

  const vault = await ethers.getContract('USDC-Vault-0.1', signer);
  const addr = '0xa4dece0f776459d2201aa49c5e3558e02610cb63';

  const strategy = await ethers.getContract('USDCftmSPIRITscream', manager);
  const strategy1 = await ethers.getContract('USDCftmSPOOKYscream', manager);

  const timelock = await ethers.getContract('ScionTimelock', deployer);

  // // console.log(timelock.address);
  // const cToken = await getErc20(
  //   '0xE45Ac34E528907d0A0239ab5Db507688070B20bf',
  //   deployer
  // );
  // const amount = await cToken.balanceOf(timelock.address);

  {
    const tx = await strategy.closePosition('100');
    const res = await tx.wait();
    console.log(res);
  }
  {
    const tx = await strategy1.closePosition('100');
    const res = await tx.wait();
    console.log(res);

    // const q = await vault.getWithdrawalQueue();
    // console.log(q);
    // const tx = await strategy.transferOwnership(timelock.address);
    // await schedule(execute, { from: deployer, log: true }, cToken, 'transfer', [
    //   manager,
    //   amount,
    // ]);
    // const tx = await vault.setPublic(true);
    // const res = await tx.wait();
    // console.log(res);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
