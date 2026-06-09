#!/bin/bash

# OP Stack L2 Rollup Setup Script
# This script automates the deployment of a complete L2 rollup testnet

set -e

# Check if running in Docker
if [ -f "/.dockerenv" ]; then
    log_error "This script should not be run inside Docker. Run it on the host system."
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# Load .env early so L2_CHAIN_ID and other vars are available before use
if [ -f "$(dirname "$0")/../.env" ]; then
    set -a
    source "$(dirname "$0")/../.env"
    set +a
fi

L1_CHAIN_ID=11155111  # Sepolia
L2_CHAIN_ID_DECIMAL=${L2_CHAIN_ID:-16586}  # Default test chain ID (decimal)
L2_CHAIN_ID=$(printf "0x%064x" "$L2_CHAIN_ID_DECIMAL")  # Convert to full 64-char hex format for TOML
P2P_ADVERTISE_IP=${P2P_ADVERTISE_IP:-127.0.0.1}  # Default to localhost for local testing
WORKSPACE_DIR="$(pwd)"
ROLLUP_DIR="$WORKSPACE_DIR"
DEPLOYER_DIR="$ROLLUP_DIR/deployer"
SEQUENCER_DIR="$ROLLUP_DIR/sequencer"
BATCHER_DIR="$ROLLUP_DIR/batcher"
PROPOSER_DIR="$ROLLUP_DIR/proposer"
CHALLENGER_DIR="$ROLLUP_DIR/challenger"
DISPUTE_MON_DIR="$ROLLUP_DIR/dispute-mon"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v op-deployer &> /dev/null; then
        log_error "op-deployer not found. Please ensure it's downloaded"
        log_info "Run: make download"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Derive Ethereum addresses from private keys
derive_addresses_from_keys() {
    log_info "Deriving Ethereum addresses from private keys..."

    # Check if cast is available
    if ! command -v cast &> /dev/null; then
        log_error "cast (foundry) is required but not installed"
        log_info "Install foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"
        exit 1
    fi

    mkdir -p "$DEPLOYER_DIR/addresses"
    log_info "Created addresses directory: $DEPLOYER_DIR/addresses"

    cd "$DEPLOYER_DIR/addresses"

    # Derive addresses from private keys (local one-time setup)

    # Derive deployer address (used for admin and system roles)
    DEPLOYER_ADDRESS=$(cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null)
    if [ -z "$DEPLOYER_ADDRESS" ]; then
        log_error "Failed to derive deployer address from PRIVATE_KEY"
        exit 1
    fi
    log_info "Deployer address: $DEPLOYER_ADDRESS"

    # Derive sequencer address
    SEQUENCER_ADDRESS=$(cast wallet address --private-key "$SEQUENCER_PRIVATE_KEY" 2>/dev/null)
    if [ -z "$SEQUENCER_ADDRESS" ]; then
        log_error "Failed to derive sequencer address from SEQUENCER_PRIVATE_KEY"
        exit 1
    fi
    log_info "Sequencer address: $SEQUENCER_ADDRESS"

    # Derive batcher address
    BATCHER_ADDRESS=$(cast wallet address --private-key "$BATCHER_PRIVATE_KEY" 2>/dev/null)
    if [ -z "$BATCHER_ADDRESS" ]; then
        log_error "Failed to derive batcher address from BATCHER_PRIVATE_KEY"
        exit 1
    fi
    log_info "Batcher address: $BATCHER_ADDRESS"

    # Derive proposer address
    PROPOSER_ADDRESS=$(cast wallet address --private-key "$PROPOSER_PRIVATE_KEY" 2>/dev/null)
    if [ -z "$PROPOSER_ADDRESS" ]; then
        log_error "Failed to derive proposer address from PROPOSER_PRIVATE_KEY"
        exit 1
    fi
    log_info "Proposer address: $PROPOSER_ADDRESS"

    # Derive challenger address
    CHALLENGER_ADDRESS=$(cast wallet address --private-key "$CHALLENGER_PRIVATE_KEY" 2>/dev/null)
    if [ -z "$CHALLENGER_ADDRESS" ]; then
        log_error "Failed to derive challenger address from CHALLENGER_PRIVATE_KEY"
        exit 1
    fi
    log_info "Challenger address: $CHALLENGER_ADDRESS"

    # Save addresses to files for reference
    echo "$DEPLOYER_ADDRESS" > admin_address.txt
    echo "$DEPLOYER_ADDRESS" > base_fee_vault_recipient_address.txt
    echo "$DEPLOYER_ADDRESS" > l1_fee_vault_recipient_address.txt
    echo "$DEPLOYER_ADDRESS" > sequencer_fee_vault_recipient_address.txt
    echo "$DEPLOYER_ADDRESS" > system_config_address.txt
    echo "$SEQUENCER_ADDRESS" > unsafe_block_signer_address.txt
    echo "$BATCHER_ADDRESS" > batcher_address.txt
    echo "$PROPOSER_ADDRESS" > proposer_address.txt
    echo "$CHALLENGER_ADDRESS" > challenger_address.txt

    log_success "All addresses derived from private keys"
    log_info "Using existing MetaMask private keys from .env"
}

