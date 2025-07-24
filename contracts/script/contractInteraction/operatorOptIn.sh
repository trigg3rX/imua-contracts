#!/bin/bash

# Set these environment variables before running:
# export IMUA_RPC_URL="https://your.rpc.url"
# export PRIVATE_KEY="your_private_key"

source .env

CONTRACT="0x72A5016ECb9EB01d7d54ae48bFFB62CA0B8e57a5"

cast send $CONTRACT "registerOperatorToAVS()" \
  --rpc-url "$IMUA_RPC_URL" \
  --private-key "$PRIVATE_KEY"
