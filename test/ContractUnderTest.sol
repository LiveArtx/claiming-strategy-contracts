// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VestingStrategy} from "src/VestingStrategy.sol";
import {MockERC20Token} from "src/mock/ERC20Mock.sol";
import {FailedCallReceiver} from "src/mock/FailedCallReceiver.sol";
import "forge-std/Test.sol";

// ex: forge clean && source .env && forge test  --via-ir -vvvv

abstract contract ContractUnderTest is Test {
    VestingStrategy internal vestingStrategy;
    MockERC20Token internal mockERC20Token;
    FailedCallReceiver internal failedCallReceiver;

    uint256 public mainnetFork;

    address payable deployer = payable(makeAddr("deployer"));
    address payable user1 = payable(makeAddr("user1"));
    address payable user2 = payable(makeAddr("user2"));
    address payable user3 = payable(makeAddr("user3"));
    address payable claimer1 = payable(0xD4B1f81F2484E01FD81c93550a25Bc2023934E8C);
    address payable claimer2 = payable(makeAddr("claimer2"));
    address payable claimer3 = payable(makeAddr("claimer3"));
    address payable unauthorizedUser = payable(makeAddr("unauthorizedUser"));
    address payable failedReceiver;
    address payable tokenApprover = payable(makeAddr("tokenApprover"));

    // Constants
    uint256 public CLAIM_AMOUNT = 500000 * 1e18;
    uint256 public INITIAL_MINT_AMOUNT = 1_000_000;

    function setUp() public virtual {
        string memory mainnet_rpc_url_key = "RPC_URL";
        string memory mainnet_rpc_url = vm.envString(mainnet_rpc_url_key);
        mainnetFork = vm.createFork(mainnet_rpc_url);

        vm.selectFork(mainnetFork);

        vestingStrategy = new VestingStrategy();

        vm.startPrank({msgSender: deployer});
        vm.warp(block.timestamp);

        vm.label({
            account: address(vestingStrategy),
            newLabel: "VestingStrategy"
        });

        vm.deal(deployer, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(unauthorizedUser, 100 ether);

        mockERC20Token = new MockERC20Token();
        mockERC20Token.mint(address(vestingStrategy), INITIAL_MINT_AMOUNT);

        vestingStrategy.initialize(address(mockERC20Token), tokenApprover);

        vm.label({account: address(mockERC20Token), newLabel: "MockArtToken"});

        failedCallReceiver = new FailedCallReceiver();
    }

    // function _claimerDetails()
    //     internal
    //     view
    //     virtual
    //     returns (bytes32 merkleRoot, bytes32[] memory merkleProof)
    // {
    //     // Create merkle tree with two addresses
    //     bytes32[] memory leaves = new bytes32[](2);
    //     leaves[0] = keccak256(abi.encodePacked(claimer1, CLAIM_AMOUNT));
    //     leaves[1] = keccak256(abi.encodePacked(claimer2, CLAIM_AMOUNT * 2));

    //     // Sort leaves for consistent merkle tree
    //     if (uint256(leaves[0]) > uint256(leaves[1])) {
    //         bytes32 temp = leaves[0];
    //         leaves[0] = leaves[1];
    //         leaves[1] = temp;
    //     }

    //     // Calculate merkle root
    //     merkleRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));

    //     // Generate proof for claimer1
    //     merkleProof = new bytes32[](1);
    //     merkleProof[0] = leaves[1];

    //     return (merkleRoot, merkleProof);
    // }
}
