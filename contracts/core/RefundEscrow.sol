// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IRefundEscrow.sol";
import "../interfaces/IEventManager.sol";

contract RefundEscrow is IRefundEscrow, Ownable, ReentrancyGuard, Pausable {
    struct Payment {
        address payer;
        uint256 amount;
        PaymentStatus status;
        bool waitlistRefundEnabled;
    }

    IEventManager public eventManager;
    
    // eventId => ticketId => Payment
    mapping(uint256 => mapping(uint256 => Payment)) private payments;
    
    // Waitlist mapping
    mapping(uint256 => address[]) private eventWaitlist;
    
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5% platform fee

    modifier onlyEventManager() {
        require(msg.sender == address(eventManager), "Caller is not EventManager");
        _;
    }

    constructor(address _eventManager) Ownable(msg.sender) {
        eventManager = IEventManager(_eventManager);
    }

    function depositPayment(uint256 eventId, uint256 ticketId) 
        external 
        payable 
        override 
        nonReentrant 
        whenNotPaused 
    {
        require(msg.value > 0, "Payment amount must be greater than 0");
        
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
        require(payment.status == PaymentStatus.Pending, "Payment not in pending status");
        
        payment.status = PaymentStatus.Released;
        
        // Calculate fees
        uint256 platformFee = (payment.amount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = payment.amount - platformFee;
        
        // Get event details to pay organizer
        IEventManager.Event memory eventDetails = eventManager.getEvent(eventId);
        
        // Transfer payments
        (bool organizerSuccess, ) = payable(eventDetails.organizer).call{value: organizerPayment}("");
        (bool ownerSuccess, ) = payable(owner()).call{value: platformFee}("");
        
        require(organizerSuccess && ownerSuccess, "Transfer failed");
        
        emit PaymentReleased(eventId, eventDetails.organizer, organizerPayment);
    }

    function refundPayment(uint256 eventId, uint256 ticketId) 
        external 
        override 
        nonReentrant 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment not in pending status");
        
        // Check if refund is allowed
        IEventManager.Event memory eventDetails = eventManager.getEvent(eventId);
        require(
            eventDetails.cancelled || 
            payment.waitlistRefundEnabled ||
            msg.sender == owner(), 
            "Refund not allowed"
        );

        payment.status = PaymentStatus.Refunded;
        
        // Transfer refund
        (bool success, ) = payable(payment.payer).call{value: payment.amount}("");
        require(success, "Refund transfer failed");
        
        emit PaymentRefunded(eventId, payment.payer, payment.amount);
    }

    function enableWaitlistRefund(uint256 eventId, uint256 ticketId) 
        external 
        override 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Payment not in pending status");
        require(msg.sender == payment.payer, "Only ticket owner can enable waitlist refund");
        
        payment.waitlistRefundEnabled = true;
        eventWaitlist[eventId].push(msg.sender);
        
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
        override 
        returns (uint256) 
    {
        return payments[eventId][ticketId].amount;
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // In case of emergency
    function withdrawStuckFunds() external onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}