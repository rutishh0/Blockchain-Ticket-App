// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IEventManager.sol";

contract EventManager is IEventManager, Ownable, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;
    Counters.Counter private _eventIds;

    mapping(uint256 => Event) private _events;
    mapping(uint256 => mapping(uint256 => Zone)) private _eventZones;
    mapping(uint256 => mapping(address => bool)) private _hasTicket;

    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5% platform fee

    constructor() Ownable(msg.sender) {}

    function createEvent(
        string memory name,
        uint256 date,
        uint256 basePrice,
        uint256[] memory zoneCapacities,
        uint256[] memory zonePrices
    ) external override whenNotPaused returns (uint256) {
        require(date > block.timestamp, "Event date must be in the future");
        require(zoneCapacities.length == zonePrices.length, "Zone arrays must match");
        require(zoneCapacities.length > 0, "Must have at least one zone");

        _eventIds.increment();
        uint256 newEventId = _eventIds.current();

        _events[newEventId] = Event({
            name: name,
            date: date,
            basePrice: basePrice,
            organizer: msg.sender,
            cancelled: false,
            zoneCapacities: zoneCapacities,
            zonePrices: zonePrices
        });

        // Initialize zones
        for (uint256 i = 0; i < zoneCapacities.length; i++) {
            _eventZones[newEventId][i] = Zone({
                capacity: zoneCapacities[i],
                price: zonePrices[i],
                availableSeats: zoneCapacities[i]
            });
        }

        emit EventCreated(newEventId, name, date, msg.sender);
        return newEventId;
    }

    function cancelEvent(uint256 eventId) external override whenNotPaused {
        Event storage eventDetails = _events[eventId];
        require(msg.sender == eventDetails.organizer, "Only organizer can cancel");
        require(!eventDetails.cancelled, "Event already cancelled");
        
        eventDetails.cancelled = true;
        emit EventCancelled(eventId);
    }

    function purchaseTicket(uint256 eventId, uint256 zoneId) 
        external 
        payable 
        override 
        nonReentrant 
        whenNotPaused 
    {
        Event storage eventDetails = _events[eventId];
        require(!eventDetails.cancelled, "Event is cancelled");
        require(eventDetails.date > block.timestamp, "Event has already occurred");
        require(!_hasTicket[eventId][msg.sender], "Already has ticket");

        Zone storage zone = _eventZones[eventId][zoneId];
        require(zone.availableSeats > 0, "Zone is sold out");
        require(msg.value == zone.price, "Incorrect payment amount");

        // Calculate platform fee
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = msg.value - platformFee;

        // Transfer payments
        (bool organizerSuccess, ) = payable(eventDetails.organizer).call{value: organizerPayment}("");
        (bool ownerSuccess, ) = payable(owner()).call{value: platformFee}("");
        
        require(organizerSuccess && ownerSuccess, "Transfer failed");

        // Update state
        zone.availableSeats--;
        _hasTicket[eventId][msg.sender] = true;

        emit TicketPurchased(eventId, _eventIds.current(), msg.sender);
    }

    function getEvent(uint256 eventId) external view override returns (Event memory) {
        return _events[eventId];
    }

    function getZone(uint256 eventId, uint256 zoneId) external view override returns (Zone memory) {
        return _eventZones[eventId][zoneId];
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}