// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {VibeCoin} from "../src/VibeCoin.sol";

/// @notice Drives VibeCoin with random sequences of transfer / approve / transferFrom from a fixed
/// set of actors, and keeps an independent ghost ledger of balances and allowances. Failing calls
/// (overdraft, missing allowance, zero address) are also driven, and must revert without moving
/// anything.
contract VibeCoinHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    VibeCoin public immutable token;
    address[] public actors;
    /// @dev Every address that could ever hold a balance: the actors plus the token itself.
    address[] public holders;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public ghostSuccessfulMoves;
    uint256 public ghostExpectedReverts;
    uint256 public ghostUnexpectedOutcome;

    constructor(VibeCoin token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            holders.push(actors_[i]);
        }
        holders.push(address(token_));
        // actors_[0] is the deployer and holds the whole supply at the start.
        ghostBalance[actors_[0]] = SUPPLY;
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _holder(uint256 seed) internal view returns (address) {
        return holders[seed % holders.length];
    }

    /// @dev Amount biased to the interesting edges: 0, 1, the whole balance, balance+1, max.
    function _amount(uint256 raw, uint256 balance) internal pure returns (uint256) {
        uint256 pick = raw % 8;
        if (pick == 0) return 0;
        if (pick == 1) return balance == 0 ? 0 : 1;
        if (pick == 2) return balance;
        if (pick == 3) return balance == 0 ? 0 : balance - 1;
        return bound(raw, 0, balance);
    }

    function _move(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostSuccessfulMoves++;
    }

    // ------------------------------------------------------------------ succeeding paths

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 amount = _amount(rawAmount, ghostBalance[from]);
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        if (!ok) ghostUnexpectedOutcome++;
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner_ = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 pick = rawAmount % 4;
        uint256 amount = pick == 0 ? type(uint256).max : (pick == 1 ? 0 : bound(rawAmount, 0, SUPPLY * 2));
        vm.prank(owner_);
        bool ok = token.approve(spender, amount);
        if (!ok) ghostUnexpectedOutcome++;
        ghostAllowance[owner_][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        uint256 amount = _amount(rawAmount, cap);
        vm.prank(spender);
        bool ok = token.transferFrom(from, to, amount);
        if (!ok) ghostUnexpectedOutcome++;
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        _move(from, to, amount);
    }

    // ------------------------------------------------------------------ failing paths

    function transferOverdraft(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) external {
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = balance + bound(rawExcess, 1, type(uint256).max - balance);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
        ghostExpectedReverts++;
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 amount = _amount(rawAmount, ghostBalance[from]);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        ghostExpectedReverts++;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawExcess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(rawExcess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        token.transferFrom(from, to, amount);
        ghostExpectedReverts++;
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawExcess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _holder(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 balance = ghostBalance[from];
        if (allowed <= balance) return; // allowance would be the binding constraint
        uint256 amount = balance + bound(rawExcess, 1, allowed - balance);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transferFrom(from, to, amount);
        ghostExpectedReverts++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner_ = _actor(ownerSeed);
        vm.prank(owner_);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        ghostExpectedReverts++;
    }

    /// @dev Privileged-looking calls from any actor (including the deployer) must all fail and
    /// change nothing.
    function adminCall(uint256 callerSeed, uint256 selectorSeed, uint256 targetSeed, uint256 amount) external {
        string[8] memory signatures = [
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "transferOwnership(address)",
            "pause()",
            "blacklist(address)",
            "seize(address)",
            "freeze(address)"
        ];
        address caller = _actor(callerSeed);
        bytes memory data = abi.encodeWithSignature(signatures[selectorSeed % 8], _actor(targetSeed), amount);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        if (ok) ghostUnexpectedOutcome++;
        ghostExpectedReverts++;
    }
}

contract VibeCoinInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    VibeCoin token;
    VibeCoinHandler handler;
    address[] actors;

    function setUp() public {
        actors.push(makeAddr("deployer"));
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        vm.prank(actors[0]);
        token = new VibeCoin();
        handler = new VibeCoinHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = VibeCoinHandler.transfer.selector;
        selectors[1] = VibeCoinHandler.approve.selector;
        selectors[2] = VibeCoinHandler.transferFrom.selector;
        selectors[3] = VibeCoinHandler.transferOverdraft.selector;
        selectors[4] = VibeCoinHandler.transferToZero.selector;
        selectors[5] = VibeCoinHandler.transferFromOverAllowance.selector;
        selectors[6] = VibeCoinHandler.transferFromOverBalance.selector;
        selectors[7] = VibeCoinHandler.approveZeroSpender.selector;
        selectors[8] = VibeCoinHandler.adminCall.selector;
        // Weight the value-moving paths more heavily.
        selectors[9] = VibeCoinHandler.transfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev The fixed supply never changes, whatever sequence of calls is made.
    /// forge-config: default.invariant.runs = 256
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Every unit of supply is held by a known holder: nothing is created or lost in transit.
    /// forge-config: default.invariant.runs = 256
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, token.totalSupply());
    }

    /// @dev On-chain balances match an independent ledger of every successful move.
    /// forge-config: default.invariant.runs = 256
    function invariant_balancesMatchGhostLedger() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            address h = handler.holders(i);
            assertEq(token.balanceOf(h), handler.ghostBalance(h));
        }
    }

    /// @dev Allowances match the ledger: set by approve, reduced exactly by transferFrom, and an
    /// infinite allowance is never reduced.
    /// forge-config: default.invariant.runs = 256
    function invariant_allowancesMatchGhostLedger() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address o = handler.actors(i);
                address s = handler.actors(j);
                assertEq(token.allowance(o, s), handler.ghostAllowance(o, s));
            }
        }
    }

    /// @dev Every call returned true when it succeeded, and every privileged-looking call failed.
    /// forge-config: default.invariant.runs = 256
    function invariant_noUnexpectedOutcome() public view {
        assertEq(handler.ghostUnexpectedOutcome(), 0);
    }

    /// @dev The zero address never receives a balance, and the token never holds ether.
    /// forge-config: default.invariant.runs = 256
    function invariant_zeroAddressAndEtherStayEmpty() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(address(token).balance, 0);
    }
}
