# Xhavic Blockchain — OP Stack L2 on Ethereum Sepolia

> A production-grade Layer 2 rollup built on the [OP Stack](https://docs.optimism.io/), settling on Ethereum Sepolia. Fully operational with sequencing, batch submission, output proposals, fault proving, and dispute monitoring — all running via Docker.

---

## Live Network

| Property | Value |
|---|---|
| **Chain Name** | Xhavic Blockchain |
| **Chain ID** | `16585` |
| **L1 Network** | Ethereum Sepolia (`11155111`) |
| **RPC Endpoint** | `https://testrpc.xhaviscan.com` |
| **WebSocket** | `wss://testrpc.xhaviscan.com` |
| **Block Explorer** | [https://xhaviscan.com](https://xhaviscan.com) |
| **Data Availability** | EIP-4844 Blobs (Ethereum Sepolia) |
| **Fault Proof Stage** | Stage 0 — Permissioned |

### Add to MetaMask

| Field | Value |
|---|---|
| Network Name | Xhavic Blockchain |
| RPC URL | `https://testrpc.xhaviscan.com` |
| Chain ID | `16585` |
| Currency Symbol | `ETH` |
| Block Explorer URL | `https://xhaviscan.com` |

### Quick Connect (no local node needed)

```bash
# Test public RPC — get current block number
curl -s -X POST https://testrpc.xhaviscan.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

# Confirm Chain ID (should return 0x40c9 = 16585)
curl -s -X POST https://testrpc.xhaviscan.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq
```

---

## Architecture

```
                        Ethereum Sepolia (L1)
                               │
              ┌────────────────┼────────────────┐
              │                │                │
         op-batcher       op-proposer     op-challenger
     (submits tx blobs) (submits output  (monitors &
              │            roots to L1)   challenges roots)
              │                │                │
              └────────────────┼────────────────┘
                               │
                          op-node (L2)
                    (consensus / sequencer)
                               │
                          op-geth (L2)
                    (execution engine / EVM)
                               │
                        Public RPC / WS
                  testrpc.xhaviscan.com : 8545 / 8546
```

### Services

| Service | Image | Role |
|---|---|---|
| `op-geth` | `op-geth:v1.101604.0` | L2 execution engine (EVM) |
| `op-node` | `op-node:v1.16.4` | L2 consensus + sequencer |
| `op-batcher` | `op-batcher:v1.16.3` | Submits L2 tx batches to L1 via blobs |
| `op-proposer` | `op-proposer:v1.10.0` | Submits L2 output roots to L1 |
| `op-challenger` | `op-challenger:v1.7.0` | Monitors and challenges invalid roots |
| `dispute-mon` | `op-dispute-mon:v1.4.2-rc.1` | Tracks dispute game health |

---

## Deployed Contracts (Sepolia)

| Contract | Address |
|---|---|
| `SystemConfigProxy` | `0xc955ecdae08fb59f2844cafa4a78cfdf513f7540` |
| `DisputeGameFactoryProxy` | `0x5ce7e9d6acf3ccdc490bab6a2e5bcfad8fa45f54` |
| `PermissionedDisputeGameImpl` | `0xb3413582f1941e01e734d015f0d687b790149cc4` |
| `Batch Inbox` | `0x0020603978f12196cc325f7887b63172eac1b732` |

### Role Addresses

| Role | Address |
|---|---|
| Admin / Deployer | `0x52a283682Aa97d7Df3D4721084decADA170a7813` |
| Sequencer (Unsafe Block Signer) | `0xf37E1174960075E38207aB049516d01C1aBdd808` |
| Batcher | `0xc88263cCD2B147e31313918A3F55904a2753a7B0` |
| Proposer | `0x929f950c6DD3DD4A6E69337c69A469517187c5af` |
| Challenger | `0x15426fb64a89BbD556FEC850fFe180a40bBa2814` |

---

## Prerequisites

| Dependency | Version | Install |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) | 24+ | [docs.docker.com](https://docs.docker.com/get-docker/) |
| [Docker Compose](https://docs.docker.com/compose/install/) | v2+ | Included with Docker Desktop |
| [jq](https://stedolan.github.io/jq/) | any | `apt install jq` / `brew install jq` |
| [curl](https://curl.se/) | any | Pre-installed on most systems |

**Minimum system resources:** 4 CPU cores, 8 GB RAM, 50 GB disk

---

## Running Locally

### 1. Clone the repository

```bash
git clone <repo-url>
cd NewL2chain
```

### 2. Configure environment

```bash
cp .example.env .env
```

Open `.env` and fill in your values:

```bash
# L1 RPC — get a free key from https://alchemy.com or https://infura.io
L1_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
L1_BEACON_URL="https://ethereum-sepolia-beacon-api.publicnode.com"

# Five separate wallets — each needs Sepolia ETH for gas
# Generate with: cast wallet new
PRIVATE_KEY="your_deployer_private_key"
SEQUENCER_PRIVATE_KEY="your_sequencer_private_key"
BATCHER_PRIVATE_KEY="your_batcher_private_key"
PROPOSER_PRIVATE_KEY="your_proposer_private_key"
CHALLENGER_PRIVATE_KEY="your_challenger_private_key"

# Your machine's public IP — run: curl ifconfig.me
P2P_ADVERTISE_IP="YOUR_PUBLIC_IP"

# Your desired L2 Chain ID (must be unique)
L2_CHAIN_ID="16585"
```

> **Sepolia ETH needed:** Batcher (~1 ETH), Proposer (~0.5 ETH), Challenger (~0.5 ETH), Deployer (~0.5 ETH). Get free Sepolia ETH from [sepoliafaucet.com](https://sepoliafaucet.com).

### 3. Deploy L1 contracts and set up services

```bash
# Download op-deployer binary
make download

# Deploy contracts to Sepolia and configure all services
make setup
```

This script:
- Deploys all OP Stack contracts to Sepolia
- Generates `genesis.json` and `rollup.json`
- Initializes op-geth datadir
- Generates JWT secret
- Creates service-specific `.env` files

### 4. Start all services

```bash
make up
```

### 5. Verify everything is running

```bash
make status
```

Expected output — all 6 containers should show `(healthy)`:

```
NAME            STATUS
dispute-mon     Up (healthy)
op-batcher      Up (healthy)
op-challenger   Up (healthy)
op-geth         Up (healthy)
op-node         Up (healthy)
op-proposer     Up (healthy)
```

### 6. Test the RPC

```bash
# Get current block number
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

# Get chain ID
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' | jq
```

---

## Make Commands

```bash
make help        # List all available commands
make setup       # Deploy contracts and configure services
make up          # Start all services
make down        # Stop all services
make logs        # Stream logs from all services
make logs-op-node    # Stream logs from a specific service
make status      # Show health of all containers
make restart     # Restart all services
make test-l2     # Test L2 RPC connectivity
make test-l1     # Test L1 RPC connectivity
make clean       # Remove containers and volumes
make reset       # Full reset — removes all data (⚠️ destructive)
```

---

## Port Reference

| Port | Service | Description | Exposed |
|---|---|---|---|
| `8545` | op-geth | HTTP JSON-RPC | Public |
| `8546` | op-geth | WebSocket RPC | Public |
| `8551` | op-geth | Engine API (JWT) | Internal only |
| `8547` | op-node | Admin RPC | Internal only |
| `9222` | op-node | P2P block gossip | Public |
| `6060` | op-geth | Metrics | Internal only |
| `7301` | op-node | Metrics | Internal only |
| `7302` | op-batcher | Metrics | Internal only |
| `7303` | op-proposer | Metrics | Internal only |
| `7304` | op-challenger | Metrics | Internal only |
| `7300` | dispute-mon | Metrics | Internal only |

---

## Directory Structure

```
NewL2chain/
├── docker-compose.yml          # All 6 service definitions
├── .env                        # Secrets and config (never commit)
├── .example.env                # Safe template to copy from
├── Makefile                    # Management commands
├── scripts/
│   ├── setup-rollup.sh         # Full deployment automation
│   └── download-op-deployer.sh # Downloads op-deployer binary
├── sequencer/                  # op-geth + op-node workspace
│   ├── genesis.json            # L2 genesis block config
│   ├── rollup.json             # op-node rollup config
│   └── op-geth-data/          # Chain data (Docker volume)
├── deployer/
│   ├── .deployer/
│   │   ├── state.json          # Deployed contract addresses
│   │   ├── intent.toml         # Deployment parameters
│   │   ├── genesis.json        # Genesis (canonical copy)
│   │   └── rollup.json         # Rollup config (canonical copy)
│   └── addresses/              # Individual address files
├── batcher/                    # op-batcher config
├── proposer/                   # op-proposer config
├── challenger/                 # op-challenger config + cannon prestate
└── dispute-mon/                # op-dispute-mon config
```

---

## Monitoring Logs

```bash
# Watch all services
docker compose logs -f

# Watch individual services
docker compose logs -f op-geth
docker compose logs -f op-node
docker compose logs -f batcher
docker compose logs -f proposer
docker compose logs -f challenger
docker compose logs -f dispute-mon
```

**What healthy logs look like:**

| Service | Expected log message |
|---|---|
| op-geth | `Chain head was updated number=XXXXX` |
| op-node | `Sequencer inserted block` + `Record safe head` |
| op-batcher | `Added L2 block to local state` + `Building Blob transaction` |
| op-proposer | `Proposing output root` (after L1 sync) |
| op-challenger | `Got sync status` every 60s |
| dispute-mon | `Completed monitoring update games=0 failed=0` |

---

## Troubleshooting

### Container not starting

```bash
docker compose logs <service-name> --tail=50
```

### op-geth stays unhealthy

```bash
# Check if datadir is initialized
docker exec op-geth ls /workspace/op-geth-data/geth/chaindata
```

If missing — the genesis init failed. Check `L1_RPC_URL` and re-run `make setup`.

### op-batcher shows `403 Forbidden`

The `HTTP_VHOSTS` in `.env` may be missing the `op-geth` Docker hostname:
```bash
HTTP_VHOSTS=yourdomain.com,localhost,op-geth
```

### op-proposer stuck on "behind target"

This is normal on first start or after downtime — the node is syncing L1 history. It will auto-start proposing once caught up. Monitor progress:
```bash
docker compose logs proposer | grep "current_l1"
```

### Reset everything and start fresh

```bash
make reset    # ⚠️ Destroys all chain data
make setup
make up
```

---

## Security

This deployment has been reviewed against the **QuillAudits OP Stack Security Checklist**. Status of all findings:

| # | Severity | Finding | Status |
|---|---|---|---|
| 01 | Critical | Engine API (port 8551) exposed | Fixed |
| 02 | Critical | admin/debug namespaces + wildcard CORS | Fixed |
| 03 | Critical | op-node admin RPC (port 8547) exposed | Fixed |
| 04 | High | Private keys in CLI arguments | Fixed |
| 05 | High | Permissionless fault proofs (Stage 1) | Stage 0 — permissioned (see note below) |
| 06 | High | P2P eclipse / admin_removePeer | Fixed |
| 07 | Low | minBaseFee = 0 | Fixed |
| 08 | Medium | `--allow-non-finalized` in proposer | Fixed |
| 09 | Medium | `sequencer.max-safe-lag` too high | Fixed |

> **Stage 0 — Permissioned Fault Proofs:** Xhavic Blockchain currently operates at Stage 0. Dispute games are permissioned — only the designated Challenger role (`0x15426fb64a89BbD556FEC850fFe180a40bBa2814`) can submit and resolve challenges. Public/permissionless fault proofs (Stage 1) are not yet active. Users should be aware that fraud proof verification is not fully trustless at this stage.

**Key security measures in place:**
- Engine API (8551) never published — internal Docker network only
- RPC exposes only `eth, net, web3` — no `admin`, `debug`, `txpool`, `miner`, or `personal`
- All private keys loaded via environment variables, never passed as CLI flags
- JWT rotated and secured with `chmod 600`
- CORS locked to `https://xhaviscan.com`
- op-node admin RPC (8547) never published externally

---

## License

MIT — see [LICENSE](LICENSE)
