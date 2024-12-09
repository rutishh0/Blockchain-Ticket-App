// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IEventManager.sol";
import "../interfaces/IRefundEscrow.sol";

contract EventManager is IEventManager, Ownable, ReentrancyGuard, Pausable {
    uint256 private _eventIds;
    uint256 private _ticketIds;
    IRefundEscrow public refundEscrow;

    mapping(uint256 => Event) private _events;
    mapping(uint256 => mapping(uint256 => Zone)) private _eventZones;
    mapping(uint256 => mapping(address => bool)) private _hasTicket;
    mapping(uint256 => uint256) private _eventRevenue;

    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant CANCELLATION_WINDOW = 14 days;
    uint256 public constant MIN_EVENT_DELAY = 1 days;

    event RevenueWithdrawn(uint256 indexed eventId, address indexed organizer, uint256 amount);
    event RefundEscrowUpdated(address indexed newEscrow);

    constructor(address refundEscrowAddress) Ownable(msg.sender) {
        require(refundEscrowAddress != address(0), "Invalid escrow address");
        refundEscrow = IRefundEscrow(refundEscrowAddress);
    }

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
        require(date > block.timestamp + MIN_EVENT_DELAY, "Invalid date");
        require(zoneCapacities.length == zonePrices.length, "Array length mismatch");
        
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
            require(zonePrices[i] >= basePrice, "Zone price below base");
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
        require(event_.organizer == msg.sender || msg.sender == owner(), "Unauthorized");
        require(!event_.cancelled, "Already cancelled");
        require(block.timestamp <= event_.date, "Event already occurred");
        
        event_.cancelled = true;
        emit EventCancelled(eventId);
        
        // Notify RefundEscrow
        refundEscrow.cancelEvent(eventId);
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
        require(block.timestamp < event_.date, "Event passed");
        require(!_hasTicket[eventId][msg.sender], "Already has ticket");
        
        Zone storage zone = _eventZones[eventId][zoneId];
        require(zone.availableSeats > 0, "Zone sold out");
        require(msg.value >= zone.price, "Insufficient payment");
        
        uint256 ticketId = ++_ticketIds;
        zone.availableSeats--;
        _hasTicket[eventId][msg.sender] = true;
        
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = msg.value - platformFee;
        
        _eventRevenue[eventId] += organizerPayment;

        // Refund excess payment
        if (msg.value > zone.price) {
            uint256 excess = msg.value - zone.price;
            (bool refundSuccess, ) = payable(msg.sender).call{value: excess}("");
            require(refundSuccess, "Refund failed");
        }

        // Deposit payment to escrow
        refundEscrow.depositPayment{value: zone.price}(eventId, ticketId);
        
        emit TicketPurchased(eventId, ticketId, msg.sender);
    }

    function withdrawEventRevenue(uint256 eventId) external nonReentrant {
        Event storage event_ = _events[eventId];
        require(event_.organizer == msg.sender, "Not organizer");
        require(block.timestamp > event_.date, "Event not ended");
        
        uint256 amount = _eventRevenue[eventId];
        require(amount > 0, "No revenue");
        
        _eventRevenue[eventId] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit RevenueWithdrawn(eventId, msg.sender, amount);
    }

    function getEvent(uint256 eventId) external view override returns (Event memory) {
        return _events[eventId];
    }

    function getZone(uint256 eventId, uint256 zoneId) external view override returns (Zone memory) {
        return _eventZones[eventId][zoneId];
    }

    function hasEventConcluded(uint256 eventId) external view override returns (bool) {
        return block.timestamp > _events[eventId].date;
    }

    function getOrganizer(uint256 eventId) external view override returns (address) {
        return _events[eventId].organizer;
    }

    function getEventRevenue(uint256 eventId) external view returns (uint256) {
        return _eventRevenue[eventId];
    }

    function hasTicket(uint256 eventId, address user) external view returns (bool) {
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
