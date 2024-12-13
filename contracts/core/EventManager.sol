// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IEventManager.sol";
import "../interfaces/IRefundEscrow.sol";

contract EventManager is IEventManager, Ownable, ReentrancyGuard, Pausable {
    uint256 private _eventIds;
    uint256 private _ticketIds;
    IRefundEscrow public refundEscrow;

    // eventId => Event struct
    mapping(uint256 => Event) private _events;
    // eventId => zoneId => Zone struct
    mapping(uint256 => mapping(uint256 => Zone)) private _eventZones;
    // eventId => user => bool (true if user has a ticket for this event)
    mapping(uint256 => mapping(address => bool)) private _hasTicket;
    // eventId => accumulated revenue for organizer
    mapping(uint256 => uint256) private _eventRevenue;
    // eventId => number of zones
    mapping(uint256 => uint256) private _zoneCount;

    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant MIN_EVENT_DELAY = 1 days;

    // Add the missing event declarations here
    event RefundEscrowUpdated(address indexed newEscrow);
    event RevenueWithdrawn(uint256 indexed eventId, address indexed organizer, uint256 amount);

    constructor() Ownable(msg.sender) {
        _eventIds = 0;
        _ticketIds = 0;
    }

    // Rest of the contract remains exactly the same...
    // ... all other functions remain unchanged ...

    function setRefundEscrow(address newEscrow) external onlyOwner {
        require(newEscrow != address(0), "Invalid escrow address");
        refundEscrow = IRefundEscrow(newEscrow);
        emit RefundEscrowUpdated(newEscrow);
    }

    function createEvent(
        string memory name,
        uint256 date,
        uint256 basePrice,
        uint256[] memory zoneCapacities,
        uint256[] memory zonePrices
    ) external override whenNotPaused returns (uint256) {
        require(bytes(name).length > 0, "Event name cannot be empty");
        require(date > block.timestamp + MIN_EVENT_DELAY, "Event date must be at least one day in the future");
        require(zoneCapacities.length == zonePrices.length, "Zone capacities and prices arrays must match");
        require(zoneCapacities.length > 0, "At least one zone required");
        require(basePrice > 0, "Base price must be greater than zero");

        _eventIds++;
        uint256 newEventId = _eventIds;

        _events[newEventId] = Event({
            name: name,
            date: date,
            basePrice: basePrice,
            organizer: msg.sender,
            cancelled: false,
            zoneCount: zoneCapacities.length
        });

        for (uint256 i = 0; i < zoneCapacities.length; i++) {
            require(zoneCapacities[i] > 0, "Zone capacity must be greater than zero");
            require(zonePrices[i] >= basePrice, "Zone price must be >= base price");
            _eventZones[newEventId][i] = Zone({
                capacity: zoneCapacities[i],
                price: zonePrices[i],
                availableSeats: zoneCapacities[i]
            });
        }

        _zoneCount[newEventId] = zoneCapacities.length;
        emit EventCreated(newEventId, name, date, msg.sender);
        return newEventId;
    }

    function cancelEvent(uint256 eventId) external override whenNotPaused {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        Event storage event_ = _events[eventId];
        require(event_.organizer == msg.sender || msg.sender == owner(), "Not event organizer or owner");
        require(!event_.cancelled, "Event already cancelled");
        require(block.timestamp <= event_.date, "Event already occurred");

        event_.cancelled = true;
        emit EventCancelled(eventId);

        if (address(refundEscrow) != address(0)) {
            refundEscrow.cancelEvent(eventId);
        }
    }

    function purchaseTicket(uint256 eventId, uint256 zoneId)
        external
        payable
        override
        nonReentrant
        whenNotPaused
    {
        require(eventId <= _eventIds && eventId > 0, "Invalid event ID");
        Event storage event_ = _events[eventId];
        require(!event_.cancelled, "Event cancelled");
        require(block.timestamp < event_.date, "Event already occurred");
        require(!_hasTicket[eventId][msg.sender], "Already purchased ticket");
        require(zoneId < event_.zoneCount, "Invalid zone ID");

        Zone storage zone = _eventZones[eventId][zoneId];
        require(zone.availableSeats > 0, "No seats available in zone");
        require(msg.value >= zone.price, "Insufficient payment");

        _ticketIds++;
        uint256 newTicketId = _ticketIds;

        zone.availableSeats--;
        _hasTicket[eventId][msg.sender] = true;

        // Calculate fees and organizer revenue
        uint256 platformFee = (zone.price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = zone.price - platformFee;

        // Store organizer's payment as event revenue
        _eventRevenue[eventId] += organizerPayment;

        // Send platform fee immediately to owner
        (bool feeSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(feeSuccess, "Platform fee transfer failed");

        // Refund any excess payment
        if (msg.value > zone.price) {
            uint256 excess = msg.value - zone.price;
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
            require(refundSuccess, "Refund failed");
        }

        emit TicketPurchased(eventId, newTicketId, msg.sender);
    }

    function withdrawEventRevenue(uint256 eventId) external nonReentrant {
        require(eventId <= _eventIds && eventId > 0, "Invalid event ID");
        Event storage event_ = _events[eventId];
        require(event_.organizer == msg.sender, "Caller not organizer");
        require(block.timestamp > event_.date, "Event not ended yet");

        uint256 amount = _eventRevenue[eventId];
        require(amount > 0, "No revenue");

        _eventRevenue[eventId] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer to organizer failed");

        emit RevenueWithdrawn(eventId, msg.sender, amount);
    }

    function getEvent(uint256 eventId) external view override returns (EventView memory) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        Event storage event_ = _events[eventId];
        
        return EventView({
            name: event_.name,
            date: event_.date,
            basePrice: event_.basePrice,
            organizer: event_.organizer,
            cancelled: event_.cancelled,
            zoneCount: event_.zoneCount
        });
    }

    function getEventData(uint256 eventId) external view returns (
        string memory name,
        uint256 date,
        uint256 basePrice,
        address organizer,
        bool cancelled,
        uint256 zoneCount
    ) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        Event storage event_ = _events[eventId];
        return (
            event_.name,
            event_.date,
            event_.basePrice,
            event_.organizer,
            event_.cancelled,
            event_.zoneCount
        );
    }

    function getZone(uint256 eventId, uint256 zoneId) external view override returns (Zone memory) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        require(zoneId < _events[eventId].zoneCount, "Zone does not exist");
        return _eventZones[eventId][zoneId];
    }

    function getZonePrice(uint256 eventId, uint256 zoneId) external view override returns (uint256) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        require(zoneId < _events[eventId].zoneCount, "Zone does not exist");
        return _eventZones[eventId][zoneId].price;
    }

    function getZoneCapacity(uint256 eventId, uint256 zoneId) external view override returns (uint256) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        require(zoneId < _events[eventId].zoneCount, "Zone does not exist");
        return _eventZones[eventId][zoneId].capacity;
    }

    function getZoneCount(uint256 eventId) external view override returns (uint256) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        return _events[eventId].zoneCount;
    }

    function hasEventConcluded(uint256 eventId) external view override returns (bool) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        return block.timestamp > _events[eventId].date;
    }

    function getOrganizer(uint256 eventId) external view override returns (address) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        return _events[eventId].organizer;
    }

    function getEventRevenue(uint256 eventId) external view returns (uint256) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        return _eventRevenue[eventId];
    }

    function hasTicket(uint256 eventId, address user) external view returns (bool) {
        require(eventId <= _eventIds && eventId > 0, "Event ID does not exist");
        return _hasTicket[eventId][user];
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}