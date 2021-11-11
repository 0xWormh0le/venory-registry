module.exports = async ({getNamedAccounts, deployments}) => {
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();

  await deploy('Registry', {
    from: deployer,
    args: ['Registry', 'Registry'],
    log: true,
  });
}

module.exports.tags = ['Registry'];