# Initialize op-deployer
init_deployer() {
    log_info "Initializing op-deployer..."

    cd "$DEPLOYER_DIR"

    # Create .env file
    cat > .env << EOF
L1_RPC_URL=$L1_RPC_URL
PRIVATE_KEY=$PRIVATE_KEY
EOF

    # Remove any existing .deployer directory for clean state
    rm -rf .deployer

        # Initialize intent
    op-deployer init \
        --l1-chain-id $L1_CHAIN_ID \
        --l2-chain-ids "$L2_CHAIN_ID_DECIMAL" \
        --workdir .deployer \
        --intent-type standard-overrides

    log_success "op-deployer initialized"
}

# Update intent configuration
update_intent() {
    log_info "Patching intent configuration..."

    # Read generated signer addresses
    UNSAFE_BLOCK_SIGNER_ADDR=$(cat addresses/unsafe_block_signer_address.txt)
    BATCHER_ADDR=$(cat addresses/batcher_address.txt)
    PROPOSER_ADDR=$(cat addresses/proposer_address.txt)
    CHALLENGER_ADDR=$(cat addresses/challenger_address.txt)

    # Patch the op-deployer-init-generated intent.toml in place. We keep the
    # generated opcmAddress, contract locators, opDeployerVersion and the
    # [chains.customGasToken] section untouched so the file always matches the
    # installed binary version and the current L1 OPCM state (this avoids the
    # version-drift initVersion() reverts). The mainnet OPCM is selected
    # automatically by init when L1_CHAIN_ID=1.
    #
    # On testnet all fee recipients and owner roles point to the deployer EOA;
    # for mainnet swap the owner roles to your Safe multisig addresses.
    L2_CHAIN_ID_HEX=$(printf "0x%064x" "$L2_CHAIN_ID")
    sed -i.bak "s|id = .*|id = \"$L2_CHAIN_ID_HEX\"|" .deployer/intent.toml
    sed -i.bak "s|fundDevAccounts = .*|fundDevAccounts = false|" .deployer/intent.toml
    sed -i.bak "s|gasLimit = .*|gasLimit = 30000000|" .deployer/intent.toml
    sed -i.bak "s|minBaseFee = .*|minBaseFee = 5000000|" .deployer/intent.toml
    sed -i.bak "s|baseFeeVaultRecipient = .*|baseFeeVaultRecipient = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|l1FeeVaultRecipient = .*|l1FeeVaultRecipient = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|sequencerFeeVaultRecipient = .*|sequencerFeeVaultRecipient = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|operatorFeeVaultRecipient = .*|operatorFeeVaultRecipient = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|chainFeesRecipient = .*|chainFeesRecipient = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|l1ProxyAdminOwner = .*|l1ProxyAdminOwner = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|l2ProxyAdminOwner = .*|l2ProxyAdminOwner = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    sed -i.bak "s|systemConfigOwner = .*|systemConfigOwner = \"$DEPLOYER_ADDRESS\"|" .deployer/intent.toml
    # NOTE: do NOT set liquidityControllerOwner — leaving it at the zero address
    # keeps custom gas token DISABLED (Xhavic uses ETH). A non-zero value makes
    # v0.6.0 require CustomGasToken.Name and fail validation.
    sed -i.bak "s|unsafeBlockSigner = .*|unsafeBlockSigner = \"$UNSAFE_BLOCK_SIGNER_ADDR\"|" .deployer/intent.toml
    sed -i.bak "s|batcher = .*|batcher = \"$BATCHER_ADDR\"|" .deployer/intent.toml
    sed -i.bak "s|proposer = .*|proposer = \"$PROPOSER_ADDR\"|" .deployer/intent.toml
    sed -i.bak "s|challenger = .*|challenger = \"$CHALLENGER_ADDR\"|" .deployer/intent.toml
    rm -f .deployer/intent.toml.bak

    log_success "Intent configuration patched"
}

