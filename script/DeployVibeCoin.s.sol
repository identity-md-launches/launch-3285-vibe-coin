// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {VibeCoin} from "../src/VibeCoin.sol";

/// @title DeployVibeCoin
/// @notice Reviewable deployment script. The token takes no constructor arguments, so there is
/// nothing to configure: `deploy()` creates the token and the caller of the creation receives
/// the full supply. The IdentityMD launch does not use this script; its factory deploys the
/// token from the built bytecode, and the factory becomes the holder of the supply.
contract DeployVibeCoin is Script {
    /// @notice Deploys the token. Exposed separately from `run()` so tests call it directly.
    function deploy() public returns (VibeCoin token) {
        token = new VibeCoin();
    }

    /// @notice Broadcast entry point. Reads no environment variables.
    function run() external returns (VibeCoin token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
