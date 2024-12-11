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

    // Event emitted when a new event is created
    event EventCreated(
        uint256 indexed eventId,
        string name,
        uint256 date,
        address organizer
    );
    
    // Event emitted when an event is cancelled
    event EventCancelled(uint256 indexed eventId);
    
    // Event emitted when a ticket is purchased
    event TicketPurchased(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        address buyer
    );

    /**
     * @notice Creates a new event.
     * @param name Name of the event.
     * @param date Date of the event (timestamp).
     * @param basePrice Base price for tickets.
     * @param zoneCapacities Array of capacities for each zone.
     * @param zonePrices Array of prices for each zone.
     * @return eventId ID of the created event.
     */
    function createEvent(
        string memory name,
        uint256 date,
        uint256 basePrice,
        uint256[] memory zoneCapacities,
        uint256[] memory zonePrices
    ) external returns (uint256);

    /**
     * @notice Cancels an event.
     * @param eventId ID of the event to cancel.
     */
    function cancelEvent(uint256 eventId) external;

    /**
     * @notice Purchases a ticket for a specific event and zone.
     * @param eventId ID of the event.
     * @param zoneId ID of the zone.
     */
    function purchaseTicket(uint256 eventId, uint256 zoneId) external payable;

    /**
     * @notice Retrieves details of a specific event.
     * @param eventId ID of the event.
     * @return The basic details of the event as an `EventView` struct.
     */
    function getEvent(uint256 eventId) external view returns (EventView memory);

    /**
     * @notice Retrieves details of a specific zone in an event.
     * @param eventId ID of the event.
     * @param zoneId ID of the zone.
     * @return The details of the zone as a `Zone` struct.
     */
    function getZone(uint256 eventId, uint256 zoneId) external view returns (Zone memory);

    /**
     * @notice Retrieves price for a specific zone.
     * @param eventId ID of the event.
     * @param zoneId ID of the zone.
     * @return The price of the zone.
     */
    function getZonePrice(uint256 eventId, uint256 zoneId) external view returns (uint256);

    /**
     * @notice Retrieves capacity for a specific zone.
     * @param eventId ID of the event.
     * @param zoneId ID of the zone.
     * @return The capacity of the zone.
     */
    function getZoneCapacity(uint256 eventId, uint256 zoneId) external view returns (uint256);

    /**
     * @notice Gets the number of zones for an event.
     * @param eventId ID of the event.
     * @return The number of zones.
     */
    function getZoneCount(uint256 eventId) external view returns (uint256);

    /**
     * @notice Checks if an event has concluded.
     * @param eventId ID of the event.
     * @return True if the event has concluded, false otherwise.
     */
    function hasEventConcluded(uint256 eventId) external view returns (bool);

    /**
     * @notice Retrieves the organizer of a specific event.
     * @param eventId ID of the event.
     * @return The address of the organizer.
     */
    function getOrganizer(uint256 eventId) external view returns (address);
}