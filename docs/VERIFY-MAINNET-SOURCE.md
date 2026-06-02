# Verify mainnet contract source (operator)

Run on the Acton deploy host after mainnet deploy:

```bash
cd ~/projects/plx-acton
acton verify JettonMinter --net mainnet
acton verify JettonWallet --net mainnet
acton verify TeamVesting --net mainnet
acton verify PaymentSplitter --net mainnet
```

Then confirm the verified badge on Tonviewer for each contract address in [`MAINNET-DEPLOYMENT-RECORD.md`](MAINNET-DEPLOYMENT-RECORD.md).
