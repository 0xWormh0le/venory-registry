const { expect } = require('chai')
const { ethers } = require('hardhat')
const { getSignature, privateKey } = require('./signer')

const Operation = {
  Call: 0,
  Create: 1,
  Create2: 2,
  StaticCall: 3,
  DelegateCall: 4
}

describe('Registry', function () {
  before(async () => {
    const Registry = await ethers.getContractFactory('Registry')
    const CallTargetMock = await ethers.getContractFactory('CallTargetMock')

    this.registry = await Registry.deploy('Registry', 'Registry')
    this.callTargetMock = await CallTargetMock.deploy()

    this.signers = await ethers.getSigners()
    this.eoa = this.signers[5]
    this.eoa2 = this.signers[6]
    this.eoa.privateKey = privateKey(5)
    this.eoa2.privateKey = privateKey(6)
  })

  it('register asset', async () => {
    const [ alice ] = this.signers
    const hash1 = 'mtwirsqawjuoloq2gvtyug2tc3jbf5htm2zeo4rsknfiv3fdp46a'
    const hash2 = 'f5htm2zeo4rsknfiv3fdp46amtwirsqawjuoloq2gvtyug2tc3jb'

    // event emits after token mint
    await expect(this.registry.connect(alice).registerAsset(hash1))
      .to.emit(this.registry, 'AssetRegistered')
      .withArgs(alice.address, hash1, 0)

    await expect(this.registry.connect(alice).registerAsset(hash2))
      .to.emit(this.registry, 'AssetRegistered')
      .withArgs(alice.address, hash2, 1)

    // check total supply
    expect(await this.registry.totalSupply()).to.equal(2)

    // check token uri
    expect(await this.registry.tokenURI(0)).to.equal(`https://ipfs.io/ipfs/${hash1}`)
    expect(await this.registry.tokenURI(1)).to.equal(`https://ipfs.io/ipfs/${hash2}`)
  })

  it('register service', async () => {
    const [ alice ] = this.signers

    // check registration failure
    await expect(this.registry.connect(alice).registerService('', [], ethers.constants.AddressZero))
      .to.revertedWith('Registry: invalid service name')
    await expect(this.registry.connect(alice).registerService('service1', [], ethers.constants.AddressZero))
      .to.revertedWith('Registry: invalid eoa address')
    await expect(this.registry.connect(alice).registerService('service1', [1, 2], this.eoa.address))
      .to.revertedWith('Registry: invalid token id')

    // register first service
    await expect(this.registry.connect(alice).registerService('service1', [0, 1], this.eoa.address))
      .to.emit(this.registry, 'ServiceRegistered')
      .withArgs(alice.address, 'service1', [0, 1], this.eoa.address)

    // try register again and fails
    await expect(this.registry.connect(alice).registerService('service1', [0, 1], this.eoa.address))
      .to.revertedWith('Registry: service already registered')

    // register second service
    await this.registry.connect(alice).registerService('service2', [0, 1], this.eoa2.address)
  })

  describe('execute', () => {
    it('fails: unregistered service', async () => {
      const [ alice ] = this.signers

      await expect(this.registry.connect(alice).execute(
        Operation.Call,
        ethers.constants.AddressZero,
        0,
        '0x00',
        'unregistered_service',
        '0x00'
      )).revertedWith('Registry: unregistered service')
    })

    it('fails: invalid signature', async () => {
      const [ alice ] = this.signers
      const msg = {
        operation: Operation.Call,
        to: ethers.constants.AddressZero,
        value: 0,
        data: '0x00',
        serviceName: 'service1',
        nonce: 0
      }
      await expect(this.registry.connect(alice).execute(
        Operation.Call,
        ethers.constants.AddressZero,
        1, // cause of invalid signature, should be 0
        '0x00',
        'service1',
        getSignature(this.eoa.privateKey, msg)
      )).revertedWith('Registry: invalid signature')
    })

    it('fails: invalid signature - called with another EOA\'s service name', async () => {
      const [ alice ] = this.signers
      const msg = {
        operation: Operation.Call,
        to: ethers.constants.AddressZero,
        value: 0,
        data: '0x00',
        serviceName: 'service1',
        nonce: 0
      }
      await expect(this.registry.connect(alice).execute(
        Operation.Call,
        ethers.constants.AddressZero,
        0,
        '0x00',
        'service1',
        getSignature(this.eoa2.privateKey, msg)
      )).revertedWith('Registry: invalid signature')
    })

    it('signature verifcation succeeds but reverts for invalid operation: called directly from eoa', async () => {
      await expect(this.registry.connect(this.eoa).execute(
        5, // invalid operation
        ethers.constants.AddressZero,
        0,
        '0x00',
        'service1',
        '0x00'
      )).revertedWith('Registry: invalid operation type')
    })

    it('succeeds: signature verification succeeds and makes contract call', async () => {
      const [ alice ] = this.signers

      const iface = new ethers.utils.Interface(
        ['function increase()']
      )
      const callData = iface.encodeFunctionData('increase', [])
      const msg = {
        operation: Operation.Call,
        to: this.callTargetMock.address,
        value: 0,
        data: callData,
        serviceName: 'service1',
        nonce: 0
      }
      const callTargetNonce = await this.callTargetMock.nonce()

      await expect(this.registry.connect(alice).execute(
        Operation.Call,
        this.callTargetMock.address,
        0,
        callData,
        'service1',
        getSignature(this.eoa.privateKey, msg)
      )).to.emit(this.registry, 'Executed')
        .withArgs(Operation.Call, this.callTargetMock.address, 0, callData)

      expect(await this.callTargetMock.nonce())
        .to.equal(callTargetNonce.add(1))
    })

    it('succeeds: next call should be sent with signature made with increased nonce', async () => {
      const [ alice ] = this.signers
      const msg = {
        operation: Operation.Call,
        to: this.callTargetMock.address,
        value: 0,
        data: '0x00',
        serviceName: 'service1',
        nonce: 0
      }

      // fails with current nonce used to make signature
      await expect(this.registry.connect(alice).execute(
        Operation.Call,
        this.callTargetMock.address,
        0,
        '0x00',
        'service1',
        getSignature(this.eoa.privateKey, msg)
      )).to.revertedWith('Registry: invalid signature')

      // try with signature made with increased nonce and signature verification succeeds
      msg.nonce = 1
      msg.operation = 9

      await expect(this.registry.connect(alice).execute(
        9,
        this.callTargetMock.address,
        0,
        '0x00',
        'service1',
        getSignature(this.eoa.privateKey, msg)
      )).to.revertedWith('Registry: invalid operation type')
    })
  })
})