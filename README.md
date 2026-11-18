# Agent BlackBox

**One black box a day. Only Agent ID holders can open it.**

Agent BlackBox is a daily on-chain black-box game on BNB Chain, built around
Binance **Agent ID** as its core access and identity layer. It was created for
the Binance Wallet Agent ID Hackathon.

**Play:** https://haff981.github.io/agent-blackbox/

## How it works

1. **Seal** — if your wallet holds an Agent ID, you can seal one box per day.
   Sealing locks in a block two blocks in the future.
2. **Reveal** — after that block, reveal your box. Your rarity is derived from
   `keccak256(blockhash(targetBlock), player, epoch)`: unknowable in advance,
   impossible to rig, and verifiable by anyone on-chain.
3. **Collect** — five rarities (Common 50% / Rare 30% / Epic 15% /
   Legendary 4% / Mythic 1%) award points. An on-chain top-10 leaderboard and
   soulbound milestone badges (First Mythic, 7-day streak, Full Set) track
   your progress. If a target block's hash expires (>256 blocks), the box is
   automatically re-targeted instead of being lost.

## Agent ID integration

- **Access control:** the game contract checks the Agent ID registry
  (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) `balanceOf` on every play.
  Holding an Agent ID literally decides who can play and how often.
- **Self-verification:** the website lets a user verify their *own* `.ai`
  name — the name is hashed (keccak256) to its token ID and the registry's
  `ownerOf` is compared only against the user's own connected wallet. It is
  not a lookup tool for other people's wallets.
- **Identity-bound progress:** points, streaks, collections and badge NFTs
  are all recorded against the player's Agent ID wallet.

## Contracts (BNB Chain mainnet)

| Contract | Address |
|---|---|
| AgentBlackBox (game) | `0x4Ebb70DC293dC7fDe481886cb08f18e7d4F9c308` |
| BlackBoxBadge (soulbound NFT) | `0x20b2A08864BdfaBfF47A1CF03E72beC02EbE58aB` |

Source: [`contracts/AgentBlackBox.sol`](contracts/AgentBlackBox.sol), verified
with an exact match on Sourcify for both contracts
([game](https://sourcify.dev/#/lookup/0x4Ebb70DC293dC7fDe481886cb08f18e7d4F9c308),
[badge](https://sourcify.dev/#/lookup/0x20b2A08864BdfaBfF47A1CF03E72beC02EbE58aB)).

The contracts have **no owner, no admin functions, no upgrade path and no
custody** — they never touch user assets. Playing is free; you only pay
network gas.

## Local development

```bash
npm install
node scripts/compile.js   # compile contracts with solc-js
node scripts/test.js      # 17-check local EVM test suite (ganache)
```
