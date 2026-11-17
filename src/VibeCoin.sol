// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Vibe Coin (VIBE)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, in the constructor, to the
/// deployer (`msg.sender`). There is no owner, no minter, no pause, no blacklist, no fee on
/// transfer and no way to mint again: after construction the supply can only stay the same.
/// @dev Built on OpenZeppelin's ERC20 v5.4.0, vendored under lib/. The contract name is
/// `VibeCoin`, which is what a launch manifest records; the token's `name()` is "Vibe Coin".
contract VibeCoin is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "Vibe Coin";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "VIBE";

    /// @notice Decimals of the token (ERC20's default, kept explicit for the manifest).
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply in whole tokens: one billion.
    uint256 public constant SUPPLY_WHOLE_TOKENS = 1_000_000_000;

    /// @notice The total supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = SUPPLY_WHOLE_TOKENS * 10 ** DECIMALS;

    /// @notice Emitted once, when the constructor mints the whole supply to the deployer.
    /// @param deployer The address that received the full supply (`msg.sender` of the deployment).
    /// @param amount The supply minted, in minor units.
    event SupplyMinted(address indexed deployer, uint256 amount);

    /// @notice Mints the full fixed supply to the deployer. Takes no arguments and reads no other
    /// contract, so it can be deployed on an empty chain.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
