import { ethers, network } from 'hardhat';

import {
  getAddr,
  ISwap,
  IChain,
  getRouterContract,
  routerMethod,
  getUniAddr,
} from '@sc1/common/utils';
import { BigNumber, Contract } from 'ethers';

import { deadline } from './hedgeHelpers';
import { Address } from 'hardhat-deploy/dist/types';

const { utils } = ethers;
const { parseUnits } = utils;

export const getPrice = async (strategy: Contract): Promise<BigNumber> => {
  const [uR, sR] = await strategy.getUnderlyingShortReserves();
  return uR.mul(parseUnits('1')).div(sR);
};

export const buyUnderlying = async (
  to: string,
  tokenOut: Address,
  tokenIn: Address,
  amnt: BigNumber,
  swap: ISwap,
  chain: IChain
): Promise<void> => {
  const signer = await ethers.getSigner(to);
  const uniRouter = getRouterContract(swap, signer);
  const base = getAddr('BASE', chain);

  // TODO can wrap ETH and only use here ERC20
  const method =
    base.toLowerCase() === tokenIn.toLowerCase()
      ? 'swapExactETHForTokens'
      : 'swapExactTokensForTokens';

  const amountIn = getAmountIn(amnt, tokenIn, tokenOut);

  const route =
    swap === 'solidly' ? [[tokenIn, tokenOut, false]] : [tokenIn, tokenOut];

  const tx = await uniRouter[routerMethod(method, swap)](
    amnt,
    route,
    to,
    deadline(),
    // offer max avail bal minus gas
    { value: amountIn }
  );
  const res = await tx.wait();
};

export const sellUnderlying = async (
  to: string,
  tokenIn: Address,
  tokenOut: Address,
  amnt: BigNumber,
  swap: ISwap,
  chain: IChain
): Promise<void> => {
  const signer = await ethers.getSigner(to);
  const uniRouter = getRouterContract(swap, signer);
  const base = getAddr('BASE', chain);
  // TODO can wrap ETH and only use here ERC20
  const method =
    base.toLowerCase() === tokenOut.toLowerCase()
      ? 'swapExactTokensForETH'
      : 'swapExactTokens';

  await uniRouter[routerMethod(method, swap)](
    amnt,
    0,
    [tokenIn, tokenOut],
    to,
    deadline()
  );
};

export const addLP = async (
  token0: string,
  tokenIn: string,
  amountA: BigNumber,
  amountB: BigNumber,
  address: string,
  swap: ISwap
): Promise<void> => {
  const signer = await ethers.getSigner(address);
  const uniRouter = getRouterContract(swap, signer);
  await uniRouter.addLiquidity(
    token0,
    tokenIn,
    amountA,
    amountB,
    amountA,
    0,
    address,
    deadline()
  );
};

export const getAmountIn = async (
  amountOut: BigNumber,
  tokenIn: string,
  tokenOut: string
): Promise<BigNumber> => {
  const factory = await ethers.getContractAt(
    [
      {
        inputs: [
          { internalType: 'address', name: '', type: 'address' },
          { internalType: 'address', name: '', type: 'address' },
          { internalType: 'bool', name: '', type: 'bool' },
        ],
        name: 'getPair',
        outputs: [{ internalType: 'address', name: '', type: 'address' }],
        stateMutability: 'view',
        type: 'function',
      },
    ],
    getUniAddr('UNISWAP_FACTORY', 'solidly')
  );
  const flip = tokenIn < tokenOut;
  [tokenIn, tokenOut] = flip ? [tokenIn, tokenOut] : [tokenOut, tokenIn];

  // defaults to non-stable
  const stablePool = false;
  const pairAddr = await factory.getPair(tokenIn, tokenOut, stablePool);
  const pair = await ethers.getContractAt('IUniswapV2Pair', pairAddr);
  let [reserveIn, reserveOut] = await pair.getReserves();
  [reserveIn, reserveOut] = flip
    ? [reserveIn, reserveOut]
    : [reserveOut, reserveIn];

  const numerator = reserveIn.mul(amountOut).mul(10000);
  const denominator = reserveOut.sub(amountOut).mul(9999);
  const amountIn = numerator.div(denominator).add(1);
  return amountIn;
};
