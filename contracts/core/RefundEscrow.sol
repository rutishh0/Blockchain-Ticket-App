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
    
    struct Payment {
        address payer;
        uint256 amount;
        PaymentStatus status;
        bool waitlistRefundEnabled;
    }

    

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
        require(payment.status == PaymentStatus.Pending, "Invalid payment status");
        
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
        
        uint256 amount = payment.amount;
        payment.status = PaymentStatus.Refunded;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Refund transfer failed");
        
        emit PaymentRefunded(eventId, msg.sender, amount);
    }

    function enableWaitlistRefund(uint256 eventId, uint256 ticketId) 
        external 
        override 
        whenNotPaused 
    {
        Payment storage payment = payments[eventId][ticketId];
        require(payment.status == PaymentStatus.Pending, "Invalid payment status");
        require(payment.payer == msg.sender, "Not the payer");
        
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