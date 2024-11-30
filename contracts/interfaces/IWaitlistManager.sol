// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWaitlistManager {
    // Structs
    struct WaitlistEntry {
        address user;
        uint256 timestamp;
        bool isActive;
    }

    // Events
    event JoinedWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event LeftWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseOffered(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseCompleted(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistOfferExpired(uint256 indexed eventId, uint256 indexed zoneId, address user);

    // Core functions
    function joinWaitlist(uint256 eventId, uint256 zoneId) external;
    function leaveWaitlist(uint256 eventId, uint256 zoneId) external;
    
    // View functions
    function getNextWaitingUser(uint256 eventId, uint256 zoneId) external view returns (address);
    function getWaitlistPosition(uint256 eventId, uint256 zoneId, address user) external view returns (uint256);
    function getWaitlistLength(uint256 eventId, uint256 zoneId) external view returns (uint256);
    function isUserWaiting(uint256 eventId, uint256 zoneId, address user) external view returns (bool);
}