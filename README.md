# 🔐 FHE MENTORSHIP

A Fhe Mentorship Project

**Contract Details:**
- **Mentorship Contract:** `Mentorship.sol` with USDC address `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238`
- **Network:** Sepolia testnet (Chain ID: 11155111)

### **Option 2: Development Environment**

Clone and run the full development environment:

```bash
# 1. Clone repository
git clone https://github.com/your-username/fhevm-react-template.git
cd fhevm-react-template

# 2. Install dependencies
pnpm install

# 3. Build SDK
pnpm sdk:build

# 4. Run showcase
pnpm --filter react-showcase start      # React on :3000
pnpm --filter nextjs-showcase dev      # Next.js on :3001
pnpm --filter vue-showcase dev         # Vue on :3003
pnpm --filter node-showcase explorer   # Interactive CLI mode (recommended)
pnpm --filter node-showcase start      # HTTP server mode
pnpm --filter node-showcase cli        # Non-interactive CLI mode


```