# Deploy L1 contracts
deploy_contracts() {
    log_info "Deploying L1 contracts..."

    cd "$DEPLOYER_DIR"

    # Note: op-deployer does not support ETH_PRIVATE_KEY env var.
    # For production, replace --private-key with a hardware wallet or KMS signer.
    op-deployer apply \
        --workdir .deployer \
        --l1-rpc-url "$L1_RPC_URL" \
        --private-key "$PRIVATE_KEY"

    log_success "L1 contracts deployed"
}

# Generate chain configuration
generate_config() {
    log_info "Generating chain configuration..."

    cd "$DEPLOYER_DIR"

    op-deployer inspect genesis --workdir .deployer "$L2_CHAIN_ID" > .deployer/genesis.json
    op-deployer inspect rollup --workdir .deployer "$L2_CHAIN_ID" > .deployer/rollup.json

    log_success "Chain configuration generated"
}

# Setup sequencer
setup_sequencer() {
    log_info "Setting up sequencer..."

    mkdir -p "$SEQUENCER_DIR"
    cd "$SEQUENCER_DIR"

    # Remove stale op-node databases from any previous chain. These are
    # bind-mounted (not in the op-geth Docker volume), so they survive a
    # volume wipe and would otherwise leak a previous chain's safe-head
    # history into the fresh chain — which makes op-challenger try to
    # dispute non-existent L2 blocks (e.g. block 311026 from an old chain).
    # op-node creates these as root, so remove them via a root container
    # (a plain `rm` run by the host user would hit permission denied).
    log_info "Cleaning stale op-node databases (safedb / discovery / peerstore)..."
    if [ -d op-node-safedb ] || [ -d opnode_discovery_db ] || [ -d opnode_peerstore_db ]; then
        docker run --rm -v "$SEQUENCER_DIR":/seq alpine \
            sh -c "rm -rf /seq/op-node-safedb /seq/opnode_discovery_db /seq/opnode_peerstore_db" \
            2>/dev/null || rm -rf op-node-safedb opnode_discovery_db opnode_peerstore_db
    fi

    # Copy configuration files
    cp "$DEPLOYER_DIR/.deployer/genesis.json" .
    cp "$DEPLOYER_DIR/.deployer/rollup.json" .

    # Generate JWT secret
    openssl rand -hex 32 > jwt.txt
    chmod 600 jwt.txt

    # Create .env file with sequencer private key
    cat > .env << EOF
L1_RPC_URL=$L1_RPC_URL
L1_BEACON_URL=$L1_BEACON_URL
PRIVATE_KEY=$SEQUENCER_PRIVATE_KEY
P2P_ADVERTISE_IP=$P2P_ADVERTISE_IP
L2_CHAIN_ID=$L2_CHAIN_ID
EOF

    log_success "Sequencer setup complete"
}

