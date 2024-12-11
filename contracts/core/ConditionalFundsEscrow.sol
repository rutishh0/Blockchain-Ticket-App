// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IConditionalFundsEscrow.sol";
import "../interfaces/IEventManager.sol";

contract ConditionalFundsEscrow is IConditionalFundsEscrow, Ownable, ReentrancyGuard, Pausable {
    address private immutable _eventManager;
    mapping(uint256 => mapping(uint256 => Payment)) private payments;

    struct Payment {
        address payer;
        uint256 amount;
        PaymentStatus status;
        bool waitlistRefundEnabled;
    }

    modifier onlyEventManager() {
        require(msg.sender == _eventManager, "Caller is not the EventManager contract");
        _;
    }

    constructor(address eventManagerAddress) Ownable(msg.sender) {
        require(eventManagerAddress != address(0), "Invalid EventManager address");
        _eventManager = eventManagerAddress;
    }

    function depositPayment(uint256 eventId, uint256 ticketId)
        external
        payable
        override
        nonReentrant
        whenNotPaused
    {
        require(msg.value > 0, "Deposit amount must be greater than zero");
        require(payments[eventId][ticketId].payer == address(0), "Payment for this ticket already exists");

        payments[eventId][ticketId] = Payment({
            payer: msg.sender,
            amount: msg.value,
            status: PaymentStatus.Pending,
            waitlistRefundEnabled: false
        });

        emit PaymentDeposited(eventId, msg.sender, msg.value);
    }

    function releasePayment(uint256 eventId, uint256 ticketId)
        external
        override
        nonReentrant
        whenNotPaused
        onlyEventManager
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status");

        // Verify that the event has concluded
        require(
            IEventManager(_eventManager).hasEventConcluded(eventId),
            "Event has not concluded or does not meet release conditions"
        );

        payment.status = PaymentStatus.Released;

        // Send funds to the event organizer
        address organizer = IEventManager(_eventManager).getOrganizer(eventId);
        (bool success, ) = payable(organizer).call{value: payment.amount}("");
        require(success, "Transfer to event organizer failed");

        emit PaymentReleased(eventId, payment.payer, payment.amount);
    }

    function refundPayment(uint256 eventId, uint256 ticketId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status for refund");
        require(payment.payer == msg.sender, "Caller is not the original payer");

        uint256 amount = payment.amount;
        payment.status = PaymentStatus.Refunded;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Refund transfer to payer failed");

        emit PaymentRefunded(eventId, msg.sender, amount);
    }

    function enableWaitlistRefund(uint256 eventId, uint256 ticketId)
        external
        override
        whenNotPaused
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status to enable waitlist refund");
        require(payment.payer == msg.sender, "Caller is not the original payer");

        payment.waitlistRefundEnabled = true;
        emit WaitlistRefundEnabled(eventId, ticketId);
    }

    function getPaymentStatus(uint256 eventId, uint256 ticketId)
        external
        view
        override
        returns (PaymentStatus)
    {
        return payments[eventId][ticketId].status;
    }

    function getPaymentAmount(uint256 eventId, uint256 ticketId)
        external
        view
        returns (uint256)
    {
        return payments[eventId][ticketId].amount;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawStuckFunds() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
