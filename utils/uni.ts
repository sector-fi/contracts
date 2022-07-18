import { ethers } from 'hardhat';

import {
  getAddr,
  ISwap,
  IChain,
  getRouterContract,
  routerMethod,
} from '@sc1/common/utils';
import { BigNumber, Contract } from 'ethers';

import { deadline } from './hedgeHelpers';
import { Address } from 'hardhat-deploy/dist/types';
import { buyUnderlying as buyUnderlyingSolidly } from './solidly';

const { utils } = ethers;
const { parseUnits } = utils;

export const getPrice = async (strategy: Contract): Promise<BigNumber> => {
  const [uR, sR] = await strategy.getUnderlyingShortReserves();
  return uR.mul(parseUnits('1')).div(sR);
};

export const buyUnderlying = async (
  to: string,
  underlying: Address,
  exchangeFor: Address,
  amnt: BigNumber,
  swap: ISwap,
  chain: IChain
): Promise<void> => {
  if (swap === 'solidly')
    return buyUnderlyingSolidly(to, underlying, exchangeFor, amnt, swap, chain);
  const signer = await ethers.getSigner(to);
  const uniRouter = getRouterContract(swap, signer);
  const base = getAddr('BASE', chain);
  // TODO can wrap ETH and only use here ERC20
  const method =
    base.toLowerCase() === exchangeFor.toLowerCase()
      ? 'swapETHForExactTokens'
      : 'swapTokensForExactTokens';
  const ethBalance = await signer.provider?.getBalance(to);

  const tx = await uniRouter[routerMethod(method, swap)](
    amnt,
    [exchangeFor, underlying],
    to,
    deadline(),
    // offer max avail bal minus gas
    { value: ethBalance?.sub(parseUnits('10')) }
  );
  await tx.wait();
};

export const sellUnderlying = async (
  to: string,
  underlying: Address,
  exchangeFor: Address,
  amnt: BigNumber,
  swap: ISwap,
  chain: IChain
): Promise<void> => {
  const signer = await ethers.getSigner(to);
  const uniRouter = getRouterContract(swap, signer);
  const base = getAddr('BASE', chain);
  // TODO can wrap ETH and only use here ERC20
  const method =
    base.toLowerCase() === exchangeFor.toLowerCase()
      ? 'swapExactTokensForETH'
      : 'swapExactTokens';
  const tx = await uniRouter[routerMethod(method, swap)](
    amnt,
    0,
    [underlying, exchangeFor],
    to,
    deadline()
  );
  await tx.wait();
};
