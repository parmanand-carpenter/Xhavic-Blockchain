#!/bin/bash

# Bridge ETH from L1 Sepolia to your L2 Rollup
# This script helps you deposit ETH into your L2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment
if [ ! -f .env ]; then
    log_error ".env file not found"
    exit 1
fi

source .env

# Get bridge contract addresses from state.json
OPTIMISM_PORTAL=$(cat deployer/.deployer/state.json | jq -r '.opChainDeployments[0].OptimismPortalProxy')

log_info "L2 Rollup Bridge Information"
echo ""
echo "================================================"
echo "L1 Network: Sepolia (Chain ID: 11155111)"
echo "L2 Network: Your Custom L2 (Chain ID: $L2_CHAIN_ID)"
echo "================================================"
echo ""
echo "Bridge Contract (OptimismPortal): $OPTIMISM_PORTAL"
echo "L1 RPC: $L1_RPC_URL"
echo "L2 RPC: http://localhost:8545"
echo ""

# Check if cast is available
if ! command -v cast &> /dev/null; then
    log_error "cast (foundry) is required but not installed"
    log_info "Install foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"
    exit 1
fi

# Get amount to bridge (default 0.01 ETH)
AMOUNT=${1:-0.01}
AMOUNT_WEI=$(cast to-wei $AMOUNT ether)

log_info "Preparing to bridge $AMOUNT ETH from L1 Sepolia to L2..."
echo ""

# Derive your address from private key
# Pass via env var to avoid exposing the key in the process table (ps aux)
YOUR_ADDRESS=$(ETH_PRIVATE_KEY="$PRIVATE_KEY" cast wallet address)
log_info "Your address: $YOUR_ADDRESS"

# Check L1 balance
L1_BALANCE=$(cast balance $YOUR_ADDRESS --rpc-url $L1_RPC_URL)
L1_BALANCE_ETH=$(cast from-wei $L1_BALANCE)
log_info "L1 Balance: $L1_BALANCE_ETH ETH"

if [ $(echo "$L1_BALANCE < $AMOUNT_WEI" | bc) -eq 1 ]; then
    log_error "Insufficient L1 balance. You need at least $AMOUNT ETH on Sepolia"
    log_info "Get Sepolia ETH from: https://www.alchemy.com/faucets/ethereum-sepolia"
    exit 1
fi

# Check L2 balance before
L2_BALANCE_BEFORE=$(cast balance $YOUR_ADDRESS --rpc-url http://localhost:8545 2>/dev/null || echo "0")
L2_BALANCE_BEFORE_ETH=$(cast from-wei $L2_BALANCE_BEFORE)
log_info "L2 Balance (before): $L2_BALANCE_BEFORE_ETH ETH"

echo ""
log_info "Sending deposit transaction to OptimismPortal..."
echo ""

# Call depositTransaction on OptimismPortal
# Function signature: depositTransaction(address _to, uint256 _value, uint64 _gasLimit, bool _isCreation, bytes _data)
# ETH_PRIVATE_KEY is used by cast so the key does not appear in the process table
export ETH_PRIVATE_KEY="$PRIVATE_KEY"
TX_HASH=$(cast send $OPTIMISM_PORTAL \
    "depositTransaction(address,uint256,uint64,bool,bytes)" \
    $YOUR_ADDRESS \
    $AMOUNT_WEI \
    100000 \
    false \
    0x \
    --value $AMOUNT_WEI \
    --rpc-url $L1_RPC_URL \
    --json | jq -r '.transactionHash')
unset ETH_PRIVATE_KEY

log_success "Deposit transaction sent!"
echo ""
echo "Transaction Hash: $TX_HASH"
echo "View on Sepolia Explorer: https://sepolia.etherscan.io/tx/$TX_HASH"
echo ""

log_info "Waiting for transaction confirmation on L1..."
cast receipt $TX_HASH --rpc-url $L1_RPC_URL > /dev/null

log_success "L1 transaction confirmed!"
echo ""
log_info "Waiting for L2 deposit to be processed (~1-2 minutes)..."
log_info "The batcher needs to submit the deposit to L2..."

# Wait for balance to update on L2 (check every 10 seconds for up to 5 minutes)
MAX_WAIT=30  # 30 iterations * 10 seconds = 5 minutes
COUNTER=0

while [ $COUNTER -lt $MAX_WAIT ]; do
    sleep 10
    L2_BALANCE_AFTER=$(cast balance $YOUR_ADDRESS --rpc-url http://localhost:8545 2>/dev/null || echo "0")

    if [ "$L2_BALANCE_AFTER" != "$L2_BALANCE_BEFORE" ]; then
        L2_BALANCE_AFTER_ETH=$(cast from-wei $L2_BALANCE_AFTER)
        echo ""
        log_success "Deposit received on L2!"
        echo ""
        echo "================================================"
        echo "L2 Balance (after): $L2_BALANCE_AFTER_ETH ETH"
        echo "================================================"
        echo ""
        log_success "You can now send transactions on your L2!"
        echo ""
        echo "To send a test transaction:"
        echo "  cast send <RECIPIENT_ADDRESS> --value 0.001ether --private-key \$PRIVATE_KEY --rpc-url http://localhost:8545"
        echo ""
        exit 0
    fi

    COUNTER=$((COUNTER + 1))
    echo -n "."
done

echo ""
log_info "Still waiting for deposit. This can take a few minutes."
log_info "Check your L2 balance manually with:"
echo "  cast balance $YOUR_ADDRESS --rpc-url http://localhost:8545"
