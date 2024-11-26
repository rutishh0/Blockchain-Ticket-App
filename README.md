# 🎫 Blockchain Event Ticketing System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-blue)](https://docs.soliditylang.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-%5E5.0.0-blue)](https://www.typescriptlang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-2.19.1-yellow)](https://hardhat.org)

A decentralized event ticketing platform built on blockchain technology, designed to eliminate scalping, ensure fair pricing, and provide transparent ticket distribution.

## 🎯 Key Features

- **Anti-Scalping Measures**: Smart contract-enforced price controls and transfer restrictions
- **Automated Refunds**: Instant refunds for cancelled events
- **Fair Distribution**: Transparent ticket allocation system
- **Secure Authentication**: Blockchain-based ticket verification
- **Dynamic Pricing Controls**: Zone-based pricing with automated price management

## 🏗️ Technology Stack

- **Smart Contracts**: Solidity
- **Testing Framework**: Hardhat & Chai
- **Frontend**: React.js & ethers.js
- **Blockchain**: Ethereum (Permissioned Network)

## 🚀 Quick Start

/Summary TBA/

### Prerequisites

```bash
node >= 14.0.0
npm >= 6.14.0
```

### Installation

1. Clone the repository
```bash
git clone https://github.com/rutishh0/Blockchain-Ticket-App.git
cd Blockchain-Ticket-App
```

2. Install dependencies
```bash
npm install
```

3. Run tests
```bash
npx hardhat test
```

4. Start local node
```bash
npx hardhat node
```

5. Deploy contracts
```bash
npx hardhat run scripts/deploy.ts --network localhost
```

## 📁 Project Structure

```
blockchain-ticketing-system/
├── contracts/              # Smart contract source files
│   ├── core/              # Core contract implementations
│   └── interfaces/        # Contract interfaces
├── scripts/               # Deployment and task scripts
├── test/                  # Test files
├── frontend/              # React.js frontend application
└── docs/                  # Documentation
```

## 🧪 Testing

Run the test suite:
```bash
# Run standard tests
npm test

# Generate coverage report
npm run coverage
```

## 📜 Smart Contracts

### Core Contracts

- **TicketFactory**: Handles ticket creation and management
- **EventManager**: Manages event creation and settings
- **RefundEscrow**: Handles secure payment and refund logic

## 🔐 Security Features

- Automated vulnerability scanning
- Test coverage requirements
- Multi-signature requirements for critical operations
- Time-locked upgrades

## 🤝 Contributing

This is a coursework project for COMP0163 Blockchain Technologies. Contributing members of this team belong to Group B.

### Team Members
- Rutishkrishna Srinivasaraghavan
- Alex Plumbridge
- Santiago De Simone
- Gavin Hor
- Zhanna Olzhabayeva

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🌟 Acknowledgments

- COMP0163 Course Team
- [Ethereum Community](https://ethereum.org/)
- [OpenZeppelin](https://openzeppelin.com/) for secure contract implementations
- [Yoda](https://youtu.be/BQ4yd2W50No?t=18) for sage advice on debugging ("Do or do not, there is no try").

---
<div align="center">
Made with ❤️ by Blockchain Ticket App Team
</div>