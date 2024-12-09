// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IRefundEscrow.sol";
import "../interfaces/IEventManager.sol";

contract RefundEscrow is IRefundEscrow, Ownable, ReentrancyGuard, Pausable {
    address private immutable _eventManager;
    mapping(uint256 => mapping(uint256 => Payment)) private payments;
    mapping(uint256 => bool) private eventCancelled;
    
    struct Payment {
        address payer;
        uint256 amount;
        PaymentStatus status;
        bool waitlistRefundEnabled;
        uint256 refundDeadline;
        bool isCancelled;
    }

    uint256 public constant REFUND_WINDOW = 14 days;
    uint256 public constant CANCELLATION_FEE_PERCENT = 5;

    modifier onlyEventManager() {
        require(msg.sender == _eventManager, "Only EventManager can call");
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
        require(msg.value > 0, "Payment required");
        require(payments[eventId][ticketId].payer == address(0), "Payment exists");
        require(!eventCancelled[eventId], "Event cancelled");

        payments[eventId][ticketId] = Payment({
            payer: msg.sender,
            amount: msg.value,
            status: PaymentStatus.Pending,
            waitlistRefundEnabled: false,
            refundDeadline: block.timestamp + REFUND_WINDOW,
            isCancelled: false
        });

        emit PaymentDeposited(eventId, msg.sender, msg.value);
    }

    function cancelTicket(uint256 eventId, uint256 ticketId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.payer == msg.sender, "Not ticket owner");
        require(!payment.isCancelled, "Already cancelled");
        require(block.timestamp <= payment.refundDeadline, "Refund window closed");

        payment.isCancelled = true;
        uint256 refundAmount = payment.amount;
        
        if (block.timestamp > payment.refundDeadline - 7 days) {
            uint256 cancellationFee = (payment.amount * CANCELLATION_FEE_PERCENT) / 100;
            refundAmount = payment.amount - cancellationFee;
            payable(owner()).transfer(cancellationFee);
        }

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund transfer failed");
        
        emit TicketCancelled(eventId, ticketId, refundAmount);
    }

    function cancelEvent(uint256 eventId) 
        external 
        onlyEventManager 
        whenNotPaused 
    {
        eventCancelled[eventId] = true;
        emit EventCancelled(eventId);
    }

    function processEventCancellationRefund(uint256 eventId, uint256 ticketId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(eventCancelled[eventId], "Event not cancelled");
        Payment storage payment = payments[eventId][ticketId];
        require(payment.payer == msg.sender, "Not ticket owner");
        require(!payment.isCancelled, "Already refunded");

        payment.isCancelled = true;
        uint256 refundAmount = payment.amount;
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund transfer failed");
        
        emit EventCancellationRefunded(eventId, ticketId, refundAmount);
    }

    function releasePayment(uint256 eventId, uint256 ticketId) 
        external 
        override 
        nonReentrant 
        whenNotPaused 
        onlyEventManager 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Invalid payment status");
        require(!payment.isCancelled, "Ticket cancelled");
        require(!eventCancelled[eventId], "Event cancelled");
        
        payment.status = PaymentStatus.Released;
        emit PaymentReleased(eventId, payment.payer, payment.amount);
    }

    function refundPayment(uint256 eventId, uint256 ticketId) 
        external 
        override 
        nonReentrant 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Invalid payment status");
        require(payment.payer == msg.sender, "Not the payer");
        require(block.timestamp <= payment.refundDeadline, "Refund window closed");
        
        uint256 refundAmount = payment.amount;
        payment.status = PaymentStatus.Refunded;
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund transfer failed");
        
        emit PaymentRefunded(eventId, msg.sender, refundAmount);
    }

    function enableWaitlistRefund(uint256 eventId, uint256 ticketId) 
        external 
        override 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Invalid payment status");
        require(payment.payer == msg.sender, "Not the payer");
        require(!payment.isCancelled, "Ticket cancelled");
        
        payment.waitlistRefundEnabled = true;
        emit WaitlistRefundEnabled(eventId, ticketId);
    }

    function getPaymentDetails(uint256 eventId, uint256 ticketId) 
        external 
        view 
        returns (
            address payer,
            uint256 amount,
            PaymentStatus status,
            bool waitlistRefundEnabled,
            uint256 refundDeadline,
            bool isCancelled
        ) 
    {
        Payment memory payment = payments[eventId][ticketId];
        return (
            payment.payer,
            payment.amount,
            payment.status,
            payment.waitlistRefundEnabled,
            payment.refundDeadline,
            payment.isCancelled
        );
    }

    function isEventCancelled(uint256 eventId) external view returns (bool) {
        return eventCancelled[eventId];
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
        override 
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