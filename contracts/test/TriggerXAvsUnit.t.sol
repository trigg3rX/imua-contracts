// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.17;

// import "forge-std/Test.sol";
// import {TriggerXAvs, TaskDefinition} from "../src/TriggerXAvs.sol";
// import "../src/interfaces/IAVSManager.sol" as avs;

// /// Mock that stands in for the AVS-Manager precompile (same as earlier tests).
// contract MockAVSManager is avs.IAVSManager {
//     uint64 public taskCounter;

//     function registerAVS(avs.AVSParams calldata) external pure returns (bool) { return true; }
//     function updateAVS(avs.AVSParams calldata) external pure returns (bool) { return true; }
//     function deregisterAVS(address, string calldata) external pure returns (bool) { return true; }
//     function registerOperatorToAVS(address) external pure returns (bool) { return true; }
//     function deregisterOperatorFromAVS(address) external pure returns (bool) { return true; }
//     function createTask(address, string calldata, bytes calldata, uint64, uint64, uint8, uint64) external returns (uint64) { return ++taskCounter; }
//     function registerBLSPublicKey(address, address, bytes calldata, bytes calldata) external pure returns (bool) { return true; }
//     function operatorSubmitTask(address, uint64, bytes calldata, bytes calldata, address, uint8) external pure returns (bool) { return true; }
//     function challenge(address, uint64, address, uint8, bool, address[] calldata, address[] calldata) external pure returns (bool) { return true; }

//     // unused views
//     function getRegisteredPubkey(address, address) external pure returns (bytes memory) { return ""; }
//     function getOptInOperators(address) external pure returns (address[] memory operators) {}
//     function getAVSUSDValue(address) external pure returns (uint256) { return 0; }
//     function getOperatorOptedUSDValue(address, address) external pure returns (uint256) { return 0; }
//     function getAVSEpochIdentifier(address) external pure returns (string memory) { return "hour"; }
//     function getTaskInfo(address, uint64) external pure returns (avs.TaskInfo memory) { revert(); }
//     function isOperator(address) external pure returns (bool) { return true; }
//     function getCurrentEpoch(string calldata) external pure returns (int64) { return 0; }
//     function getChallengeInfo(address, uint64) external pure returns (address) { return address(0); }
//     function getOperatorTaskResponse(address, address, uint64) external pure returns (avs.TaskResultInfo memory) { revert(); }
//     function getOperatorTaskResponseList(address, uint64) external pure returns (avs.OperatorResInfo[] memory) { revert(); }
// }

// contract TriggerXAvsOwnerTests is Test {
//     TriggerXAvs public avsProxy;
//     MockAVSManager public mock;

//     address owner = address(this);
//     address nonOwner = address(0xBEEF);

//     function setUp() public {
//         // Deploy and etch mock precompile
//         mock = new MockAVSManager();
//         vm.etch(avs.AVSMANAGER_PRECOMPILE_ADDRESS, address(mock).code);

//         avsProxy = new TriggerXAvs();
//         avsProxy.initialize(owner);
//     }

//     // --------------------------------------------------------
//     // RewardManager & Slasher setters
//     // --------------------------------------------------------

//     function testOnlyOwnerSetRewardManager() public {
//         address newRM = address(0xCAFE);
//         // non-owner should revert
//         vm.prank(nonOwner);
//         vm.expectRevert("Ownable: caller is not the owner");
//         avsProxy.setRewardManager(newRM);

//         // owner succeeds & event emitted
//         vm.expectEmit(true, false, false, false);
//         emit TriggerXAvs.RewardManagerUpdated(newRM);
//         avsProxy.setRewardManager(newRM);
//         assertEq(avsProxy.rewardManager(), newRM);
//     }

//     function testOnlyOwnerSetSlasher() public {
//         address newS = address(0xDEAD);
//         vm.prank(nonOwner);
//         vm.expectRevert("Ownable: caller is not the owner");
//         avsProxy.setSlasher(newS);

//         vm.expectEmit(true, false, false, false);
//         emit TriggerXAvs.SlasherUpdated(newS);
//         avsProxy.setSlasher(newS);
//         assertEq(avsProxy.slasher(), newS);
//     }

//     function testCreateTaskDefinitionOnlyOwner() public {
//         vm.prank(nonOwner);
//         vm.expectRevert("Ownable: caller is not the owner");
//         avsProxy.createTaskDefinition(
//             "foo",
//             1 ether,
//             0.5 ether,
//             0.2 ether,
//             1000,
//             new address[](0),
//             100
//         );

//         vm.expectEmit(true, false, false, true);
//         emit TriggerXAvs.TaskDefinitionCreated(1, "foo");
//         uint8 id = avsProxy.createTaskDefinition(
//             "foo",
//             1 ether,
//             0.5 ether,
//             0.2 ether,
//             1000,
//             new address[](0),
//             100
//         );
//         assertEq(id, 1);

//         TaskDefinition memory stored = avsProxy.getTaskDefinition(id);
//         assertEq(stored.name, "foo");
//         assertEq(stored.baseRewardFeeForAttesters, 1 ether);
//         assertEq(stored.baseRewardFeeForPerformer, 0.5 ether);
//         assertEq(stored.baseRewardFeeForAggregator, 0.2 ether);
//         assertEq(stored.minimumVotingPower, 1000);
//         assertEq(stored.restrictedOperatorIds.length, 0);
//         assertEq(stored.maximumNumberOfAttesters, 100);
//     }

//     // --------------------------------------------------------
//     // createTask OnlyOwner guard
//     // --------------------------------------------------------

//     function testCreateTaskAccessControl() public {
//         TaskDefinition memory def = TaskDefinition({
//             taskDefinitionId: 1,
//             name: "task",
//             baseRewardFeeForAttesters: 1 ether,
//             baseRewardFeeForPerformer: 0,
//             baseRewardFeeForAggregator: 0,
//             minimumVotingPower: 0,
//             restrictedOperatorIds: new address[](0),
//             maximumNumberOfAttesters: 100
//         });

//         vm.prank(nonOwner);
//         vm.expectRevert("Ownable: caller is not the owner");
//         avsProxy.createTask("task", 1, 5, 3, 60, 6);
//     }

//     function _defaultAVSParams() internal pure returns (avs.AVSParams memory p) {
//         p.sender = address(0x1234);
//         p.avsName = "TestAVS";
//         p.minStakeAmount = 1;
//         p.taskAddress = address(0x1);
//         p.slashAddress = address(0x2);
//         p.rewardAddress = address(0x3);
//         p.avsOwnerAddresses = new address[](0);
//         p.whitelistAddresses = new address[](0);
//         p.assetIDs = new string[](0);
//         p.avsUnbondingPeriod = 0;
//         p.minSelfDelegation = 0;
//         p.epochIdentifier = "epoch";
//         p.miniOptInOperators = 0;
//         p.minTotalStakeAmount = 0;
//         p.avsRewardProportion = 0;
//         p.avsSlashProportion = 0;
//     }

//     function testRegisterAVSEmitsEvent() public {
//         avs.AVSParams memory params = _defaultAVSParams();
//         vm.expectEmit(true, false, false, true);
//         emit TriggerXAvs.AVSRegistered(address(this), params.avsName);
//         avsProxy.registerAVS(params);
//     }

//     function testUpdateAVSEmitsEvent() public {
//         avs.AVSParams memory params = _defaultAVSParams();
//         vm.expectEmit(true, false, false, true);
//         emit TriggerXAvs.AVSUpdated(address(this), params.avsName);
//         avsProxy.updateAVS(params);
//     }
// } 