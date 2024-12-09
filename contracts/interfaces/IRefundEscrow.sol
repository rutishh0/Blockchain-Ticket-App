// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRefundEscrow {
    enum PaymentStatus { Pending, Released, Refunded }
    
    event PaymentDeposited(uint256 indexed eventId, address indexed payer, uint256 amount);
    event PaymentReleased(uint256 indexed eventId, address indexed payee, uint256 amount);
    event PaymentRefunded(uint256 indexed eventId, address indexed payer, uint256 amount);
    event WaitlistRefundEnabled(uint256 indexed eventId, uint256 indexed ticketId);

    function depositPayment(uint256 eventId, uint256 ticketId) external payable;
    function releasePayment(uint256 eventId, uint256 ticketId) external;
    function refundPayment(uint256 eventId, uint256 ticketId) external;
    function enableWaitlistRefund(uint256 eventId, uint256 ticketId) external;
    function getPaymentStatus(uint256 eventId, uint256 ticketId) external view returns (PaymentStatus);
    function getPaymentAmount(uint256 eventId, uint256 ticketId) external view returns (uint256);
    function cancelEvent(uint256 eventId) external;
}