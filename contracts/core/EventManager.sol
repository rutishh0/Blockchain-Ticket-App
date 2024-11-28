// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IEventManager.sol";

contract EventManager is IEventManager, Ownable, ReentrancyGuard, Pausable {
    uint256 private _eventIds;

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
        _eventIds++;
        uint256 newEventId = _eventIds;
        
        _events[newEventId] = Event({
            name: name,
            date: date,
            basePrice: basePrice,
            organizer: msg.sender,
            cancelled: false,
            zoneCapacities: zoneCapacities,
            zonePrices: zonePrices
        });

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
        Event storage event_ = _events[eventId];
        require(event_.organizer == msg.sender, "Not event organizer");
        require(!event_.cancelled, "Event already cancelled");
        
        event_.cancelled = true;
        emit EventCancelled(eventId);
    }

    function purchaseTicket(uint256 eventId, uint256 zoneId) 
        external 
        payable 
        override 
        nonReentrant 
        whenNotPaused 
    {
        Event storage event_ = _events[eventId];
        require(!event_.cancelled, "Event cancelled");
        require(!_hasTicket[eventId][msg.sender], "Already has ticket");
        
        Zone storage zone = _eventZones[eventId][zoneId];
        require(zone.availableSeats > 0, "Zone sold out");
        require(msg.value >= zone.price, "Insufficient payment");
        
        zone.availableSeats--;
        _hasTicket[eventId][msg.sender] = true;
        
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = msg.value - platformFee;
        
        (bool success, ) = payable(event_.organizer).call{value: organizerPayment}("");
        require(success, "Transfer to organizer failed");
        
        emit TicketPurchased(eventId, _eventIds, msg.sender);
    }

    function getEvent(uint256 eventId) external view override returns (Event memory) {
        return _events[eventId];
    }

    function getZone(uint256 eventId, uint256 zoneId) external view override returns (Zone memory) {
        return _eventZones[eventId][zoneId];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}