process.env.NODE_ENV = 'test'
import { expect } from 'chai'
import { ethers, getNamedAccounts, deployments } from 'hardhat'
import {
  forkNetwork,
  setupAccount,
  setMiningInterval,
  copyDeployments,
  chain,
  forkBlock,
} from '../utils'

import { IChain, strategies } from '@sc1/common'

// NOTE - this test has to run first, otherwise contract is already upgraded

const setupTest = deployments.createFixture(async (_, strat: any) => {
  const { deployer } = await getNamedAccounts()
  await setupAccount(deployer)
  await deployments.run('Strategies', {
    resetMemory: false,
    deletePreviousDeployments: false,
    writeDeploymentsToFiles: false,
  })
})

// runs tests for all strategies
strategies
  // can only test one at a time since the upgrade will update both strategies
  // .filter((s) => s.symbol === 'USDCavaxJOEqi')
  .filter((s) => s.chain === chain)
  .forEach((strat) => {
    describe.skip('Upgrade ' + strat.symbol, function () {
      this.timeout(220000) // fantom is slow

      before(async () => {
        await forkNetwork(chain as IChain, forkBlock[chain])
        await setMiningInterval(0)
        await copyDeployments(chain as IChain)
      })

      it('should upgrade', async function () {
        const { deployer, manager } = await getNamedAccounts()
        const strategy = await ethers.getContract(
          strat.symbol + '-prev',
          deployer,
        )
        const tvl = await strategy.getTotalTVL()

        await setupTest(strat)

        const upgraded = await ethers.getContract(strat.symbol, deployer)

        if (!strategy) throw new Error('missing strategy')

        console.log('start tvl', tvl.toString())
        const dec = await strategy.decimals()

        const isManager = await strategy.isManager(manager)

        // test the last variable to ensure storage layout is correct
        const rebalanceThreshold = await strategy.rebalanceThreshold()

        const oldStart = await ethers.getContractAt(
          strat.symbol,
          strategy.address,
          deployer,
        )
        let version = 0
        try {
          version = await oldStart.version()
        } catch (err) {
          //
        }

        const rebalanceThresholdU = await upgraded.rebalanceThreshold()

        const isManagerU = await upgraded.isManager(manager)

        const versionU = await upgraded.version()
        const tvlU = await upgraded.getTotalTVL()

        // expect(version).to.not.equal(versionU)
        expect(isManager).to.be.true
        expect(isManager).to.equal(isManagerU)
        expect(rebalanceThresholdU).to.equal(rebalanceThreshold)
        expect(versionU).to.equal(1)
        console.log('tvlU', tvlU.toString(), tvl.toString())
        expect(tvlU).to.be.closeTo(tvl, 10 ** (dec - 1))
      })
    })
  })
