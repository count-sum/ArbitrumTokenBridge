# Arbitrum Cross-Chain Token Bridge


## Overview
This project implements a custom token bridge between Ethereum Layer 1 (Sepolia testnet) and Arbitrum Layer 2 (Arbitrum Sepolia testnet). The bridge allows for seamless token transfers between the two networks using a custom gateway and token implementation.


## Features
- Custom ERC20 token deployment on both L1 and L2
- Custom gateway contracts for cross-chain token transfers
- Support for token minting, burning, and bridging
- Deployment and setup script for easy token bridge configuration


## Prerequisites

Before getting started, ensure you have the following installed:

- Node.js (v18 or later)
- pnpm (Package manager)
- Ethereum wallet with testnet ETH (Sepolia * Arbitrum Sepolia)


## Installation

1. Clone the repository:
```bash
git clone https://github.com/count-sum/ArbitrumTokenBridge.git
```

2. Install dependencies:
```bash
pnpm i
```

3. Set up environment variables:
```bash
cp .env.example .env
```

4. Update `.env` with :

```
- PRIVATE_KEY (starts with 0x)
- L1_CHAIN_RPC=
- L2_CHAIN_RPC=
- TOKEN_SUPPLY_AMOUNT=
- TOKEN_BRIDGE_AMOUNT=
```

5. Run the following command to deploy the token and gateway contracts:

```
npx hardhat scripts/setupAndDeploy.ts
```

