
# 🧠 zkPredict – Anonymous Prediction Market on Aleo

**Your prediction, your privacy.**

zkPredict is a fully anonymous, decentralized prediction market platform built using **Zero-Knowledge Proofs (ZKPs)** and the **Leo programming language** on the **Aleo blockchain**. This project was developed during a hackathon by the AlphaBetaZK team to explore private betting markets where users can bet on outcomes **without revealing their identities or choices**.

## 🔐 Why zkPredict?

Current prediction markets (e.g., Polymarket, Augur) lack **privacy by default**:
- Your bets are public.
- Your wallet is trackable.
- You leave a footprint.

**zkPredict solves this** by ensuring that:
- All bets are private.
- No one can see how or what you bet on.
- Rewards are claimed with ZK-proofs, not addresses.

## ⚙️ Tech Stack

| Component        | Description                                     |
|------------------|-------------------------------------------------|
| **Leo**          | Domain-specific language for ZK apps on Aleo.   |
| **Aleo**         | Privacy-first L1 blockchain using ZKPs.         |
| **SnarkOS**      | Node to interact with Aleo testnet/devnet.      |
| **ZK-Proofs**    | Ensures anonymous bets and reward claims.       |

## 🏗️ Project Structure

\`\`\`
prediction_market_leo/
├── src/
│   └── main.leo               # Main Leo contract logic
├── build/                     # Compiled Aleo bytecode
├── inputs/                    # Input files for testing
├── README.md                  # This file
└── .aleo/                     # Aleo deployment metadata
\`\`\`

## 📦 Features

✅ Create a new prediction market  
✅ Mint YES/NO tokens dynamically  
✅ Bet privately on outcomes  
✅ Close markets after end date  
✅ Claim rewards anonymously  
✅ Refund invalid or canceled markets  
✅ AMM-style liquidity with token pool logic (ongoing)  

## 🧠 Smart Contract Overview

### `initialize_amm_market`
Creates a new prediction market and mints `YES` / `NO` tokens.

\`\`\`leo
async transition initialize_amm_market(...)
\`\`\`

### `finalize_initialize_amm_market`
Registers the market with metadata (question hash, options, deadlines).

### `bet_on_yes` / `bet_on_no`
Allows users to place private bets using minted tokens.

### `close_market`
Admin function to close the market and register the winning outcome.

### `claim_reward`
User proves their bet and claims their reward with a ZK-proof.

## 🧪 How to Run Locally

### Prerequisites

- [Install Aleo tooling](https://developer.aleo.org/aleo/getting-started/installation)
- Clone the repo:

\`\`\`bash
git clone https://github.com/alphabetaZK/prediction_market_leo
cd prediction_market_leo
\`\`\`

### Build the Leo Program

\`\`\`bash
leo build
\`\`\`

### Run a Function

\`\`\`bash
leo run initialize_amm_market 123field 456field ...
\`\`\`

### Deploy to Aleo Testnet

```bash
snarkos developer deploy ./build/prediction_market.aleo \
  --private-key <YOUR_PRIVATE_KEY> \
  --query https://api.explorer.provable.com/v1 \
  --broadcast https://api.explorer.provable.com/v1/testnet/transaction/broadcast \
  --network 1
```

## 🔒 Privacy by Design

- We never store public bet data on-chain.
- All tokens are handled with shielded ZK logic.
- Users reveal nothing beyond the final proof when claiming.

## 👥 Team

- **Ramzy** – Leo Dev, smart contracts  
- **Salim** – Front  
- **Lina** – UI/UX & integrations  
- **Abdellahi** – Buisness & game theory  

## 🌐 License

MIT License – Use freely, fork, contribute. Let’s build private futures.

## 📩 Contact / Support

- Contact us via [GitHub Issues](https://github.com/alphabetaZK/prediction_market_leo/issues)
