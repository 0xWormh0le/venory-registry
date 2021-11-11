const { ethers } = require('hardhat')
const { ecsign } = require('ethereumjs-util')

const { keccak256, solidityPack } = ethers.utils

module.exports.getSignature = (
  privateKey,
  data_
) => {
  const { operation, to, value, data, serviceName, nonce } = data_
  const msg = keccak256(
    solidityPack(
      ['uint256', 'address', 'uint256', 'bytes', 'string', 'uint256'],
      [operation, to, value, data, serviceName, nonce]
    )
  )
  const { v, r, s } = ecsign(
    Buffer.from(msg.slice(2), 'hex'),
    Buffer.from(privateKey.slice(2), 'hex')
  )

  return '0x' + r.toString('hex') + s.toString('hex') + v.toString(16)
}

module.exports.privateKey = index => {
  const mnemonic = 'test test test test test test test test test test test junk';
  return ethers.Wallet.fromMnemonic(mnemonic, `m/44'/60'/0'/0/${index}`).privateKey;
}
