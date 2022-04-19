import '@nomiclabs/hardhat-waffle'
import 'solidity-coverage'
import 'hardhat-deploy'
import 'hardhat-contract-sizer'
import 'tsconfig-paths/register'
import 'hardhat-gas-reporter'
import env from 'dotenv'
import path from 'path'

// import 'hardhat-typechain'; // doesn't work rn
env.config({ path: path.join(__dirname, '.env') })

const {
  DEPLOYER_KEY,
  MANAGER_KEY,
  INFURA_API_KEY,
  COIN_MARKET_CAP_API,
  SHOW_GAS,
  DEPLOYER,
  MANAGER,
  FORK_CHAIN,
  TEAM_1,
  TIMELOCK_ADMIN,
} = process.env

const keys = [DEPLOYER_KEY, MANAGER_KEY].filter((k) => k != null)

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  namedAccounts: {
    deployer: {
      default: DEPLOYER,
      // default: 'ledger://0x157875C30F83729Ce9c1E7A1568ec00250237862',
      hardhat: DEPLOYER,
      localhost: DEPLOYER,
    },
    owner: {
      default: 0,
      // default: 'ledger://0x157875C30F83729Ce9c1E7A1568ec00250237862',
      // hardhat: DEPLOYER,
    },
    managerProd: {
      default: '0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A',
    },
    manager: {
      default: '0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A',
      hardhat: MANAGER,
      localhost: MANAGER,
    },
    timelockAdmin: {
      default: TIMELOCK_ADMIN,
    },
    team1: {
      default: TEAM_1,
    },
    addr1: {
      default: 1,
    },
    addr2: {
      default: 2,
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
      tags: [FORK_CHAIN],
      allowUnlimitedContractSize: true,
      chains: {
        43114: {
          hardforkHistory: {
            arrowGlacier: 0,
          },
        },
        250: {
          hardforkHistory: {
            arrowGlacier: 0,
          },
        },
      },
    },
    localhost: {
      accounts: keys.length ? keys : undefined,
      tags: [FORK_CHAIN],
    },
    fantom: {
      url: 'https://rpc.ftm.tools/',
      gasPrice: 285e9,
      chainId: 250,
      accounts: keys.length ? keys : undefined,
      tags: ['fantom'],
      verify: {
        etherscan: {
          apiUrl: 'https://api.ftmscan.com/',
        },
      },
    },
    avalanche: {
      url: 'https://api.avax.network/ext/bc/C/rpc',
      gasPrice: 27e9,
      chainId: 43114,
      accounts: keys.length ? keys : undefined,
      tags: ['avalanche'],
      verify: {
        etherscan: {
          apiUrl: 'https://api.snowtrace.io/',
        },
      },
    },
    moonriver: {
      url: 'https://rpc.api.moonriver.moonbeam.network',
      accounts: keys.length ? keys : undefined,
      chainId: 1285,
      gasPrice: 1.1e9,
      name: 'moonriver',
      tags: ['moonriver'],
    },
    mainnet: {
      accounts: keys.length ? keys : undefined,
      url: 'https://mainnet.infura.io/v3/' + INFURA_API_KEY,
      gasPrice: 2.1e9,
      chainId: 1,
    },
  },

  solidity: {
    compilers: [
      {
        version: '0.8.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: SHOW_GAS === 'true',
    currency: 'USD',
    gasPrice: 30,
    coinmarketcap: COIN_MARKET_CAP_API,
  },
  paths: {
    sources: './src',
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
}
