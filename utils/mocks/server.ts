import { IChain } from '@sc1/common';
import { createMockClient } from 'mock-apollo-client';
import { createClient } from 'redis-mock';
import { ImportMock } from 'ts-mock-imports';
import * as apollo from '@sc1/server/apolloClient';
import * as redis from '@sc1/server/redis';
import * as keeperCore from '@sc1/server/keeper/core';
import * as vaults from '@sc1/common/vaults';
import { strategies } from '@sc1/common/strategies';
import { stratSortedMock, stratMock } from '@sc1/common/gql/queries';
import { ethers, deployments, getNamedAccounts } from 'hardhat';
import util from 'util';
import * as gas from '@sc1/server/keeper/gas';

process.env.NODE_ENV = 'test';

const { MaxUint256 } = ethers.constants;

const mockApolloClient = createMockClient();
ImportMock.mockOther(apollo, 'apolloClient', mockApolloClient);

const mockRedisClient = createClient();
ImportMock.mockOther(redis, 'client', mockRedisClient);

ImportMock.mockOther(keeperCore, 'getWallet', async () => {
  const { manager } = await getNamedAccounts();
  return await ethers.getSigner(manager);
});

ImportMock.mockOther(
  gas,
  'getGasPrice',
  async (chain: IChain, speed: gas.TGasSpeed) => {
    switch (speed) {
      case 'fast':
        return 999e9;
      case 'normal':
        return 333e9;
      case 'slow':
        return 111e9;
    }
  }
);

redis.client.HGET = util.promisify(redis.client.HGET).bind(redis.client);
redis.client.SMEMBERS = util
  .promisify(redis.client.SMEMBERS)
  .bind(redis.client);
redis.client.HGETALL = util.promisify(redis.client.HGETALL).bind(redis.client);
redis.client.SADD = util.promisify(redis.client.SADD).bind(redis.client);
redis.client.DEL = util.promisify(redis.client.DEL).bind(redis.client);
redis.client.HSET = util.promisify(redis.client.HSET).bind(redis.client);

export const mockServer = async (chain: IChain) => {
  const stratDataPromises = strategies
    .filter((s) => s.chain === chain)
    .reverse() // reverse to test withdrawalQueue reorder
    .map(async (s, i) => ({
      id: (await ethers.getContract(s.symbol)).address,
      symbol: s.symbol,
      aprThreeDay: i.toString(),
      tvl: i.toString(),
      maxTvl: MaxUint256,
      lastHarvest: '1646816484',
      lastRebalance: '1646684322',
    }))
    .reverse(); // we want abr to  be ascending

  // wait for promises and sort by desc apr
  const stratData = await await Promise.all(stratDataPromises);

  mockApolloClient.setRequestHandler(stratSortedMock.request.query, () =>
    Promise.resolve({
      data: {
        vault: {
          ...stratSortedMock.result.data.vault,
          strategies: stratData,
        },
      },
    })
  );

  const vaultData = await deployments.get('USDC-Vault-0.1');
  ImportMock.mockFunction(vaults, 'getVaults', {
    'USDC-Vault-0.1': vaultData,
  });

  return { stratData, strategies };
};

export const mockStrat = async (lastRebalance: number): Promise<void> => {
  mockApolloClient.setRequestHandler(stratMock.request.query, () =>
    Promise.resolve({
      data: {
        ...stratMock.result.data,
        strategy: {
          ...stratMock.result.data.strategy,
          lastRebalance,
        },
      },
    })
  );
};
