# Vibe Coin (VIBE)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Parameter | Value |
| --- | --- |
| Solidity contract name | `VibeCoin` (`src/VibeCoin.sol`) |
| `name()` | `Vibe Coin` |
| `symbol()` | `VIBE` |
| `decimals()` | `18` |
| Total supply | 1,000,000,000 VIBE = `1000000000000000000000000000` minor units (1e27) |
| Constructor arguments | none |
| Minted to | `msg.sender` of the deployment, once, in the constructor |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, EVM `cancun` |

## What the token does

- Mints the whole supply (`TOTAL_SUPPLY`) to the deployer in the constructor and emits
  `Transfer(0, deployer, supply)` plus a one-off `SupplyMinted(deployer, supply)` event.
- Implements plain ERC-20 (OpenZeppelin v5.4.0 `ERC20`): `transfer`, `approve`, `transferFrom`,
  `allowance`, `balanceOf`, `totalSupply`, `name`, `symbol`, `decimals`.
- Nothing else. There is no `mint`, no owner, no pause, no blacklist or freeze, no fee or burn on
  transfer, no upgrade path, no `receive`/`fallback`, no `selfdestruct` or `delegatecall`. The
  supply can never grow after construction, and no address can move or lock another holder's
  balance except through an ERC-20 allowance the holder granted.

## Assumptions

- The deployer is whoever creates the contract. In the IdentityMD launch that is the
  `ProjectFactory`, which receives the full 1e27 units and distributes them (10% to the
  launch's MerkleDistributor, `poolBps` to the Uniswap v4 pool, the remainder to
  `economics.remainderTo`). The token has no exemptions because it has no transfer rules:
  every launch flow moves exactly the amount requested.
- The constructor reads no other contract and takes no arguments, so it deploys on an empty
  chain and the launch manifest's `constructorArgs` is `[]`.
- Decimals are fixed at 18, matching the brief and the manifest.
- No value in the brief was left open: name, symbol, supply and decimals are all given. The only
  constants chosen here are the compiler settings above.

## Deployment parameters

The launch manifest (written by the manifest step, not by this repository) records:

- `token.contract`: `VibeCoin`
- `token.name`: `Vibe Coin`
- `token.symbol`: `VIBE`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`

No application contracts are part of this launch (`contracts: []`).

`script/DeployVibeCoin.s.sol` is a reviewable reference deployment that reads no environment
variables; its `deploy()` function is exercised directly by the tests. It is not used by the
IdentityMD launch, which deploys the built bytecode through its factory.

## After launch

There is nothing to configure: the token has no owner-settable values and no owner. The
operational responsibilities that remain are the launch's, not the token's:

- The factory holds the full supply immediately after deployment and must perform the
  distributor transfer, pool seed and remainder transfer in the same launch transaction.
- Explorer source verification of the deployed bytecode is the deployer's. The build is
  reproducible from this repository with the pinned compiler and `bytecode_hash = "none"`.
- Holders are responsible for their own approvals: an allowance of `type(uint256).max` is never
  decremented, as in every OpenZeppelin ERC-20.

## Security notes

- Built on OpenZeppelin Contracts v5.4.0 `ERC20`, vendored unchanged under
  `lib/openzeppelin-contracts/contracts/` (MIT). Test framework forge-std v1.11.0 is vendored
  under `lib/forge-std/src/` (MIT/Apache-2.0). Both are ordinary files, not submodules.
- Reentrancy: the token makes no external calls.
- No `abi.encodePacked` of dynamic values, no shifts in assembly, no libraries with external
  functions, no initializer, no upgrade path, no `selfdestruct`.
- Tests pass with `forge test` under the verifier's fuzz seed and assume nothing about the
  caller or the environment (no `vm.env*`). Passing tests are not an audit; the launch's
  independent review step is still expected.

## Build and test

```sh
forge build
forge test
forge fmt --check
```
