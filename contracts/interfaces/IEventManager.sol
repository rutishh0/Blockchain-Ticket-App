// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEventManager {
    struct Event {
        string name;
        uint256 date;
        uint256 basePrice;
        address organizer;
        bool cancelled;
        uint256 zoneCount;  // Instead of dynamic arrays
    }

    // Ensure the fields are in the exact order the tests expect:
    // (name, date, basePrice, organizer, cancelled, zoneCount)
    struct EventView {
        string name;
        uint256 date;
        uint256 basePrice;
        address organizer;
        bool cancelled;
        uint256 zoneCount;
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
    
    event TicketPurchased(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address buyer
    );

    function createEvent(
        string memory name,
        uint256 date,
        uint256 basePrice,
        uint256[] memory zoneCapacities,
        uint256[] memory zonePrices
    ) external returns (uint256);

    function cancelEvent(uint256 eventId) external;

    function purchaseTicket(uint256 eventId, uint256 zoneId) external payable;

    function getEvent(uint256 eventId) external view returns (EventView memory);

    function getZone(uint256 eventId, uint256 zoneId) external view returns (Zone memory);

    function getZonePrice(uint256 eventId, uint256 zoneId) external view returns (uint256);

    function getZoneCapacity(uint256 eventId, uint256 zoneId) external view returns (uint256);

    function getZoneCount(uint256 eventId) external view returns (uint256);

    function hasEventConcluded(uint256 eventId) external view returns (bool);

    function getOrganizer(uint256 eventId) external view returns (address);
}
