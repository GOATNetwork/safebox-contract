# Bridge

## Roles

- **Users**: 
    - Submit deposit transactions to Bitcoin network
    - Submit withdrawal requests through EVM
    - Monitor transaction status through bridge interface
    - Manage their wrapped BTC balance on L2

- **Relayer**: 
    - Manage cross-chain state and transaction consensus
    - Propose and validate Bitcoin block headers
    - Process deposit and withdrawal requests
    - Maintain P2P network for communication
    - Generate and validate SPV proofs
    - Sign withdrawal transactions
    - Monitor Bitcoin network for new blocks and transactions
  
    - **Relayer Group**
        - Managed by a multi-signature whitelist contract
        - Member changes (add/remove) are submitted to Fireblocks persistence layer via /v2/config_change_sign_request
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

- **Tss Layer**: 
    - Manage threshold signature scheme (TSS) for Bitcoin transactions
    - Generate and manage deposit addresses
    - Sign withdrawal transactions
    - Maintain key shares security
    - Coordinate with Fireblocks for key management
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
There are 2 versions to contained L2 EVM address in the raw transaction, allow  L2 EVM address to be detected through consensus layer and add wrapped funds to L2 EVM address on execution layer. 

**Deposit(P2wpkh with evm address in op_return)**: build a transaction with op_return txout which contained magic bytes and user evm address, and txout index 0 contains the receiving funds to the tss-servers managed address.  

**Deposit Anywhere(P2wsh with evm address in witness script)** evm address is contained in the witness script and could used to receiving funds on anywhere and anytime
### bridge-in p2wsh witness script
```
<evmAddress>
OP_DROP
<pubkey>
OP_CHECKSIG
```

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