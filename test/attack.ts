import { assert, expect } from 'chai'
import { ethers, getNamedAccounts, deployments, network } from 'hardhat'
import {
  forkNetwork,
  approve,
  fundAccount,
  mockChainlink,
  getTvl,
  setupAccount,
  setMiningInterval,
  movePriceBy,
  disableBandFeed,
  buyUnderlying,
  getVault,
  chain,
  forkBlock,
} from '../utils'
import { getUniAddr } from '@sc1/common/utils/address'
import { IChain, strategies } from '@sc1/common'

// this test demonstrates an (expensive) sandwitch attack on the Vault:
// attacker is able to use large capital + sandwitch attack to decrease the value of an underlying strategyy
// and the is able to buy vault shares at a discount and sell them later once the correct balance is restored
// prevention methods:
// 1.√ use could use price oracles to compute strategy tvl, but this cannot be done with 100% accuracy because of of issues with computation of LP value
// 2. Vault should track lockedLoss, just like it tracs lockedProfit - this would make the sandwitch attack anfeasable
// since arbitraguers will restore the price before loss is 'unlocked'

// CAPITAL REQUIRED
// in a smaller pool like AVAX/USDC on Pangolin (21M in liquidity)
// it costs about $8.5M of AVAX to move the price down by 50%
// this can earn the attacker 1.85% return on any capital deposited
// so, for example access to $18.5M in capital will result in $263K in profit (1.85% of 10M + 4.2M from the AVAX sale)
// with flashbots this attack is riskless and can be performed on every single harvest

const { getSigner, utils } = ethers
const { parseUnits, formatUnits } = utils

const DEPOSIT_AMT = '100'

const setupTest = deployments.createFixture(async (_, strat: any) => {
  await deployments.fixture(['Timelock', 'DevOwner', 'Mocks', 'TimelockStrat'])
  await setMiningInterval(0)
  const { deployer, manager, addr1 } = await getNamedAccounts()

  const vault = await getVault()

  await vault.bulkAllow([addr1])
  // await vault.setFeePercent(0)
  await setupAccount(deployer)

  await fundAccount(addr1, '1000000000')
  await fundAccount(deployer, '1000000000')
  await approve(strat.underlying, deployer, vault.address)
  await approve(strat.underlying, addr1, vault.address)

  const router = getUniAddr('UNISWAP_ROUTER', strat.swap)
  await approve(strat.underlying, deployer, router)
  await approve(strat.underlying, addr1, router)

  await mockChainlink(strat)

  const strategy = await ethers.getContract(strat.symbol, deployer)

  await disableBandFeed(strat)
  const dec = await strategy.decimals()

  await buyUnderlying(
    addr1,
    strat.underlying,
    strat.short,
    parseUnits('200', 6),
    strat.swap,
    strat.chain,
  )

  return { vault, strategy, dec }
})

// runs tests for all strategies
strategies
  .filter((s) => s.chain === chain)
  // .filter((s) => s.symbol === 'USDCavaxPNGqi')
  .forEach((strat) => {
    describe(strat.symbol, function () {
      this.timeout(80000) // fantom is slow

      let owner
      let managerSig
      let vault
      let strategy
      let dec
      let hacker
      let baseUnits

      before(async () => {
        await forkNetwork(chain as IChain, forkBlock[chain])
        await setMiningInterval(0)
        const { deployer, manager, addr1 } = await getNamedAccounts()
        owner = deployer
        managerSig = await getSigner(manager)
        hacker = await getSigner(addr1)
      })

      describe('attack', async () => {
        before(async () => {
          ;({ vault, strategy, dec } = await setupTest(strat))
          baseUnits = await vault.BASE_UNIT()
        })

        it('regular users deposit funds', async function () {
          const amountUsd = parseUnits(DEPOSIT_AMT, dec)
          await vault.deposit(amountUsd)
          await vault
            .connect(managerSig)
            .depositIntoStrategy(strategy.address, amountUsd)
          const price = await vault.exchangeRate()
          console.log('start price', formatUnits(price, dec))
          expect(price).to.be.closeTo(baseUnits, 10 ** (dec / 2))
          await getTvl(strategy)
        })

        it('attack - sandwitch harvest start', async function () {
          await movePriceBy(0.5, strat, owner, strategy, true)
          const price = await vault.exchangeRate()
          console.log('price', formatUnits(price, dec))
          expect(price).to.be.closeTo(baseUnits, 10 ** (dec / 2))
          await getTvl(strategy)
        })

        it('harvest', async function () {
          await vault.connect(managerSig).harvest([strategy.address])
          const price = await vault.exchangeRate()
          // here the price is decreased (but deposits should not be impacted)
          // expect(price).to.be.lt(baseUnits);
          console.log('price', formatUnits(price, dec))
          await getTvl(strategy)
        })

        it('attack - harvest sandwitch end', async function () {
          const amount = parseUnits(DEPOSIT_AMT, dec)
          await vault.connect(hacker).deposit(amount)
          await movePriceBy(2, strat, owner, strategy, true)
          // here price is till depressed (waiting for harvest)
          const price = await vault.exchangeRate()
          console.log('price', formatUnits(price, dec))
          // expect(price).to.be.lt(baseUnits);
          // expect(price).to.be.closeTo(baseUnits, 10 ** (dec / 2));
        })

        it('wait until next harvest', async function () {
          await vault.connect(managerSig).harvest([strategy.address])
          await network.provider.send('evm_increaseTime', [6 * 60 * 60])
          await network.provider.send('evm_mine')
          const price = await vault.exchangeRate()
          console.log('price', formatUnits(price, dec))
          await getTvl(strategy)
          expect(price).to.be.closeTo(baseUnits, 10 ** (dec / 2))
        })

        it('attacker share value should not be inflated', async function () {
          const shareBalanceHacker = await vault.balanceOf(hacker.address)
          const shareBalanceOwner = await vault.balanceOf(owner)
          const totalSupply = await vault.totalSupply()
          const tvl = await vault.totalHoldings()

          console.log('supply', formatUnits(totalSupply, dec))
          console.log('tvl', formatUnits(tvl, dec))

          const price = await vault.exchangeRate()
          console.log('price', formatUnits(price, dec))

          const hackerBalance = shareBalanceHacker.mul(price).div(baseUnits)
          const ownerBalance = shareBalanceOwner.mul(price).div(baseUnits)
          console.log('hacker balance', formatUnits(hackerBalance, dec))
          console.log('owner balance', formatUnits(ownerBalance, dec))

          expect(hackerBalance).to.be.closeTo(ownerBalance, 10 ** (dec / 2))
        })
      })
    })
  })
