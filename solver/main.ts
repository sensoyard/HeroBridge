import axios from "axios";
import { ethers } from "ethers";
import dotenv from "dotenv";

// Load environment variables
dotenv.config();

// Function to get environment variable with type assertion
function getEnvVariable(key: string): string {
  const value = process.env[key];
  if (value === undefined) {
    throw new Error(`Environment variable ${key} is not set`);
  }
  return value;
}

// Access environment variables
const HERODOTUS_API_KEY = getEnvVariable("HERODOTUS_API_KEY");
const CHAIN_A_RPC_URL = getEnvVariable("CHAIN_A_RPC_URL");
const CHAIN_B_RPC_URL = getEnvVariable("CHAIN_B_RPC_URL");
const MULTI_TOKEN_DEPOSIT_ADDRESS_A = getEnvVariable(
  "MULTI_TOKEN_DEPOSIT_ADDRESS_A"
);
const MULTI_TOKEN_DEPOSIT_ADDRESS_B = getEnvVariable(
  "MULTI_TOKEN_DEPOSIT_ADDRESS_B"
);
const PRIVATE_KEY = getEnvVariable("PRIVATE_KEY");

// ABI for the MultiTokenDeposit contract (partial, only what we need)
const ABI = [
  "function depositNonce() view returns (uint256)",
  "function deposits(uint256) view returns (uint256 depositId, address user, address token, address tokenWanted, uint256 amount, uint256 timestamp)",
  "function createFulfillmentOrder(uint256 depositId, uint256 amount, address token, address user) external",
];

async function getLastDeposit(
  provider: ethers.JsonRpcProvider,
  contractAddress: string
) {
  const contract = new ethers.Contract(contractAddress, ABI, provider);
  const nonce = await contract.depositNonce();
  const lastDepositId = nonce.toNumber() - 1;
  const deposit = await contract.deposits(lastDepositId);
  return {
    depositId: deposit.depositId,
    user: deposit.user,
    token: deposit.token,
    tokenWanted: deposit.tokenWanted,
    amount: deposit.amount,
    timestamp: deposit.timestamp,
  };
}

async function createFulfillmentOrder(
  provider: ethers.JsonRpcProvider,
  contractAddress: string,
  depositId: bigint,
  amount: bigint,
  token: string,
  user: string
) {
  const signer = new ethers.Wallet(PRIVATE_KEY, provider);
  const contract = new ethers.Contract(contractAddress, ABI, signer);
  const tx = await contract.createFulfillmentOrder(
    depositId,
    amount,
    token,
    user
  );
  await tx.wait();
  console.log(`Fulfillment order created. Transaction hash: ${tx.hash}`);
}

async function submitBatchQuery(
  depositId: string,
  amount: string,
  orderId: string
) {
  const url = "https://api.herodotus.cloud/submit-batch-query";

  const fulfillmentOrderSlot = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "uint256"],
      [orderId, 1]
    )
  );

  const depositIdSlot = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "bytes32"],
      [0, fulfillmentOrderSlot]
    )
  );

  const userSlot = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "bytes32"],
      [1, fulfillmentOrderSlot]
    )
  );

  const tokenSlot = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "bytes32"],
      [2, fulfillmentOrderSlot]
    )
  );

  const amountSlot = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "bytes32"],
      [3, fulfillmentOrderSlot]
    )
  );

  const data = {
    query: [
      {
        block_id: {
          tag: "latest",
        },
        accounts: [
          {
            address: MULTI_TOKEN_DEPOSIT_ADDRESS_B,
            slots: [depositIdSlot, userSlot, tokenSlot, amountSlot],
          },
        ],
      },
    ],
  };

  const config = {
    headers: {
      "Content-Type": "application/json",
      "X-API-KEY": HERODOTUS_API_KEY,
    },
  };

  try {
    const response = await axios.post(url, data, config);
    console.log("API Response:", response.data);

    const queryId = response.data.query_id;
    console.log("Query ID:", queryId);

    // Here you would typically wait for the query to be processed
    // and then use the results to call claimWithProof
  } catch (error) {
    console.error(
      "Error:",
      error instanceof Error ? error.message : String(error)
    );
  }
}

async function main() {
  const providerA = new ethers.JsonRpcProvider(CHAIN_A_RPC_URL);
  const providerB = new ethers.JsonRpcProvider(CHAIN_B_RPC_URL);

  try {
    // Get the last deposit from chain A
    const lastDeposit = await getLastDeposit(
      providerA,
      MULTI_TOKEN_DEPOSIT_ADDRESS_A
    );
    console.log("Last deposit:", lastDeposit);

    // Create a fulfillment order on chain B
    await createFulfillmentOrder(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      lastDeposit.depositId,
      lastDeposit.amount,
      lastDeposit.tokenWanted,
      lastDeposit.user
    );

    // Submit batch query to Herodotus
    await submitBatchQuery(
      lastDeposit.depositId.toString(),
      lastDeposit.amount.toString(),
      (lastDeposit.depositId + 1n).toString() // Assuming orderId is depositId + 1
    );
  } catch (error) {
    console.error(
      "Error in main function:",
      error instanceof Error ? error.message : String(error)
    );
  }
}

main();
