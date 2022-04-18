import fetch from 'node-fetch';
import fetchMock from 'fetch-mock';
import { getGasPrice, chainToReq } from '@sc1/server/keeper/gas';
import { safeParseUnits } from '@sc1/common';
import {
  owlracleMock,
  debankMock,
  owlracleApiError,
} from '../utils/mocks/gasPrices';
import { expect } from 'chai';
import { ImportMock } from 'ts-mock-imports';
import { ethers } from 'hardhat';

process.env.NODE_ENV = 'test';

const { OWLRACLE_API_KEY } = process.env;

const myMock = fetchMock.sandbox();

ImportMock.mockOther(fetch, undefined, myMock);

const delay =
  (response: any, after = 500) =>
  (): Promise<any> =>
    new Promise((resolve) => setTimeout(resolve, after)).then(() => response);

describe('Gas Test.', function () {
  this.timeout(200000);
  const chain = 'moonriver';
  const key = chainToReq[chain];

  describe('if both gas apis fail', function () {
    before(() =>
      myMock
        .get(
          `https://api.debank.com/chain/gas_price_dict_v2?chain=${key}`,
          delay(404, 1600)
        )
        .get(
          `https://owlracle.info/${key}/gas?apikey=${OWLRACLE_API_KEY}`,
          delay(owlracleApiError, 1600)
        )
    );
    it('should allow both apis to fail to 0', async function () {
      const gasPrice = await getGasPrice(chain, 'fast', ethers.provider);
      const providerGasPrice = await (
        await ethers.provider.getGasPrice()
      ).toNumber();
      expect(gasPrice).to.be.equal(providerGasPrice);
      expect(gasPrice).to.be.greaterThan(0);
    });

    after(() => myMock.restore());
  });

  describe('if one gas api fails.', function () {
    before(() =>
      myMock
        .get(
          `https://api.debank.com/chain/gas_price_dict_v2?chain=${key}`,
          debankMock
        )
        .get(
          `https://owlracle.info/${key}/gas?apikey=${OWLRACLE_API_KEY}`,
          delay(404, 1600)
        )
    );
    it('should allow one api to fail gracefully', async function () {
      const gasPrice = await getGasPrice(chain, 'fast', ethers.provider);
      expect(gasPrice).to.be.equal(debankMock.data.fast.price);
    });
    after(() => myMock.restore());
  });

  describe('if apis succeed.', function () {
    before(() =>
      myMock
        .get(
          `https://api.debank.com/chain/gas_price_dict_v2?chain=${key}`,
          debankMock
        )
        .get(
          `https://owlracle.info/${key}/gas?apikey=${OWLRACLE_API_KEY}`,
          owlracleMock,
          { delay: 2000 }
        )
    );
    it('should pick highest gas price for fast', async function () {
      const gasPrice = await getGasPrice(chain, 'fast', ethers.provider);
      expect(gasPrice).to.be.equal(
        safeParseUnits(owlracleMock.speeds[3].gasPrice.toString(), 9).toNumber()
      );
    });
    it('should pick highest gas price for normal', async function () {
      const gasPrice = await getGasPrice(chain, 'normal', ethers.provider);
      expect(gasPrice).to.be.equal(
        safeParseUnits(owlracleMock.speeds[1].gasPrice.toString(), 9).toNumber()
      );
    });
    after(() => myMock.restore());
  });
});
