// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEventManager {
    struct Event {
        string name;
        uint256 date;
        uint256 basePrice;
        address organizer;
        bool cancelled;
        uint256[] zoneCapacities;
        uint256[] zonePrices;
    }

    struct Zone {
        uint256 capacity;
        uint256 price;
        uint256 availableSeats;
    }

    event EventCreated(
        uint256 indexed eventId,
        string name,
        uint256 date,
        address organizer
    );
    
    event EventCancelled(uint256 indexed eventId);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address buyer);

    function createEvent(
        string memory name,
        uint256 date,
        uint256 basePrice,
        uint256[] memory zoneCapacities,
        uint256[] memory zonePrices
    ) external returns (uint256);

    function cancelEvent(uint256 eventId) external;
    function purchaseTicket(uint256 eventId, uint256 zoneId) external payable;
    function getEvent(uint256 eventId) external view returns (Event memory);
    function getZone(uint256 eventId, uint256 zoneId) external view returns (Zone memory);
}