# Setup batcher
setup_batcher() {
    log_info "Setting up batcher..."

    mkdir -p "$BATCHER_DIR"
    cd "$BATCHER_DIR"

    # Copy state file
    cp "$DEPLOYER_DIR/.deployer/state.json" .
    # Batch inbox is a pre-computed drop address from rollup.json, NOT the SystemConfigProxy
    INBOX_ADDRESS=$(jq -r '.batch_inbox_address' "$DEPLOYER_DIR/.deployer/rollup.json")
    
    # Create .env file with OP_BATCHER prefixed variables using batcher private key
    # Use production-ready settings from main .env or defaults
    POLL_INTERVAL=${OP_BATCHER_POLL_INTERVAL:-1s}
    SUB_SAFETY_MARGIN=${OP_BATCHER_SUB_SAFETY_MARGIN:-300}
    NUM_CONFIRMATIONS=${OP_BATCHER_NUM_CONFIRMATIONS:-10}
    SAFE_ABORT_COUNT=${OP_BATCHER_SAFE_ABORT_NONCE_TOO_LOW_COUNT:-3}

    cat > .env << EOF
OP_BATCHER_L2_ETH_RPC=http://op-geth:8545
OP_BATCHER_ROLLUP_RPC=http://op-node:8547
OP_BATCHER_PRIVATE_KEY=$BATCHER_PRIVATE_KEY
OP_BATCHER_POLL_INTERVAL=$POLL_INTERVAL
OP_BATCHER_SUB_SAFETY_MARGIN=$SUB_SAFETY_MARGIN
OP_BATCHER_NUM_CONFIRMATIONS=$NUM_CONFIRMATIONS
OP_BATCHER_SAFE_ABORT_NONCE_TOO_LOW_COUNT=$SAFE_ABORT_COUNT
OP_BATCHER_INBOX_ADDRESS=$INBOX_ADDRESS
EOF

    log_success "Batcher setup complete"
}

# Setup proposer
setup_proposer() {
    log_info "Setting up proposer..."

    mkdir -p "$PROPOSER_DIR"
    cd "$PROPOSER_DIR"

    # Copy state file
    cp "$DEPLOYER_DIR/.deployer/state.json" .

    # Extract dispute game factory address
    GAME_FACTORY_ADDR=$(cat state.json | jq -r '.opChainDeployments[0].DisputeGameFactoryProxy')

    # Create .env file with OP_PROPOSER prefixed variables using proposer private key
    # Use production-ready settings from main .env or defaults
    PROPOSER_POLL_INTERVAL=${OP_PROPOSER_POLL_INTERVAL:-12s}
    # Stage 0 (permissioned) chain → PermissionedDisputeGame = game type 1.
    # Must match the game type registered on the DisputeGameFactory, else
    # the proposer cannot create games and the chain never finalizes.
    PROPOSER_GAME_TYPE=${OP_PROPOSER_GAME_TYPE:-1}
    PROPOSER_PROPOSAL_INTERVAL=${OP_PROPOSER_PROPOSAL_INTERVAL:-5h}

    cat > .env << EOF
OP_PROPOSER_GAME_FACTORY_ADDRESS=$GAME_FACTORY_ADDR
OP_PROPOSER_PRIVATE_KEY=$PROPOSER_PRIVATE_KEY
OP_PROPOSER_POLL_INTERVAL=$PROPOSER_POLL_INTERVAL
OP_PROPOSER_GAME_TYPE=$PROPOSER_GAME_TYPE
OP_PROPOSER_PROPOSAL_INTERVAL=$PROPOSER_PROPOSAL_INTERVAL
EOF

    log_success "Proposer setup complete"
}

