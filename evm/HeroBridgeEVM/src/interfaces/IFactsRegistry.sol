// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

library Types {
    struct BlockHeaderProof {
        uint256 treeId;
        uint128 mmrTreeSize;
        uint256 blockNumber;
        uint256 blockProofLeafIndex;
        bytes32[] mmrPeaks;
        bytes32[] mmrElementInclusionProof;
        bytes provenBlockHeader;
    }

    enum AccountFields {
        NONCE,
        BALANCE,
        STORAGE_ROOT,
        CODE_HASH
    }
}

interface IFactsRegistry {
    function accountField(
        address account,
        uint256 blockNumber,
        Types.AccountFields field
    ) external view returns (bytes32);

    function accountStorageSlotValues(
        address account,
        uint256 blockNumber,
        bytes32 slot
    ) external view returns (bytes32);

    function verifyAccount(
        address account,
        Types.BlockHeaderProof calldata headerProof,
        bytes calldata accountTrieProof
    )
        external
        view
        returns (
            uint256 nonce,
            uint256 accountBalance,
            bytes32 codeHash,
            bytes32 storageRoot
        );

    function verifyStorage(
        address account,
        uint256 blockNumber,
        bytes32 slot,
        bytes calldata storageSlotTrieProof
    ) external view returns (bytes32 slotValue);
}
