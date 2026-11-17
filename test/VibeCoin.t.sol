// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VibeCoin} from "../src/VibeCoin.sol";
import {DeployVibeCoin} from "../script/DeployVibeCoin.s.sol";

/// @notice Stands in for the launch factory: deploys the token with CREATE2 and holds the supply,
/// then pays it out the way the factory does.
contract FactoryProbe {
    function deploy(bytes32 salt) external returns (VibeCoin token) {
        token = new VibeCoin{salt: salt}();
    }

    function move(VibeCoin token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract VibeCoinTest is Test {
    uint256 constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");

    VibeCoin token;

    event SupplyMinted(address indexed deployer, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new VibeCoin();
    }

    // ---------------------------------------------------------------- metadata & constructor

    function test_metadata() public view {
        assertEq(token.name(), "Vibe Coin");
        assertEq(token.symbol(), "VIBE");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Vibe Coin");
        assertEq(token.TOKEN_SYMBOL(), "VIBE");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstants() public view {
        assertEq(token.SUPPLY_WHOLE_TOKENS(), 1_000_000_000);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "supply");
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(this)), 0, "test contract got nothing");
    }

    function test_constructorEmitsTransferFromZeroAndSupplyMinted() public {
        address other = makeAddr("other");
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), other, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(other, EXPECTED_SUPPLY);
        vm.prank(other);
        new VibeCoin();
    }

    /// @dev The launch deploys through a factory contract with CREATE2: the factory, not any EOA,
    /// must hold the supply afterwards, and nothing in the constructor may move it.
    function test_factoryStyleCreate2DeploymentMintsToTheFactory() public {
        FactoryProbe factory = new FactoryProbe();
        VibeCoin deployed = factory.deploy(bytes32(uint256(42)));
        assertTrue(address(deployed).code.length > 0);
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(deployer), 0);
    }

    /// @dev The launch flows: ten percent to the distributor, a claim out of it, both whole.
    function test_launchFlowsArriveWhole() public {
        FactoryProbe factory = new FactoryProbe();
        VibeCoin deployed = factory.deploy(bytes32(uint256(7)));
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        uint256 swarm = EXPECTED_SUPPLY / 10;

        assertTrue(factory.move(deployed, distributor, swarm));
        assertEq(deployed.balanceOf(distributor), swarm);
        vm.prank(distributor);
        assertTrue(deployed.transfer(claimant, swarm));
        assertEq(deployed.balanceOf(claimant), swarm);
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_deployScriptMintsToTheScriptCaller() public {
        DeployVibeCoin script = new DeployVibeCoin();
        VibeCoin deployed = script.deploy();
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
        // The script contract is msg.sender of the creation, so it holds the supply.
        assertEq(deployed.balanceOf(address(script)), EXPECTED_SUPPLY);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_000e18;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, EXPECTED_SUPPLY));
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5e18));
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferRevertsWhenSenderHasLessThanAmount() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10e18, 10e18 + 1));
        token.transfer(bob, 10e18 + 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------- approve / transferFrom

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(deployer, spender, 123e18);
        vm.prank(deployer);
        assertTrue(token.approve(spender, 123e18));
        assertEq(token.allowance(deployer, spender), 123e18);
    }

    function test_approveToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100e18);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(deployer, bob, 60e18);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 60e18));

        assertEq(token.balanceOf(bob), 60e18);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 60e18);
        assertEq(token.allowance(deployer, spender), 40e18);
        assertEq(token.balanceOf(spender), 0, "the spender itself received nothing");
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrement() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1e18);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_transferFromRevertsWhenAllowanceTooSmall() public {
        vm.prank(deployer);
        token.approve(spender, 5e18);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 5e18, 6e18));
        token.transferFrom(deployer, bob, 6e18);
    }

    function test_transferFromRevertsWhenOwnerBalanceTooSmall() public {
        vm.prank(alice);
        token.approve(spender, 1e18);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1e18));
        token.transferFrom(alice, bob, 1e18);
    }

    /// @dev Nobody can pull tokens from a holder who approved nothing, not even the deployer.
    function test_deployerCannotPullFromAHolder() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10e18);
    }

    // ---------------------------------------------------------------- no admin surface

    /// @dev The token exposes none of the usual privileged functions. Every such call reverts
    /// (no matching selector, no fallback), the supply never grows and a holder keeps transferring.
    function test_noAdminOrMintSelectorExists() public {
        vm.prank(deployer);
        token.transfer(alice, 1e18);
        address attacker = makeAddr("attacker");
        string[18] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "setTransfersEnabled(bool)"
        ];
        address[2] memory callers = [attacker, deployer];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 1e18);
        assertEq(token.balanceOf(attacker), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1e18));
    }

    function test_plainEtherTransferAndUnknownCalldataRevert() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token must not accept ether");
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok, "token must not have a fallback");
    }

    // ---------------------------------------------------------------- bytecode

    function test_runtimeCodeFitsEip170() public view {
        uint256 size = address(token).code.length;
        assertGt(size, 0);
        assertLe(size, 24_576);
    }

    /// @dev Mirrors the launch floor: reachable runtime code has no DELEGATECALL, CALLCODE or
    /// SELFDESTRUCT. Push data is skipped and bytes after a terminating opcode are data until the
    /// next JUMPDEST.
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, EXPECTED_SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, amount)
        );
        token.transfer(alice, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, EXPECTED_SUPPLY);
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowance_);
        vm.prank(spender);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance_, amount)
            );
            token.transferFrom(deployer, bob, amount);
        } else {
            assertTrue(token.transferFrom(deployer, bob, amount));
            assertEq(token.balanceOf(bob), amount);
            assertEq(token.allowance(deployer, spender), allowance_ - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }
}
