import { createPublicClient, createWalletClient, http, parseEther, parseUnits } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { sepolia } from 'viem/chains';
import { fileURLToPath } from 'url';
import { join, dirname } from 'path';

/**
 * PYRE PROTOCOL - FRONTEND INTEGRATION REFERENCE
 * 
 * This file contains the necessary addresses, ABIs, and functions to perform
 * swaps for the PYRE token on Uniswap v4 (Sepolia).
 */

// Load environment variables from .env file
try {
  // @ts-ignore - loadEnvFile is available in Node 20.12.0+
  if (typeof process.loadEnvFile === 'function') {
    // @ts-ignore
    process.loadEnvFile();
  }
} catch (e) {
  console.warn('Note: .env file not found or could not be loaded automatically.');
}

// --- DEPLOYED ADDRESSES ---
export const PYRE_TOKEN = '0x4765344c933018a559f77f00658f6c55382f73e4';
export const PYRE_HOOK = '0xe9a33cdcd454afbf1a12475059871d9d95fcbff8';
export const SWAP_ROUTER = '0x00000000000044a361Ae3cAc094c9D1b14Eece97';
export const POOL_MANAGER = '0xe03a1074c86cfedd5c142c4f04f1a1536e203543';

// --- POOL CONFIGURATION ---
export const POOL_FEE = 3000; // 0.3%
export const TICK_SPACING = 60;

// --- ABIs ---
export const PYRE_TOKEN_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

export const SWAP_ROUTER_ABI = [
  {
    name: 'swapExactTokensForTokens',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      { name: 'amountIn', type: 'uint256' },
      { name: 'amountOutMin', type: 'uint256' },
      { name: 'zeroForOne', type: 'bool' },
      {
        name: 'poolKey',
        type: 'tuple',
        components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' },
        ],
      },
      { name: 'hookData', type: 'bytes' },
      { name: 'receiver', type: 'address' },
      { name: 'deadline', type: 'uint256' },
    ],
    outputs: [{ name: 'delta', type: 'int128[]' }],
  },
] as const;

// --- HELPERS ---

/**
 * Constructs the PoolKey for the PYRE/ETH pool.
 * currency0 is always the lower address. In our case, ETH (address(0)) is currency0.
 */
export const getPoolKey = () => ({
  currency0: '0x0000000000000000000000000000000000000000' as `0x${string}`,
  currency1: PYRE_TOKEN as `0x${string}`,
  fee: POOL_FEE,
  tickSpacing: TICK_SPACING,
  hooks: PYRE_HOOK as `0x${string}`,
});

/**
 * BUY PYRE (ETH -> PYRE)
 */
export async function buyPyre(walletClient: any, amountInEth: string, account: any) {
  const amountIn = parseEther(amountInEth);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);

  console.log(`Swapping ${amountInEth} ETH for PYRE...`);
  const hash = await walletClient.writeContract({
    address: SWAP_ROUTER,
    abi: SWAP_ROUTER_ABI,
    functionName: 'swapExactTokensForTokens',
    args: [
      amountIn,
      0n, 
      true, // ETH -> PYRE
      getPoolKey(),
      '0x',
      account.address,
      deadline,
    ],
    value: amountIn,
    chain: sepolia,
    account,
  });
  console.log(`Transaction sent: ${hash}`);
  return hash;
}

/**
 * SELL PYRE (PYRE -> ETH)
 */
export async function sellPyre(walletClient: any, amountInPyre: string, account: any, publicClient: any) {
  const amountIn = parseUnits(amountInPyre, 18);
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 60 * 20);

  console.log(`Approving ${amountInPyre} PYRE for SwapRouter...`);
  const approveHash = await walletClient.writeContract({
    address: PYRE_TOKEN,
    abi: PYRE_TOKEN_ABI,
    functionName: 'approve',
    args: [SWAP_ROUTER, amountIn],
    chain: sepolia,
    account,
  });
  console.log(`Approval sent: ${approveHash}`);

  console.log('Waiting for approval to be mined...');
  await publicClient.waitForTransactionReceipt({ hash: approveHash });

  console.log(`Swapping ${amountInPyre} PYRE for ETH...`);
  const swapHash = await walletClient.writeContract({
    address: SWAP_ROUTER,
    abi: SWAP_ROUTER_ABI,
    functionName: 'swapExactTokensForTokens',
    args: [
      amountIn,
      0n,
      false, // PYRE -> ETH
      getPoolKey(),
      '0x',
      account.address,
      deadline,
    ],
    chain: sepolia,
    account,
  });
  console.log(`Swap sent: ${swapHash}`);
  return swapHash;
}

// --- CLI RUNNER ---

async function main() {
  const command = process.argv[2];
  const amount = process.argv[3];

  if (!command || !amount || !['buy', 'sell'].includes(command)) {
    console.log('Usage: npx tsx scripts/frontend-integration.ts <buy|sell> <amount>');
    console.log('Example: npx tsx scripts/frontend-integration.ts buy 0.1');
    console.log('\nNote: Ensure RPC_URL and DEPLOYER_PRIVATE_KEY are set in your .env file.');
    process.exit(1);
  }

  const rpcUrl = process.env.RPC_URL;
  let privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (privateKey && !privateKey.startsWith('0x')) {
    privateKey = `0x${privateKey}`;
  }

  if (!rpcUrl || !privateKey) {
    console.error('Error: RPC_URL and DEPLOYER_PRIVATE_KEY must be set in environment');
    process.exit(1);
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);
  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(rpcUrl),
  });

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl),
  });

  try {
    let hash: `0x${string}`;
    if (command === 'buy') {
      hash = await buyPyre(walletClient, amount, account);
    } else {
      hash = await sellPyre(walletClient, amount, account, publicClient);
    }

    console.log('Waiting for transaction to be mined...');
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    console.log(`Transaction successful! Status: ${receipt.status}`);
    console.log(`Block Number: ${receipt.blockNumber}`);
  } catch (error) {
    console.error('Execution failed:', error);
    process.exit(1);
  }
}

// Check if script is run directly
const isMain = process.argv[1] && (
  process.argv[1].endsWith('frontend-integration.ts') || 
  process.argv[1] === fileURLToPath(import.meta.url)
);

if (isMain) {
  main();
}
