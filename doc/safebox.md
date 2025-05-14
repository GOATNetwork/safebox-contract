# Safebox-Transactions

## Workflows
![image](https://github.com/user-attachments/assets/f2cb8253-9aac-442e-914b-5d2efb6a7160)


## Roles

- **Admin**: Has the authority to manage certificates, including creating, canceling, and forcibly destroying them.
- **Relayer**: Responsible for receiving funds and initializing timelock transactions.
- **Partner**: Provides the account address and sets up the certificate. For the same partner, only one certificate can be in progress at a time.

## Main Bitcoin Transactions

- **Bridge-In (User Side)**: Partner send bridge-in transaction and get wrapped btc by evm address on GOAT Network
- **Gen-Timelock-Utxo (Server Side)**: Relayer network detecting bridge-in transaction, the relayer-voter votes and then relayer-proposer send timelock-p2wsh which could be spent by the related partner. Proposer is elected in voters by random argorism.
- **Recover-to-P2wpkh (User Side)**: Partner convert timelock-p2wsh utxo to normal address utxo

### timelock-p2wsh witness script
```
<timestamp>
OP_CHECKLOCKTIMEVERIFY
OP_DROP
<pubkey>
OP_CHECKSIG
```

### References
```
func BuildTimeLockScriptForP2WSH(pubKey []byte, lockTime time.Time, net *chaincfg.Params) ([]byte, error) {
	posPubkey, err := btcec.ParsePubKey(pubKey)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key: %v", err)
	}
	subScript, err := txscript.NewScriptBuilder().
		AddInt64(lockTime.Unix()).
		AddOp(txscript.OP_CHECKLOCKTIMEVERIFY).
		AddOp(txscript.OP_DROP).
		AddData(posPubkey.SerializeCompressed()).
		AddOp(txscript.OP_CHECKSIG).Script()
	if err != nil {
		return nil, fmt.Errorf("failed to build subscript: %v", err)
	}
	return subScript, nil
}
```
https://github.com/GOATNetwork/goat-relayer/blob/0ea838b6e6bca79b4f255df3922646c2f8773eb2/internal/types/utils.go#L350

## Contracts Procedure

- **Certificate Creation**: Use the `setupTask` function to set up a new certificate for partners. The certificate must meet specific conditions, such as a valid deadline, timelock, amount, etc.
- **Certificate Cancellation**: The certificate can be canceled using the `cancelTask` function before the funds are received.
- **Funds Reception**: Use the `receiveFunds` function to mark the certificate as received, ensuring the funds have been deposited.
- **Initialize Timelock Transaction**: Use the `initTimelockTx` function to initialize the timelock transaction for the funds.
- **Process Timelock Transaction**: Use the `processTimelockTx` function to verify the validity of the timelock transaction.
- **Certificate Completion**: After the timelock expires, use the `burn` function to complete the certificate and destroy the funds.
- **Force Destruction**: The administrator can use the `forceBurn` function to forcibly destroy the certificate before the timelock expires.


### Event

- `TaskCreated`: Triggered when a certificate is created.
- `TaskCancelled`: Triggered when a certificate is canceled.
- `FundsReceived`: Triggered when funds are received.
- `TimelockInitialized`: Triggered when a timelock transaction is initialized.
- `TimelockProcessed`: Triggered when a timelock transaction is processed.
- `Burned`: Triggered when a certificate is completed and destroyed.

