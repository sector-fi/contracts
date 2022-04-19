# Scion Contracts

## Running Tests

install deps
```
yarn
```

hardhat integration tests:
```
yarn test
```

foundry forge tests:
```
yarn test:forge
```

## Coverage

hardhat integration coverage:
```
yarn cover // alias for npx hardhat coverage
```

limited forge test coverage can be done using dapptools:
```
yarn coverage <Contract.sol>
```

## Strategies

### BaseStrategy
This is a wrapper that provides an interface for the vault to interact with and tracks `shares` and `totalSupply`. Only `vault` is allowed to deposit or withdraw from the strategy so we don't have a need for an ERC20 to track shares. 

### HedgedLP
(inherits from is `BaseStrategy`)  

This is our first strategy, it takes deposits in `underlying`, sends a portion to a lending protocol as collateral, borrows `short` and provides `underlying/short` as liquidity to a Uniswap dex. On each `deposit` or `withdrawal` we increase or decrease our position.

When the price of the `short` asset moves wrt the `underlying` our `shortLP` position will begin to diverge from our `borrowedPosition`. A rebalance is required to restore the the balance. This usually involves in either trading some of the `underlying` for `short` and repaying a portion of the loan, or borrowing more in order to buy more `underlying`. This function is performed by the `manager` role.

The strategy manager is also responsible for harvesting the LP farm. This is done by calling the `harvest` method and providing appropriate slippage parameters. 

A public `rebalanceLoan` method is available for anyone to call if the loan position gets close to liquidation. This will enable an external `keeper` network like Gelato to ensure the safty of the position.

### Security: Swaps & sandwitch/flashloa attacks:
#### underlying/short swaps
`underlying/short` swaps that happen as part of `deposit`, `withdraw`, `rebalance` and `closePosition` are protected against flash-swap attacks by the `checkPrice` modifier. This modifier queries the prices via the oracle used by the lending protocol (usually chainlink) and checks them against the current dex spot price. 

#### harvest swaps
Swaps necessary as part of harvest operations take a `min` output amount computed externally. 

### Mixins
`HedgedLP` uses abstract mixins to interact with lending and dex protocols. These mixina are agnostic to the concrete implementation of the protocol.

### Adapters
Adapters are contrete implementations of the lending and dex mixins for specific protocols. 

## Permissions Architecture

### Strategies
 - Public - can call `rebalanceLoan` when strategy is close to liquidation
 - Vault - can deposit (`mint`) and withdraw (`redeemUnderlying`) from the strategy
 - Owner - can set critical parameters & set manager
 - Manager - `closePosition`, `setMaxTvl`, `rebalance` (not as critical) and `harvest` - critical because of the ability to set slippage params for swaps

### Vault
 - Public - can `deposit` and `withdraw` from vault
 - Owner - can add new strategies, set critical parameters, & set manager
 - Manager
   - `harvest` vault
   - manage assets via `depositIntoStrategy` and `withdrawFromStrategy`
   - set non-critcal configs like `maxTvl`
   - manage `withdrawalQueue` 
   - `seizeStrategy` which attempts to withdraw all assets to the vault and then send any remaining tokens that belong to the strategy to the `owner`

![permissions architecture](https://github.com/scion-finance/contracts/blob/dev/docs/permissions.png?raw=true)
