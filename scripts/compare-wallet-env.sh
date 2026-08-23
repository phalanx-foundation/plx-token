#!/usr/bin/env bash
set -euo pipefail
cd ~/projects/plx-acton
DEPLOY_ACTON=$(/home/dev/.acton/bin/acton wallet list | awk '/toolkit-deployer-mainnet/ {print $2}')
SCRATCH_ACTON=$(/home/dev/.acton/bin/acton wallet list | awk '/plx-scratch-seeker-payment/ {print $2}')
API_ENV=~/services/plx-toolkit-api/.env
DEPLOY_ENV=$(grep '^JETTON_DEPLOYER_ADDRESS_MAINNET=' "$API_ENV" | cut -d= -f2- | tr -d '\r')
SCRATCH_ENV=$(grep '^SCRATCH_PAYOUT_ADDRESS=' "$API_ENV" | cut -d= -f2- | tr -d '\r')
echo "toolkit-deployer-mainnet (acton): $DEPLOY_ACTON"
echo "JETTON_DEPLOYER_ADDRESS_MAINNET (env): $DEPLOY_ENV"
echo "plx-scratch-seeker-payment (acton): $SCRATCH_ACTON"
echo "SCRATCH_PAYOUT_ADDRESS (env): $SCRATCH_ENV"
