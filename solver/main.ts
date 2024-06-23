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

// ABI for the MultiTokenDeposit contract
const ABI = [
  "function depositNonce() view returns (uint256)",
  "function deposits(uint256) view returns (uint256 depositId, address user, address token, address tokenWanted, uint256 amount, uint256 timestamp)",
  "function createFulfillmentOrder(uint256 depositId, uint256 amount, address token, address user) external",
  "function claimWithProof(uint256 depositId, uint256 amount, uint256 blockNumber, uint256 orderId) external",
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
  const receipt = await tx.wait();
  console.log(`Fulfillment order created. Transaction hash: ${tx.hash}`);
  return receipt.blockNumber;
}

async function getStorageAt(
  provider: ethers.JsonRpcProvider,
  address: string,
  slot: string,
  blockTag: string | number = "latest"
): Promise<string> {
  return await provider.getStorage(address, slot, blockTag);
}

async function submitBatchQuery(
  depositId: string,
  amount: string,
  orderId: string,
  blockNumber: number
) {
  const providerB = new ethers.JsonRpcProvider(CHAIN_B_RPC_URL);

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

  try {
    const depositIdValue = await getStorageAt(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      depositIdSlot,
      blockNumber
    );
    const userValue = await getStorageAt(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      userSlot,
      blockNumber
    );
    const tokenValue = await getStorageAt(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      tokenSlot,
      blockNumber
    );
    const amountValue = await getStorageAt(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      amountSlot,
      blockNumber
    );

    console.log("Slot values:");
    console.log("depositId:", depositIdValue);
    console.log("user:", ethers.getAddress("0x" + userValue.slice(-40)));
    console.log("token:", ethers.getAddress("0x" + tokenValue.slice(-40)));
    console.log("amount:", BigInt(amountValue).toString());

    // Now submit these values to Herodotus
    const url = "https://api.herodotus.cloud/submit-batch-query";
    const data = {
      query: [
        {
          block_id: {
            number: blockNumber,
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

    const response = await axios.post(url, data, config);
    console.log("Herodotus API Response:", response.data);
    return response.data.query_id;
  } catch (error) {
    console.error(
      "Error:",
      error instanceof Error ? error.message : String(error)
    );
    throw error;
  }
}

async function waitForQueryResult(queryId: string): Promise<any> {
  const url = `https://api.herodotus.cloud/get-query-status/${queryId}`;
  const config = {
    headers: {
      "X-API-KEY": HERODOTUS_API_KEY,
    },
  };

  while (true) {
    const response = await axios.get(url, config);
    if (response.data.status === "DONE") {
      return response.data.result;
    } else if (response.data.status === "FAILED") {
      throw new Error("Query failed");
    }
    await new Promise((resolve) => setTimeout(resolve, 5000)); // Wait for 5 seconds before checking again
  }
}

async function claimWithProof(
  provider: ethers.JsonRpcProvider,
  contractAddress: string,
  depositId: bigint,
  amount: bigint,
  blockNumber: number,
  orderId: bigint
) {
  const signer = new ethers.Wallet(PRIVATE_KEY, provider);
  const contract = new ethers.Contract(contractAddress, ABI, signer);
  const tx = await contract.claimWithProof(
    depositId,
    amount,
    blockNumber,
    orderId
  );
  await tx.wait();
  console.log(`Claim with proof completed. Transaction hash: ${tx.hash}`);
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
    const blockNumber = await createFulfillmentOrder(
      providerB,
      MULTI_TOKEN_DEPOSIT_ADDRESS_B,
      lastDeposit.depositId,
      lastDeposit.amount,
      lastDeposit.tokenWanted,
      lastDeposit.user
    );

    const orderId = lastDeposit.depositId + 1n; // Assuming orderId is depositId + 1

    // Submit batch query to Herodotus with individual slot fetching
    const queryId = await submitBatchQuery(
      lastDeposit.depositId.toString(),
      lastDeposit.amount.toString(),
      orderId.toString(),
      blockNumber
    );

    console.log("Waiting for Herodotus query result...");
    const queryResult = await waitForQueryResult(queryId);
    console.log("Query result:", queryResult);

    // Call claimWithProof on chain A
    await claimWithProof(
      providerA,
      MULTI_TOKEN_DEPOSIT_ADDRESS_A,
      lastDeposit.depositId,
      lastDeposit.amount,
      blockNumber,
      orderId
    );

    console.log("Cross-chain transfer completed successfully!");
  } catch (error) {
    console.error(
      "Error in main function:",
      error instanceof Error ? error.message : String(error)
    );
  }
}

main();
