// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VibeCoin} from "../src/VibeCoin.sol";

/// @notice Deploys two tokens in one transaction, to show each deployment is independent.
contract TwinDeployer {
    function deployTwo() external returns (VibeCoin a, VibeCoin b) {
        a = new VibeCoin();
        b = new VibeCoin();
    }
}

/// @notice Edge cases and failure paths not covered by VibeCoin.t.sol.
contract VibeCoinEdgesTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 1e18;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address spender = makeAddr("spender");

    VibeCoin token;

    function setUp() public {
        vm.prank(deployer);
        token = new VibeCoin();
    }

    // ------------------------------------------------------------------ constructor

    function test_eachDeploymentMintsItsOwnSupplyOnce() public {
        TwinDeployer d = new TwinDeployer();
        (VibeCoin a, VibeCoin b) = d.deployTwo();
        assertTrue(address(a) != address(b));
        assertEq(a.balanceOf(address(d)), SUPPLY);
        assertEq(b.balanceOf(address(d)), SUPPLY);
        assertEq(a.totalSupply(), SUPPLY);
        assertEq(b.totalSupply(), SUPPLY);
        // The original token is untouched by later deployments.
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(d)), 0);
    }

    function test_constructorEmitsExactlyTwoLogs() public {
        vm.recordLogs();
        vm.prank(alice);
        VibeCoin t = new VibeCoin();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "only Transfer and SupplyMinted");
        assertEq(logs[0].emitter, address(t));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(logs[1].topics[0], keccak256("SupplyMinted(address,uint256)"));
        assertEq(logs[1].topics[1], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[1].data, (uint256)), SUPPLY);
    }

    function test_noAllowancesExistAfterDeployment() public view {
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.allowance(deployer, address(token)), 0);
    }

    // ------------------------------------------------------------------ approve

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(spender, 100);
        token.approve(spender, 30);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 30);
    }

    function test_approveToZeroRevokes() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(deployer);
        token.approve(spender, 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_approveIsPerSpender() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_approveMoreThanBalanceIsAllowedButCannotOverdraw() public {
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    // ------------------------------------------------------------------ transferFrom

    function test_selfTransferFromStillNeedsAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, spender), 10, "a reverted call spends no allowance");
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromZeroAddressReverts() public {
        // amount 0 passes the allowance amount check, and the allowance rewrite rejects the zero owner.
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), bob, 0);
        // a nonzero amount is stopped earlier by the allowance.
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(deployer);
        token.approve(spender, 7e18);
        vm.prank(spender);
        token.transferFrom(deployer, bob, 7e18);
        assertEq(token.allowance(deployer, spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromDoesNotEmitApproval() public {
        vm.prank(deployer);
        token.approve(spender, 5);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(deployer, bob, 3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
    }

    function test_transferFromZeroAmountWithoutAllowanceSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromOwnerToOwnerKeepsBalanceButSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.prank(spender);
        token.transferFrom(deployer, deployer, 4);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, spender), 6);
    }

    // ------------------------------------------------------------------ transfer edges

    function test_transferOneWeiAndBack() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        token.transfer(deployer, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_tokensSentToTheTokenContractAreLockedNotLost() public {
        vm.prank(deployer);
        token.transfer(address(token), 5e18);
        assertEq(token.balanceOf(address(token)), 5e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revertedTransferChangesNothing() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_burnSelectorsDoNotExist() public {
        vm.startPrank(deployer);
        (bool ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertFalse(ok);
        (ok,) = address(token).call(abi.encodeWithSignature("burn(address,uint256)", deployer, 1));
        assertFalse(ok);
        vm.stopPrank();
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ------------------------------------------------------------------ fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferChainConservesSupply(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        assertEq(token.balanceOf(deployer), SUPPLY - a);
        assertEq(token.balanceOf(alice), a - b);
        assertEq(token.balanceOf(bob), b);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromNeverExceedsMinOfAllowanceAndBalance(
        uint256 balance,
        uint256 allowance_,
        uint256 amount
    ) public {
        balance = bound(balance, 0, SUPPLY);
        allowance_ = bound(allowance_, 0, type(uint256).max);
        amount = bound(amount, 0, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, allowance_);

        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(IERC20.transferFrom, (alice, bob, amount)));
        if (amount <= allowance_ && amount <= balance) {
            assertTrue(ok);
            assertEq(token.balanceOf(bob), amount);
            assertEq(token.balanceOf(alice), balance - amount);
            if (allowance_ == type(uint256).max) assertEq(token.allowance(alice, spender), allowance_);
            else assertEq(token.allowance(alice, spender), allowance_ - amount);
        } else {
            assertFalse(ok);
            assertEq(token.balanceOf(bob), 0);
            assertEq(token.balanceOf(alice), balance);
            assertEq(token.allowance(alice, spender), allowance_);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 500
    function testFuzz_strangerCannotMoveAnotherHoldersBalance(address stranger, uint256 amount) public {
        vm.assume(stranger != alice);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(stranger);
        (bool ok,) = address(token).call(abi.encodeCall(IERC20.transferFrom, (alice, stranger, amount)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), amount);
    }
}
