// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IRefundEscrow.sol";
import "../interfaces/IEventManager.sol";

contract RefundEscrow is IRefundEscrow, Ownable, ReentrancyGuard, Pausable {
    event TicketCancelled(uint256 indexed eventId, uint256 indexed ticketId, uint256 refundAmount);
    event EventCancelled(uint256 indexed eventId);
    event EventCancellationRefunded(uint256 indexed eventId, uint256 indexed ticketId, uint256 refundAmount);
    
    address private immutable _eventManager;
    mapping(uint256 => mapping(uint256 => Payment)) private payments;
    mapping(uint256 => bool) private eventCancelled;
    mapping(uint256 => mapping(uint256 => address)) private originalPayers;
    
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
        require(msg.sender == _eventManager, "Caller is not the EventManager");
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
        require(msg.value > 0, "Payment amount must be greater than zero");
        require(payments[eventId][ticketId].payer == address(0), "A payment for this ticket already exists");
        require(!eventCancelled[eventId], "Cannot deposit payment for a cancelled event");

        // Store the original transaction sender
        address originalPayer = tx.origin;
        originalPayers[eventId][ticketId] = originalPayer;

        payments[eventId][ticketId] = Payment({
            payer: originalPayer,
            amount: msg.value,
            status: PaymentStatus.Pending,
            waitlistRefundEnabled: false,
            refundDeadline: block.timestamp + REFUND_WINDOW,
            isCancelled: false
        });

        emit PaymentDeposited(eventId, originalPayer, msg.value);
    }

    function cancelTicket(uint256 eventId, uint256 ticketId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.payer == originalPayers[eventId][ticketId], "Caller is not the owner of the ticket");
        require(!payment.isCancelled, "This ticket has already been cancelled");
        require(block.timestamp <= payment.refundDeadline, "Refund request exceeds the allowable refund window");

        payment.isCancelled = true;
        uint256 refundAmount = payment.amount;
        
        if (block.timestamp > payment.refundDeadline - 7 days) {
            uint256 cancellationFee = (payment.amount * CANCELLATION_FEE_PERCENT) / 100;
            refundAmount = payment.amount - cancellationFee;
            payable(owner()).transfer(cancellationFee);
        }

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Transfer of refund amount to ticket owner failed");
        
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
        require(eventCancelled[eventId], "Refunds cannot be processed for an event that has not been cancelled");
        Payment storage payment = payments[eventId][ticketId];
        require(payment.payer == originalPayers[eventId][ticketId], "Caller is not the owner of the ticket");
        require(!payment.isCancelled, "This ticket has already been refunded");

        payment.isCancelled = true;
        uint256 refundAmount = payment.amount;
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Transfer of refund amount failed");
        
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
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status to be released");
        require(!payment.isCancelled, "Cannot release payment for a cancelled ticket");
        require(!eventCancelled[eventId], "Cannot release payment for a cancelled event");
        
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
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status to be refunded");
        require(msg.sender == originalPayers[eventId][ticketId], "Caller is not the payer of this ticket");
        require(block.timestamp <= payment.refundDeadline, "Cannot refund payment as the refund window has expired");
        
        uint256 refundAmount = payment.amount;
        payment.status = PaymentStatus.Refunded;
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Transfer of refund amount to payer failed");
        
        emit PaymentRefunded(eventId, msg.sender, refundAmount);
    }

    function enableWaitlistRefund(uint256 eventId, uint256 ticketId) 
        external 
        override 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment must be in a Pending status to be refunded");
        require(msg.sender == originalPayers[eventId][ticketId], "Caller is not the payer of this ticket");
        require(!payment.isCancelled, "Cannot enable waitlist refund for a cancelled ticket");
        
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

    function getOriginalPayer(uint256 eventId, uint256 ticketId) 
        external 
        view 
        returns (address) 
    {
        return originalPayers[eventId][ticketId];
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