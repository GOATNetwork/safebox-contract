-include .env

deployMain:
	forge script script/Deploy.s.sol:Deploy --rpc-url goatMainnet --broadcast -vvvv --verify --verifier blockscout --verifier-url https://explorer.goat.network/api/

deployTest:
	forge script script/DeployTest.s.sol:DeployTest --rpc-url goatTestnet --broadcast -vvvv --verify --verifier blockscout --verifier-url https://explorer.testnet3.goat.network/api/
