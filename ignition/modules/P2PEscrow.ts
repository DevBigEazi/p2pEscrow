// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";


const P2PEscrowModule = buildModule("P2PEscrowModule", (m) => {

  const p2PEscrow = m.contract("P2PEscrow");

  return { p2PEscrow };
});

export default P2PEscrowModule;