# Setup challenger
setup_challenger() {
    log_info "Setting up challenger..."

    mkdir -p "$CHALLENGER_DIR"
    cd "$CHALLENGER_DIR"

    # Copy configuration files
    cp "$DEPLOYER_DIR/.deployer/genesis.json" .
    cp "$DEPLOYER_DIR/.deployer/rollup.json" .

    # Extract dispute game factory address
    GAME_FACTORY_ADDR=$(cat ../deployer/.deployer/state.json | jq -r '.opChainDeployments[0].DisputeGameFactoryProxy')

    # Check for existing prestate file
    CHALLENGER_PRESTATE_FILE=""
    if [ -d "$CHALLENGER_DIR" ]; then
        # Look for any .bin.gz file in the challenger directory
        EXISTING_PRESTATE=$(find "$CHALLENGER_DIR" -maxdepth 1 -name "*.bin.gz" -print -quit 2>/dev/null)
        if [ -n "$EXISTING_PRESTATE" ]; then
            CHALLENGER_PRESTATE_FILE=$(basename "$EXISTING_PRESTATE")
            log_info "Found existing prestate file: $CHALLENGER_PRESTATE_FILE"
        fi
    fi

    # Ensure prestate file exists
    if [ -z "$CHALLENGER_PRESTATE_FILE" ] || [ ! -f "$CHALLENGER_DIR/$CHALLENGER_PRESTATE_FILE" ]; then
        log_error "Challenger prestate file not found in $CHALLENGER_DIR/"
        log_error "Make sure generate_challenger_prestate runs before setup_challenger"
        return 1
    fi

    # Create .env file with OP_CHALLENGER prefixed variables using challenger private key
    cat > .env << EOF
OP_CHALLENGER_GAME_FACTORY_ADDRESS=$GAME_FACTORY_ADDR
OP_CHALLENGER_PRIVATE_KEY=$CHALLENGER_PRIVATE_KEY
OP_CHALLENGER_CANNON_PRESTATE=/workspace/$CHALLENGER_PRESTATE_FILE
EOF

    log_success "Challenger setup complete"
}

# Validate main .env file for docker-compose
validate_main_env() {
    log_info "Validating .env file..."

    # Load user-provided .env file
    USER_ENV_FILE="$(dirname "$0")/../.env"
    if [ ! -f "$USER_ENV_FILE" ]; then
        log_error ".env file not found. Please run 'make init' first."
        log_info "Run: make init"
        return 1
    fi

    log_info "Loading .env file..."
    set -a  # automatically export all variables
    source "$USER_ENV_FILE"
    set +a

    # Validate required environment variables
    if [ -z "$L1_RPC_URL" ]; then
        log_error "L1_RPC_URL is not set. Please set it in your .env file."
        log_info "Example: L1_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com"
        return 1
    fi

    if [ -z "$L1_BEACON_URL" ]; then
        log_error "L1_BEACON_URL is not set. Please set it in your .env file."
        log_info "Example: L1_BEACON_URL=https://ethereum-sepolia-beacon-api.publicnode.com"
        return 1
    fi

    if [ -z "$PRIVATE_KEY" ]; then
        log_error "PRIVATE_KEY is not set. Please set it in your .env file."
        log_info "Example: PRIVATE_KEY=0x..."
        return 1
    fi

    if [ -z "$SEQUENCER_PRIVATE_KEY" ]; then
        log_error "SEQUENCER_PRIVATE_KEY is not set. Please set it in your .env file."
        return 1
    fi

    if [ -z "$BATCHER_PRIVATE_KEY" ]; then
        log_error "BATCHER_PRIVATE_KEY is not set. Please set it in your .env file."
        return 1
    fi

    if [ -z "$PROPOSER_PRIVATE_KEY" ]; then
        log_error "PROPOSER_PRIVATE_KEY is not set. Please set it in your .env file."
        return 1
    fi

    if [ -z "$CHALLENGER_PRIVATE_KEY" ]; then
        log_error "CHALLENGER_PRIVATE_KEY is not set. Please set it in your .env file."
        return 1
    fi

    if [ -z "$L2_CHAIN_ID" ]; then
        log_error "L2_CHAIN_ID is not set. Please set it in your .env file."
        log_info "Example: L2_CHAIN_ID=16586"
        return 1
    fi

    # Set defaults for optional values
    P2P_ADVERTISE_IP=${P2P_ADVERTISE_IP:-127.0.0.1}

    log_success ".env file validated"
}

