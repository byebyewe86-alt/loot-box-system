# Loot Box System with On-Chain Randomness

A Web3 gaming smart contract built on **Sui Move** for the SUI Coders Hackathon.

## Overview
Players purchase mystery loot boxes using fungible tokens and receive randomly generated NFT items with varying rarity levels. The randomness is **verifiable, tamper-proof, and fair** using Sui's native on-chain randomness beacon.

## Features

### Core (Required)
-  **Secure Randomness** — Uses `sui::random` with `entry` function protection to prevent frontrunning attacks
-  **Purchase System** — Players pay tokens to receive an unopened LootBox object
-  **NFT Minting** — Random GameItem NFTs with name, rarity, power, and flavor text
-  **4 Rarity Tiers** — Common (60%), Rare (25%), Epic (12%), Legendary (3%)
-  **Item Lifecycle** — Transfer and burn capabilities
-  **Admin Controls** — Update rarity weights with AdminCap

### Bonus (Extra Features)
-  **Pity System** — Guaranteed Legendary after 30 non-legendary opens (tracked per-user via dynamic fields)
-  **Item Fusion** — Combine 2 same-rarity items into 1 stronger fused item
-  **Streak Bonus** — Open 5+ boxes consecutively for improved drop rates
-  **Item Durability** — Items degrade on use and can be repaired
-  **On-Chain Leaderboard** — Tracks top 5 most powerful items ever minted

## 📊 Rarity Distribution

| Tier      | Drop Rate | Power Range |
|-----------|-----------|-------------|
| Common    | 60%       | 1 - 10      |
| Rare      | 25%       | 11 - 25     |
| Epic      | 12%       | 26 - 40     |
| Legendary | 3%        | 41 - 50     |

##  Test Results
```
Total tests: 11 | Passed: 11 | Failed: 0 
```
- ✅ test_init_game
- ✅ test_purchase_loot_box
- ✅ test_purchase_insufficient_payment
- ✅ test_open_loot_box
- ✅ test_transfer_item
- ✅ test_burn_item
- ✅ test_update_rarity_weights
- ✅ test_update_weights_invalid_sum
- ✅ test_item_durability
- ✅ test_item_fusion
- ✅ test_leaderboard

## Project Structure
```
loot_box/
├── sources/
│   └── loot_box.move      # Main smart contract
├── tests/
│   └── loot_box_tests.move # 11 unit tests
└── Move.toml               # Package config
```

##  How to Run
```bash
# Build
sui move build

# Test
sui move test
```

## Why entry (not public) for open_loot_box?
The `open_loot_box` function is marked `entry` instead of `public` intentionally. This prevents other smart contracts from calling it and inspecting the random value before deciding whether to proceed — blocking frontrunning attacks on the randomness.

##  Built With
- Sui Move
- sui::random (on-chain randomness)
- sui::dynamic_field (pity system + streak tracking)
- sui::event (rich event emission)
