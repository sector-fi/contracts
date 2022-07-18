import { ethers, network } from 'hardhat';
import { setupAccount } from '../';
import { default as screamPriceOracle } from '@sc1/common/abis/scream-oracle.json';
import { buyUnderlying, getPrice, sellUnderlying } from '../uni';
import { IStrat } from '@sc1/common/strategies/types';
import { Contract } from 'ethers';

const { utils, getContractAt } = ethers;
const { parseUnits, formatUnits } = utils;

export const updateShortPrice = async (
  strat: IStrat,
  price: string
): Promise<void> => {
  if (!('mocks' in strat)) return;
  const newFeed = await getContractAt(
    'MockV3Aggregator',
    strat.mocks.chainlinkFeed
  );
  await newFeed.updateAnswer(parseUnits(price, strat.mocks.chainlinkDec));
  await newFeed.setDecimals(strat.mocks.chainlinkDec);
};

// specific to scream price oracle
export const disableBandFeed = async (strat: IStrat): Promise<void> => {
  if (!('mocks' in strat)) return;
  if (strat.lending !== 'scream') return;

  if (!strat.mocks.oracle)
    throw new Error('missing mock.oracle in strategy config');
  setupAccount(strat.mocks.oracleAdmin);
  const oracle = await getContractAt(
    screamPriceOracle,
    strat.mocks.oracle,
    strat.mocks.oracleAdmin
  );
  // await oracle._setMaxPriceDiff(parseUnits('10000000'));
  await oracle._setUnderlyingSymbols(
    [strat.cTokenBorrow, strat.cTokenLend],
    ['', '']
  );
};

export const mockChainlink = async (strat: IStrat): Promise<void> => {
  if (!('mocks' in strat)) return;

  const chainLinkMock = await ethers.getContract('MockV3Aggregator');
  const bytecode = await ethers.provider.getCode(chainLinkMock.address);

  const oldFeed = await getContractAt(
    'MockV3Aggregator',
    strat.mocks.chainlinkFeed
  );
  const price = await oldFeed.latestAnswer();

  await network.provider.send('hardhat_setCode', [
    strat.mocks.chainlinkFeed,
    bytecode,
  ]);

  const newFeed = await getContractAt(
    'MockV3Aggregator',
    strat.mocks.chainlinkFeed
  );
  await newFeed.updateAnswer(price.toString());
  await newFeed.setDecimals(strat.mocks.chainlinkDec);
};

export const movePriceBy = async (
  fraction: number,
  strat: IStrat,
  account: string,
  strategy: Contract,
  skipOracleUpdate = false
): Promise<void> => {
  const [underlyingBN] = await strategy.getUnderlyingShortReserves();
  const dec = await strategy.decimals();
  const underlying = parseFloat(formatUnits(underlyingBN, dec));
  const adjust = Math.abs(Math.ceil(underlying * (1 - Math.sqrt(fraction))));

  const adjstBN = parseUnits(adjust.toString(), dec);

  fraction < 1
    ? await buyUnderlying(
        account,
        strat.underlying,
        strat.short,
        adjstBN,
        strat.swap,
        strat.chain
      )
    : await sellUnderlying(
        account,
        strat.underlying,
        strat.short,
        adjstBN,
        strat.swap,
        strat.chain
      );

  const newShortPrice = await getPrice(strategy);

  !skipOracleUpdate &&
    (await updateShortPrice(strat, formatUnits(newShortPrice, dec)));
};

export const setOraclePriceOffset = async (
  offset: number, // basis
  strategy: Contract,
  strat: IStrat
): Promise<void> => {
  const dec = await strategy.decimals();
  const newShortPrice = await getPrice(strategy);
  await updateShortPrice(
    strat,
    formatUnits(newShortPrice.mul(offset * 10000).div(10000), dec)
  );
};
