import { ethers, network } from 'hardhat';

// direct import from lib, so need to make sure common is built (careful about circular deps)
import { BigNumber, Contract, constants } from 'ethers';
import 'dotenv/config';

const { utils, getContractAt, getSigner } = ethers;
const { parseUnits, formatUnits, splitSignature } = utils;

export const HUNDRED_PERCENT = BigNumber.from(10000);

export const deadline = (): number =>
  Math.round(Date.now() / 1000 + 60 * 60 * 24 * 356);

export const getErc20 = async (
  addr: string,
  _signer: string
): Promise<Contract> => {
  const signer = await ethers.getSigner(_signer);
  return await getContractAt('ERC20', addr, signer);
};

export const getWrapped = async (
  addr: string,
  _signer: string
): Promise<Contract> => {
  const signer = await ethers.getSigner(_signer);
  return await getContractAt('IWETH', addr, signer);
};

export const approve = async (
  address: string,
  _signer: string,
  spender: string
): Promise<void> => {
  const erc20 = await getErc20(address, _signer);
  await erc20.approve(spender, constants.MaxUint256);
};

export const getMinAmount = (amount: BigNumber, percent: number): BigNumber => {
  return amount
    .mul(HUNDRED_PERCENT.sub(BigNumber.from(percent * 100)))
    .div(HUNDRED_PERCENT);
};

export const getExpectedAmounts = async (
  totalUsd: BigNumber,
  collateralRatio: BigNumber,
  strategy: Contract
): Promise<[BigNumber, BigNumber]> => {
  const [uR, sR] = await strategy.getUnderlyingShortReserves();
  const shortPerUnderlying = uR.mul(parseUnits('1')).div(sR);
  const amntUnderlying = totalUsd
    .mul(collateralRatio)
    .div(HUNDRED_PERCENT.add(collateralRatio));
  const amntShort = amntUnderlying
    .mul(shortPerUnderlying)
    .div(parseUnits('1', '6'));
  return [amntUnderlying, amntShort];
};

export const getTvl = async (hlp: any) => {
  const [tvl, collateralBalance, shortPosition, borrowBalance, lpBalance] =
    await hlp.getTVL();
  console.log(
    'tvl',
    formatUnits(tvl, 6),
    'collateralBalance',
    formatUnits(collateralBalance, 6),
    'shortPostion',
    formatUnits(shortPosition, 18),
    'shortBalance',
    formatUnits(borrowBalance, 6),
    'lpBalance',
    formatUnits(lpBalance, 6)
  );
  return {
    tvl,
    collateralBalance,
    shortPosition,
    borrowBalance,
    lpBalance,
  };
};

// a lot of tokens won't have permit
const depositWPermit = async (owner, token, amount, router, vault) => {
  const deployerSig = await getSigner(owner);
  const tokenContract = await getErc20(token, owner);
  const nonce = await tokenContract.nonces(owner);
  console.log('nonce', nonce);
  const deadline = Math.round(Date.now() / 1000) + 100 * 24 * 60 * 60;
  const data = getTypedPermitMsg(
    owner,
    token,
    amount.toString(),
    nonce.add('1').toString(),
    deadline.toString(),
    router.address,
    await vault.name(),
    network.config.chainId || 1
  );
  const sigHex = await deployerSig._signTypedData(
    data.domain,
    data.types,
    data.message
  );
  const split = splitSignature(sigHex);
  await router.depositIntoVaultWithPermit(
    vault.address,
    amount,
    deadline,
    split.v,
    split.r,
    split.s
  );
};

const getTypedPermitMsg = (
  owner: string,
  spender: string,
  value: string,
  nonce: string, // make sure its +1 (pending nonce)
  deadline: string,
  verifyingContract: string,
  contarctName: string,
  chainId: number
) => {
  return {
    types: {
      Permit: [
        { name: 'owner', type: 'address' },
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    },
    domain: {
      name: contarctName,
      version: '1',
      chainId,
      verifyingContract,
    },
    message: {
      owner,
      spender,
      value,
      nonce,
      deadline,
    },
  };
};
