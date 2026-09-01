/**
 * Broadcast Ston.fi balanced liquidity provision from the ops LP wallet (W5 / v5r1).
 *
 * Env:
 *   TON_OPERATOR_MNEMONIC — 24 words for plx-lp (preferred)
 *   LP_TON_NANO — TON side in nano (token A)
 *   STONFI_POOL_ADDRESS, PLX_JETTON_MINTER_MAINNET
 *   EXPECTED_WALLET_ADDRESS — optional; fail if derived address differs
 *   TONCENTER_MAINNET_API_KEY (optional)
 *   STONFI_LP_SLIPPAGE — default 0.01
 *   DRY_RUN=true — simulate + build only, do not send
 */

import { StonApiClient } from "@ston-fi/api";
import { dexFactory } from "@ston-fi/sdk";
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
const tonNano = process.env.LP_TON_NANO || "0";
const slippage = process.env.STONFI_LP_SLIPPAGE || "0.01";
const mnemonic = (process.env.TON_OPERATOR_MNEMONIC || "").trim();
const expected = (process.env.EXPECTED_WALLET_ADDRESS || "").trim();
const dryRun = (process.env.DRY_RUN || "").toLowerCase() === "true";

function fail(msg, extra = {}) {
  console.log(JSON.stringify({ ok: false, error: msg, ...extra }));
  process.exit(1);
}

if (!mnemonic) fail("TON_OPERATOR_MNEMONIC required");
if (!tonNano || BigInt(tonNano) <= 0n) fail("LP_TON_NANO required");

const apiKey = process.env.TONCENTER_MAINNET_API_KEY || "";
const endpoint = apiKey
  ? `https://toncenter.com/api/v2/jsonRPC?api_key=${apiKey}`
  : "https://toncenter.com/api/v2/jsonRPC";

const tonClient = new TonClient({ endpoint, timeout: 30_000 });
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

const simulation = await apiClient.simulateLiquidityProvision({
  provisionType: "Balanced",
  tokenA: TON_NATIVE,
  tokenB: plxMinter,
  tokenAUnits: tonNano,
  poolAddress: pool,
  slippageTolerance: slippage,
  walletAddress: userWalletAddress,
});

if (!simulation?.routerAddress) {
  fail("simulate_failed", { simulation });
}

const routerInfo = await apiClient.getRouter(simulation.routerAddress);
const { Router, pTON } = dexFactory(routerInfo);
const router = tonClient.open(Router.create(routerInfo.address));
const pTon = pTON.create(routerInfo.ptonMasterAddress);

const isTonAsset = (addr) => addr === TON_NATIVE;

async function buildLeg({ sendAmount, sendTokenAddress, otherTokenAddress }) {
  const base = {
    userWalletAddress,
    minLpOut: simulation.minLpUnits,
    sendAmount,
    otherTokenAddress: isTonAsset(otherTokenAddress)
      ? pTon.address.toString()
      : otherTokenAddress,
  };
  if (isTonAsset(sendTokenAddress)) {
    return router.getProvideLiquidityTonTxParams({
      ...base,
      proxyTon: pTon,
    });
  }
  return router.getProvideLiquidityJettonTxParams({
    ...base,
    sendTokenAddress,
  });
}

const [tonLeg, jettonLeg] = await Promise.all([
  buildLeg({
    sendAmount: simulation.tokenAUnits,
    sendTokenAddress: simulation.tokenA,
    otherTokenAddress: simulation.tokenB,
  }),
  buildLeg({
    sendAmount: simulation.tokenBUnits,
    sendTokenAddress: simulation.tokenB,
    otherTokenAddress: simulation.tokenA,
  }),
]);

const payload = {
  ok: true,
  dry_run: dryRun,
  mode: dryRun ? "stonfi_lp_dry_run" : "stonfi_broadcast",
  wallet: userWalletAddress,
  pool,
  ton_nano: tonNano,
  plx_nano: simulation.tokenBUnits,
  min_lp_units: simulation.minLpUnits,
  router: simulation.routerAddress,
  legs: [
    { to: tonLeg.to.toString(), value: tonLeg.value.toString() },
    { to: jettonLeg.to.toString(), value: jettonLeg.value.toString() },
  ],
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
      to: tonLeg.to,
      value: tonLeg.value,
      body: tonLeg.body,
      bounce: true,
    }),
    internal({
      to: jettonLeg.to,
      value: jettonLeg.value,
      body: jettonLeg.body,
      bounce: true,
    }),
  ],
});

console.log(JSON.stringify({ ...payload, seqno }));
process.exit(0);
