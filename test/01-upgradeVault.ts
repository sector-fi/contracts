import { expect } from "chai";
import { ethers, getNamedAccounts, deployments } from "hardhat";
import {
  forkNetwork,
  setupAccount,
  setMiningInterval,
  copyDeployments,
  getVault,
  forkBlock,
} from "../utils";

import { IChain } from "@sc1/common";
Error.stackTraceLimit = Infinity;

// NOTE - this test has to run first, otherwise contract is already upgraded

const { FORK_CHAIN = "" } = process.env;

const setupTest = deployments.createFixture(async () => {
  const { deployer } = await getNamedAccounts();
  await setupAccount(deployer);
  await deployments.run(["USDC-Vault-0"], {
    resetMemory: false,
    deletePreviousDeployments: false,
    writeDeploymentsToFiles: false,
  });
  const vault = await getVault(undefined, "0.2");
  return vault;
});

describe("Upgrade Vault", function () {
  this.timeout(220000); // fantom is slow

  before(async () => {
    await forkNetwork(FORK_CHAIN as IChain, forkBlock[FORK_CHAIN]);
    await setMiningInterval(0);
    await copyDeployments(FORK_CHAIN as IChain);
  });

  it("should upgrade", async function () {
    const { manager } = await getNamedAccounts();
    const vault = await await getVault();
    if (!vault) throw new Error("missing vault");

    const isManager = await vault.isManager(manager);
    const q0 = await vault.withdrawalQueue(0);
    const maxLockedProfit = await vault.maxLockedProfit();
    const lastHarvest = await vault.lastHarvest();
    const isPublic = await vault.isPublic();

    const upgraded = await setupTest();
    console.log("upgraded", upgraded.address, manager);

    const isManagerU = await upgraded.isManager(manager);
    const q0U = await upgraded.withdrawalQueue(0);
    const maxLockedProfitU = await upgraded.maxLockedProfit();
    const lastHarvestU = await upgraded.lastHarvest();
    const isPublicU = await upgraded.isPublic();
    // const version = await upgraded.version();

    // expect(version).to.be.equal(2);
    expect(isManager).to.be.true;
    expect(isManager).to.equal(isManagerU);
    expect(q0U).to.equal(q0);
    expect(lastHarvestU).to.be.equal(lastHarvest);
    expect(lastHarvestU).to.be.gt(0);
    expect(maxLockedProfitU).to.be.equal(maxLockedProfit);
    expect(isPublicU).to.be.equal(isPublic);
  });
});
