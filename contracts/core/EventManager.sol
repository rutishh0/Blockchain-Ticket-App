// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IEventManager.sol";
import "../interfaces/IRefundEscrow.sol";

contract EventManager is IEventManager, Ownable, ReentrancyGuard, Pausable {
    uint256 private _eventIds;
    IRefundEscrow public refundEscrow;

    struct Event {
        string name;
        uint256 date;
        uint256 basePrice;
        address organizer;
        bool cancelled;
        uint256[] zoneCapacities;
        uint256[] zonePrices;
        uint256 totalRevenue;
        uint256 refundDeadline;
    }

    struct Zone {
        uint256 capacity;
        uint256 price;
        uint256 availableSeats;
        uint256 revenue;
    }

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
            zonePrices: zonePrices,
            totalRevenue: 0,
            refundDeadline: date - CANCELLATION_WINDOW
        });

        for (uint256 i = 0; i < zoneCapacities.length; i++) {
            require(zonePrices[i] >= basePrice, "Zone price below base");
            _eventZones[newEventId][i] = Zone({
                capacity: zoneCapacities[i],
                price: zonePrices[i],
                availableSeats: zoneCapacities[i],
                revenue: 0
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
        
        zone.availableSeats--;
        zone.revenue += msg.value;
        _hasTicket[eventId][msg.sender] = true;
        
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 organizerPayment = msg.value - platformFee;
        
        _eventRevenue[eventId] += organizerPayment;
        event_.totalRevenue += msg.value;
        
        // Deposit payment to escrow
        refundEscrow.depositPayment{value: msg.value}(eventId, _eventIds);
        
        emit TicketPurchased(eventId, _eventIds, msg.sender);
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