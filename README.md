# Valary Assignment

https://drive.google.com/file/d/1WPmiQ2rLc-jFKV5_AHUOu_OAcG6U-AIi/view

1. Running test 

`npm run test`

2. Deploying on Ganache

`ganache-cli`
`npm run deploy-ganache`

3. Description

- `execute` function will verify tx in 2 ways
  - EOA of registered service directly call `execute`
  - `execute` is successfully verified using `signature` arg given to the function
- Add reentrancy guard to `execute` function
- Nonce was involved to make signature to prevent attack
- Each token minted has ipfs hash in its token uri

## Run Tests

Compile solidity contracts and run the test suite with:

```shell
npm test
```

## Deploy

```shell
yarn deploy --network kovan
```

## Hardhat Commands

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
node scripts/sample-script.js
npx hardhat help
```
