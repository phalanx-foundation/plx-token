/**
 * Broadcast Ston.fi TON→PLX swap from plx-treasury (W5 / v5r1) for buyback.
 *
 * Env:
 *   TON_OPERATOR_MNEMONIC — 24 words for plx-treasury (or loaded by Python wrapper)
 *   SWAP_UNITS — TON nano to swap
 *   STONFI_POOL_ADDRESS, PLX_JETTON_MINTER_MAINNET
 *   EXPECTED_WALLET_ADDRESS — pin treasury EQ address
 *   STONFI_SLIPPAGE — default 0.03
 *   TONCENTER_MAINNET_API_KEY (optional)
 *   DRY_RUN=true — simulate + build only, do not send
 */

import { StonApiClient } from "@ston-fi/api";
import { dexFactory, Client as StonClient } from "@ston-fi/sdk";
import { mnemonicToPrivateKey } from "@ton/crypto";
import { Address, internal } from "@ton/core";
import { TonClient, WalletContractV5R1 } from "@ton/ton";

const TON_NATIVE = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c";
const pool =
  process.env.STONFI_POOL_ADDRESS ||
  "EQAm-5HxQpfQl8_lqyvax4AEPS9LXp6rE8AFr35hcfRPyZTq";
const plxMinter =
  process.env.PLX_JETTON_MINTER_MAINNET ||
  process.env.JETTON_MINTER_ADDRESS ||
  "EQCbaUJqiRIuw5U-A_tUYTK4mdH0L37oFMvxeMEDGE5nVfLS";
const units = process.env.SWAP_UNITS || "0";
const slippage = process.env.STONFI_SLIPPAGE || "0.03";
const mnemonic = (process.env.TON_OPERATOR_MNEMONIC || "").trim();
const expected = (process.env.EXPECTED_WALLET_ADDRESS || "").trim();
const dryRun = (process.env.DRY_RUN || "").toLowerCase() === "true";

function fail(msg, extra = {}) {
  console.log(JSON.stringify({ ok: false, error: msg, ...extra }));
  process.exit(1);
}

if (!mnemonic) fail("TON_OPERATOR_MNEMONIC required");
if (!units || BigInt(units) <= 0n) fail("SWAP_UNITS required");

const apiKey = process.env.TONCENTER_MAINNET_API_KEY || "";
const endpoint = apiKey
  ? `https://toncenter.com/api/v2/jsonRPC?api_key=${apiKey}`
  : "https://toncenter.com/api/v2/jsonRPC";

const tonClient = new TonClient({ endpoint, timeout: 30_000 });
const stonClient = new StonClient({ endpoint, timeout: 30_000 });
const apiClient = new StonApiClient();

const keyPair = await mnemonicToPrivateKey(mnemonic.split(/\s+/));
const wallet = WalletContractV5R1.create({
  workchain: 0,
  publicKey: keyPair.publicKey,
});
const walletContract = tonClient.open(wallet);
const userWalletAddress = wallet.address.toString({
  bounceable: true,
  urlSafe: true,
});

if (expected) {
  const a = Address.parse(expected);
  const b = wallet.address;
  if (!a.equals(b)) {
    fail("derived_wallet_mismatch", {
      expected,
      derived: userWalletAddress,
    });
  }
}

const simulation = await apiClient.simulateSwap({
  offerAddress: TON_NATIVE,
  askAddress: plxMinter,
  offerUnits: units,
  poolAddress: pool,
  slippageTolerance: slippage,
  walletAddress: userWalletAddress,
});

if (!simulation?.routerAddress) {
  fail("simulate_failed", { simulation });
}

const routerInfo = await apiClient.getRouter(simulation.routerAddress);
const dexContracts = dexFactory(routerInfo);
const router = stonClient.open(dexContracts.Router.create(routerInfo.address));
const proxyTon = dexContracts.pTON.create(routerInfo.ptonMasterAddress);

const txParams = await router.getSwapTonToJettonTxParams({
  userWalletAddress,
  offerAmount: simulation.offerUnits,
  minAskAmount: simulation.minAskUnits,
  askJettonAddress: simulation.askAddress,
  proxyTon,
  queryId: Date.now(),
});

const payload = {
  ok: true,
  dry_run: dryRun,
  mode: dryRun ? "buyback_swap_dry_run" : "buyback_swap_broadcast",
  side: "buy",
  wallet: userWalletAddress,
  pool,
  ton_nano: units,
  ask_units: simulation.askUnits,
  min_ask_units: simulation.minAskUnits,
  router: simulation.routerAddress,
  to: txParams.to.toString(),
  value: txParams.value.toString(),
};

if (dryRun) {
  console.log(JSON.stringify(payload));
  process.exit(0);
}

const seqno = await walletContract.getSeqno();
await walletContract.sendTransfer({
  seqno,
  secretKey: keyPair.secretKey,
  messages: [
    internal({
      to: txParams.to,
      value: txParams.value,
      body: txParams.body,
      bounce: true,
    }),
  ],
});

console.log(JSON.stringify({ ...payload, seqno }));
process.exit(0);
