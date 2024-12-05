// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IConditionalFundRelease {
address public owner;
address public beneficiary;
uint256 public amount;

enum ConditionsStatus {NotMet, Met, Released}
ConditionStatus public conditionsStatus;

event FundsDeposited (address indexed depositor, uint256 amount);
event FundsReleased (address indexed beneficicary, uint256 amount);
event ConditionUpdated (ConditionStatus status);

modifier onlyOwner () {
    require(msg.sender == owner, "Only owner can perform this action");
    _;
}

modifier inState (ConditionStatus _state) {
    require(conditionStatus == _state, "Invalid state for this action");
    _;





}
