# Bridge

## Workflows
![image](https://github.com/user-attachments/assets/37aaaba2-d56d-44cc-8a3e-b37a15cbf3de)

## Roles

- **Users** 
    - Submit deposit transactions to Bitcoin network
    - Submit withdrawal requests through EVM
    - Monitor transaction status through bridge interface
    - Manage their wrapped BTC balance on L2

- **Relayer**
    - Manage cross-chain state and transaction consensus
    - Propose and validate Bitcoin block headers
    - Process deposit and withdrawal requests
    - Maintain P2P network communication
    - Generate and validate SPV proofs
    - Send withdrawal
    - Monitor Bitcoin network for new blocks and transactions
  
    - **Relayer Group**
        - Managed by a multi-signature whitelist contract
        - Member changes (add/remove) are submitted to Fireblocks persistence layer
        - Fireblocks manages TSS private key shares
    - **Proposer**
        - Selected periodically from voters by consensus
        - Must submit all relayer messages
        - Manages BLS12-381 private key for multi-signature
    - **Voter**
        - All members except leader in the multi-signature group
        - Has voting rights for relayer transactions
        - Each member manages their own BLS12-381 private key for multi-signature
    - **Replica**
        - Responsible for forwarding P2P messages

- **Fireblocks Network**: 
    - Manage threshold signature scheme (TSS) for Bitcoin transactions
    - Generate and manage deposit addresses
    - Sign withdrawal transactions
    - Maintain key shares security
    - Handle member changes in the TSS group
  
## Deposit Flow

1. User interface (bridge) obtains the latest deposit public key from consensus layer and constructs a deposit address
2. User sends BTC to the deposit address and submits the raw transaction with L2 EVM address to relayer RPC
3. Relayer RPC performs initial validation and returns pending status
4. Once transaction reaches required confirmations, SPV proof is generated and broadcasted to relayer network
5. Proposer validates transaction and submits deposit confirmation to consensus layer
6. Consensus layer validates SPV proof and adds to pending transaction list
7. Validators select up to 16 pending transactions for execution layer
8. Execution layer confirms and increases balance for deposit address

### Versions
There are two versions to contained L2 EVM address in the raw transaction, allow  L2 EVM address to be detected through consensus layer and add wrapped funds to L2 EVM address on execution layer. 

**Deposit by OP_RETURN**: build a transaction with op_return txout which contained magic bytes and user evm address, and txout index 0 contains the receiving funds to the tss-servers managed address.  

**Deposit by P2WSH** evm address is contained in the witness script and could used to receiving funds on anywhere and anytime
### bridge-in p2wsh witness script
```
<evmAddress> OP_DROP <pubkey> OP_CHECKSIG
```

### References
**Deposit by OP_RETURN**
``` typescript
export function buildDataEmbedScript(magicBytes: Buffer, evmAddress: Buffer): Buffer {
  // Parameter validation
  if (!Buffer.isBuffer(magicBytes) || magicBytes.length !== 4) {
    throw new Error("magicBytes must be a Buffer of length 4");
  }
  if (!Buffer.isBuffer(evmAddress) || evmAddress.length !== 20) {
    throw new Error("evmAddress must be a Buffer of length 20");
  }

  // Serialize data
  const serializedStakingData = Buffer.concat([
    magicBytes, // 4 bytes, endianess not applicable to byte array
    evmAddress // 20 bytes, endianess not applicable to byte array
  ]);

  return script.compile([opcodes.OP_RETURN, serializedStakingData]);
}
```
https://github.com/GOATNetwork/btc-script-factory/blob/193ae38d4d66f72adf4125df30e433dee10fbf74/lib/covenantV1/bridge.script.js#L38

**Deposit by P2WSH** 
``` typescript
export function buildDepositScript(evmAddress: Buffer, posPubkey: Buffer): Buffer {
  if (!Buffer.isBuffer(evmAddress) || !Buffer.isBuffer(posPubkey)) {
    throw new Error("Invalid input types");
  }
  if (evmAddress.length !== ETH_PK_LENGTH) {
    throw new Error("Invalid EVM address length");
  }
  if (posPubkey.length !== PK_LENGTH) {
    throw new Error("Invalid public key length");
  }

  return script.compile([
    evmAddress,
    opcodes.OP_DROP,
    posPubkey,
    opcodes.OP_CHECKSIG
  ]);
}
```
https://github.com/GOATNetwork/btc-script-factory/blob/193ae38d4d66f72adf4125df30e433dee10fbf74/src/covenantV1/bridge.script.ts#L11C17-L11C35

## Withdrawal Flow

1. User submits withdrawal request in EVM
2. Consensus layer processes request and adds to pending list
3. Proposer waits for optimal conditions (aggregation, network fees) before initiating withdrawal
4. Proposer initiates withdrawal construction request in P2P network
5. Voters validate and sign the request
6. Proposer submits signed withdrawal request to consensus layer
7. Proposer requests signatures for each BTC transaction input
8. Voters sign and return signatures to proposer
9. Proposer constructs complete transaction and submits to both consensus layer and BTC network
10. After final confirmation, proposer submits withdrawal completion with SPV proof to consensus layer
11. Consensus layer validates and updates withdrawal status
12. Validators select up to 16 completed transactions for execution layer
13. Execution layer finalizes withdrawal status