# Generate challenger prestate
generate_challenger_prestate() {
    log_info "Generating challenger prestate..."

    # Get the chain ID from the rollup config
    if [ -f "$DEPLOYER_DIR/.deployer/rollup.json" ]; then
        CHAIN_ID=$(jq -r '.l2_chain_id' "$DEPLOYER_DIR/.deployer/rollup.json")
    else
        log_error "Could not find rollup.json to determine chain ID"
        return 1
    fi

    log_info "Chain ID for prestate generation: $CHAIN_ID"

    # Create optimism directory for prestate generation
    OPTIMISM_DIR="$ROLLUP_DIR/optimism"
    if [ ! -d "$OPTIMISM_DIR" ]; then
        log_info "Cloning Optimism repository..."
        git clone https://github.com/ethereum-optimism/optimism.git "$OPTIMISM_DIR"
        cd "$OPTIMISM_DIR"

        # Find the latest op-program tag
        log_info "Finding latest op-program version..."
        OP_PROGRAM_TAG=$(git tag --list "op-program/v*" | sort -V | tail -1)
        if [ -z "$OP_PROGRAM_TAG" ]; then
            log_error "Could not find any op-program tags"
            return 1
        fi
        log_info "Using op-program version: $OP_PROGRAM_TAG"

        git checkout "$OP_PROGRAM_TAG"
        git submodule update --init --recursive
    else
        log_info "Optimism repository already exists, checking configuration..."
        cd "$OPTIMISM_DIR"

        # Check if we're on the correct op-program tag
        CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
        LATEST_TAG=$(git tag --list "op-program/v*" | sort -V | tail -1)

        if [ "$CURRENT_TAG" != "$LATEST_TAG" ]; then
            log_info "Updating to latest op-program version: $LATEST_TAG"
            git checkout "$LATEST_TAG"
            git submodule update --init --recursive
        else
            log_info "Already on correct op-program version: $CURRENT_TAG"
        fi
    fi

    # Copy configuration files
    log_info "Copying chain configuration files..."
    mkdir -p op-program/chainconfig/configs
    cp "$DEPLOYER_DIR/.deployer/rollup.json" "op-program/chainconfig/configs/${CHAIN_ID}-rollup.json"
    cp "$DEPLOYER_DIR/.deployer/genesis.json" "op-program/chainconfig/configs/${CHAIN_ID}-genesis-l2.json"

    # Generate prestate
    log_info "Generating reproducible prestate..."
    make reproducible-prestate

    # Extract the prestate hash from the JSON file
    PRESTATE_HASH=$(jq -r '.pre' op-program/bin/prestate-proof-mt64.json)
    if [ -z "$PRESTATE_HASH" ] || [ "$PRESTATE_HASH" = "null" ]; then
        log_error "Could not extract prestate hash from prestate-proof-mt64.json"
        return 1
    fi

    log_info "Prestate hash: $PRESTATE_HASH"

    # Move the prestate file
    log_info "Moving prestate file to challenger directory..."
    mkdir -p "$ROLLUP_DIR/challenger"
    mv "op-program/bin/prestate-mt64.bin.gz" "$ROLLUP_DIR/challenger/${PRESTATE_HASH}.bin.gz"

    # Verify the prestate file was created successfully
    if [ ! -f "$ROLLUP_DIR/challenger/${PRESTATE_HASH}.bin.gz" ]; then
        log_error "Failed to create prestate file: $ROLLUP_DIR/challenger/${PRESTATE_HASH}.bin.gz"
        return 1
    fi

    # Clean up
    cd "$ROLLUP_DIR"
    # rm -rf "$OPTIMISM_DIR"  # Uncomment to clean up after successful generation

    log_success "Challenger prestate generation complete: $ROLLUP_DIR/challenger/${PRESTATE_HASH}.bin.gz"
}

