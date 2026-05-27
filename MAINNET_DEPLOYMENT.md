# Xhavic Blockchain — Mainnet Deployment Requirements
### Prepared for: Client
### Prepared by: Xhavic Blockchain Team
### Date: May 2026

---

## Executive Summary

Xhavic Blockchain is a production-grade Layer 2 blockchain built on the OP Stack, currently live on Ethereum Sepolia testnet (Chain ID: 16585). This document covers everything needed from the client side to deploy on **Ethereum Mainnet**.

---

## Table of Contents

1. [Current Status](#1-current-status)
2. [ETH Requirements](#2-eth-requirements)
3. [Security Requirements](#3-security-requirements)
4. [Pre-Launch Checklist](#4-pre-launch-checklist)
5. [Deployment Timeline](#5-deployment-timeline)
6. [Ongoing Operations](#6-ongoing-operations)
7. [Risk & Cautions](#7-risk--cautions)
8. [Client Action Items](#8-client-action-items)

---

## 1. Current Status

| Item | Status |
|---|---|
| Chain live on Sepolia testnet | ✅ Running |
| Chain ID 16585 | ✅ Active |
| Block explorer (xhaviscan.com) | ✅ Live |
| Public RPC (testrpc.xhaviscan.com) | ✅ Live |
| Security audit — QuillAudits | ✅ 8 of 9 findings fixed |
| All 6 services healthy | ✅ Confirmed |
| Mainnet deployment | ⏳ Pending client approval |

---

## 2. ETH Requirements

All wallets must be funded **before** deployment begins.

| Wallet | Amount | Purpose |
|---|---|---|
| Deployer | 3–5 ETH | Deploys ~15 contracts to mainnet (one-time) |
| Batcher | 5 ETH | Submits L2 transactions to L1 (ongoing) |
| Proposer | 2 ETH | Submits state roots every 30 minutes |
| Challenger | 5 ETH | Challenges invalid state roots (10.5-day window: 7-day proof maturity + 3.5-day finality delay) |
| Sequencer | 0.5 ETH | Block signing |
| Emergency buffer | 2 ETH | Gas spikes and unexpected costs |
| **Total** | **~17–20 ETH** | |

> The batcher is the highest ongoing cost — it submits to L1 every few minutes. Client tops up the batcher monthly based on usage.

---

## 3. Security Requirements

### Gnosis Safe Multisig — 1 Required

**ProxyAdmin Safe** controls all smart contract upgrades. A single compromised key here could drain all bridge funds — it must require multiple approvals.

- Minimum 2-of-3 signers from the founding team
- Free setup at [https://safe.global](https://safe.global) → Ethereum Mainnet
- Provide the Safe address to the development team before deployment begins

### Security Audits

| Audit | Status |
|---|---|
| OP Stack configuration (QuillAudits) | ✅ 8/9 fixed |
| Bridge UI and frontend | ⏳ Required before mainnet |
| Bug bounty program (Immunefi) | ⏳ Must be live before public launch |

---

## 4. Pre-Launch Checklist

### Client Must Complete

- [ ] Create ProxyAdmin Gnosis Safe (2-of-3 minimum) — provide address to team
- [ ] Generate 5 wallet addresses (one per role) — provide all 5 to the development team
- [ ] Arrange ~17–20 ETH distributed across the 5 wallets (team provides exact breakdown)
- [ ] Provision 5 servers and provide SSH root access to the development team
- [ ] Confirm DNS access for xhaviscan.com and testrpc.xhaviscan.com
- [ ] Create Cloudflare account — add both domains
- [ ] Approve budget for bridge UI security audit

### Development Team Handles

- [ ] Configure all 5 servers (firewall, Docker, Nginx, SSL, Cloudflare)
- [ ] Sync L1 Ethereum node (3–5 days)
- [ ] Deploy all OP Stack contracts to Ethereum mainnet
- [ ] Configure proxyd and op-conductor
- [ ] Start all 6 chain services and verify healthy
- [ ] Set up Grafana dashboards and Alertmanager (Telegram/PagerDuty)
- [ ] Deploy and index Blockscout
- [ ] Full bridge and RPC testing + load test
- [ ] Submit Chain ID 16585 to chainlist.org
- [ ] Final health check before public announcement

---

## 5. Deployment Timeline

```
Month 1 — Infrastructure & Deployment
  Week 1  Client completes initial actions (Safe, wallets, servers, SSH access)
  Week 2  Team configures all 5 servers, L1 node begins syncing (3–5 days)
  Week 3  Sequencer + op-conductor set up, all services connected and verified
  Week 4  L1 contracts deployed to mainnet, all 6 services live and healthy

Month 2 — Testing & Launch
  Week 5  Monitoring stack (Grafana, Loki, Alertmanager) configured
          Bridge UI security audit begins
  Week 6  Client funds all 5 wallets. Blockscout begins indexing.
          proxyd rate limiting and method whitelist configured
  Week 7  Audit fixes applied. Full bridge test, RPC test, load test
  Week 8  Bug bounty live. Status page live. Final sign-off.
          Public launch — announcement + submit to L2Beat 🚀
```

**Total: ~8 weeks from client completing initial actions**

---

## 6. Ongoing Operations

### Daily (Automated)
- All 6 services monitored 24/7 — team responds to alerts
- Batcher ETH balance alert at < 1 ETH — team notifies client to top up

### Monthly (Client)
- Top up batcher wallet with ETH
- Top up proposer wallet if below 0.5 ETH

### Monthly (Team)
- Review server disk usage (chain grows ~50–100 GB/month)
- Docker security updates
- Blockscout database size review

### Emergency Response
- Target recovery: under 15 minutes for services, under 30 minutes for sequencer
- Status communicated to users via status page during any downtime

---

## 7. Risk & Cautions

| Risk | Impact | Prevention |
|---|---|---|
| Private key compromise | Funds stolen | Env vars on firewalled servers — never commit to git |
| Sequencer server down | Chain halts | op-conductor + 24/7 monitoring |
| Batcher runs out of ETH | Batches stop posting to L1 | Team alerts at 1 ETH — client tops up |
| L1 node falls behind | Batcher/proposer use stale data | Monitoring alert; Alchemy kept as backup |
| DDoS on public RPC | RPC unresponsive | Cloudflare + proxyd rate limiting |
| Bridge vulnerability | User funds at risk | Security audit + bug bounty before launch |
| Disk full on sequencer | Chain database corruption | Team monitors — expand before 80% full |

---

## 8. Client Action Items

Everything below **must be provided by the client** before the team can begin.

| # | Action | Where |
|---|---|---|
| 1 | Create ProxyAdmin Gnosis Safe (2-of-3) | [safe.global](https://safe.global) → Ethereum Mainnet |
| 2 | Generate 5 wallet addresses and provide to team | `cast wallet new` or any wallet tool |
| 3 | Fund wallets with ~17–20 ETH total | Team provides per-wallet breakdown |
| 4 | Provision 5 servers and provide SSH root access | Any cloud/dedicated provider |
| 5 | Add both domains to Cloudflare | [cloudflare.com](https://cloudflare.com) |
| 6 | Approve bridge UI audit budget | Team will recommend auditor |

---

*— Xhavic Blockchain Development Team*