# Setup dispute monitor
setup_dispute_monitor() {
    log_info "Setting up dispute monitor..."

    mkdir -p "$DISPUTE_MON_DIR"
    cd "$DISPUTE_MON_DIR"

    # Get required addresses from state.json
    GAME_FACTORY_ADDRESS=$(jq -r '.opChainDeployments[0].DisputeGameFactoryProxy' "$DEPLOYER_DIR/.deployer/state.json")
    PROPOSER_ADDRESS=$(jq -r '.appliedIntent.chains[0].roles.proposer' "$DEPLOYER_DIR/.deployer/state.json")
    CHALLENGER_ADDRESS=$(jq -r '.appliedIntent.chains[0].roles.challenger' "$DEPLOYER_DIR/.deployer/state.json")

    log_info "Game Factory: $GAME_FACTORY_ADDRESS"
    log_info "Proposer: $PROPOSER_ADDRESS"
    log_info "Challenger: $CHALLENGER_ADDRESS"

    # Create environment file for dispute monitor
    cat > .env << EOF
# Rollup RPC Configuration
ROLLUP_RPC=http://op-node:8547

# Contract Addresses
OP_DISPUTE_MON_GAME_FACTORY_ADDRESS=$GAME_FACTORY_ADDRESS

# Honest Actors
PROPOSER_ADDRESS=$PROPOSER_ADDRESS
CHALLENGER_ADDRESS=$CHALLENGER_ADDRESS

# OP_DISPUTE_MON_NETWORK intentionally omitted — not applicable to custom chain $L2_CHAIN_ID

# Monitoring Configuration
OP_DISPUTE_MON_MONITOR_INTERVAL=10s
EOF

    # Create logs directory
    mkdir -p logs

    log_success "Dispute monitor configuration created"
    log_info "Dispute monitor will start with 'docker-compose up -d' from project root"
    log_info "To verify it's working, run: curl -s http://localhost:7300/metrics | grep -E \"op_dispute_mon_(games|ignored)\" | head -10"
}

# Add op-deployer to PATH if it exists in the workspace
if [ -f "$(dirname "$0")/../op-deployer" ]; then
    OP_DEPLOYER_PATH="$(cd "$(dirname "$0")/.." && pwd)/op-deployer"
    export PATH="$(dirname "$OP_DEPLOYER_PATH"):$PATH"
    log_info "Added op-deployer to PATH: $OP_DEPLOYER_PATH"
fi

# Main execution
main() {
    log_info "Starting OP Stack L2 Rollup deployment..."
    log_info "L2 Chain ID: $L2_CHAIN_ID"
    log_info "L1 Chain ID: $L1_CHAIN_ID"

    # Clean start - remove any existing deployer directory
    log_info "Cleaning up any existing deployment..."
    rm -rf "$DEPLOYER_DIR"
    mkdir -p "$DEPLOYER_DIR"

    validate_main_env
    check_prerequisites
    derive_addresses_from_keys
    init_deployer
    update_intent
    deploy_contracts
    generate_config
    setup_sequencer
    setup_batcher
    setup_proposer
    generate_challenger_prestate
    setup_challenger
    setup_dispute_monitor

    log_success "OP Stack L2 Rollup deployment complete!"
    log_info "Run 'docker-compose up -d' to start all services (including dispute monitor)"
    log_info "Dispute monitor metrics: http://localhost:7300/metrics"
}

# Handle command line arguments for standalone function calls
if [ $# -gt 0 ]; then
    case "$1" in
        "prestate"|"generate-prestate")
            log_info "Running standalone prestate generation..."

            # Set up required variables for standalone execution
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            ROLLUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
            DEPLOYER_DIR="$ROLLUP_DIR/deployer"

            generate_challenger_prestate
            exit $?
            ;;
        *)
            log_error "Unknown command: $1"
            log_info "Available commands: prestate"
            exit 1
            ;;
    esac
fi

# Run main function if no arguments provided
main "$@"
