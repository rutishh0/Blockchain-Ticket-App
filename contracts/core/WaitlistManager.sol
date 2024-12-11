// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract WaitlistManager is Ownable, ReentrancyGuard, Pausable {
    struct WaitlistEntry {
        address user;
        uint256 timestamp;
        bool isActive;
        bool hasOffer;
        uint256 offerExpiry;
    }

    struct ZoneWaitlist {
        WaitlistEntry[] entries;
        mapping(address => uint256) userIndex;
        mapping(address => bool) isWaiting;
    }

    mapping(uint256 => mapping(uint256 => ZoneWaitlist)) private waitlists;
    
    uint256 public constant OFFER_DURATION = 24 hours;
    
    event JoinedWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event LeftWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseOffered(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseCompleted(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistOfferExpired(uint256 indexed eventId, uint256 indexed zoneId, address user);

    constructor() Ownable(msg.sender) {}

    function joinWaitlist(uint256 eventId, uint256 zoneId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(!waitlist.isWaiting[msg.sender], "Caller is already in the waitlist for this event and zone");
        
        waitlist.entries.push(WaitlistEntry({
            user: msg.sender,
            timestamp: block.timestamp,
            isActive: true,
            hasOffer: false,
            offerExpiry: 0
        }));
        
        waitlist.userIndex[msg.sender] = waitlist.entries.length - 1;
        waitlist.isWaiting[msg.sender] = true;
        
        emit JoinedWaitlist(eventId, zoneId, msg.sender);
    }

    function leaveWaitlist(uint256 eventId, uint256 zoneId) 
        external 
        whenNotPaused 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[msg.sender], "Caller is not in the waitlist for this event and zone");
        
        uint256 index = waitlist.userIndex[msg.sender];
        waitlist.entries[index].isActive = false;
        waitlist.isWaiting[msg.sender] = false;
        
        emit LeftWaitlist(eventId, zoneId, msg.sender);
    }

    function offerTicketToWaitlisted(uint256 eventId, uint256 zoneId, address user)
        external
        whenNotPaused
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[user], "User is not in the waitlist for this event and zone");
        
        uint256 index = waitlist.userIndex[user];
        WaitlistEntry storage entry = waitlist.entries[index];
        require(!entry.hasOffer, "User already has an active ticket offer for this event and zone");
        
        entry.hasOffer = true;
        entry.offerExpiry = block.timestamp + OFFER_DURATION;
        
        emit WaitlistPurchaseOffered(eventId, zoneId, user);
    }

    function completeWaitlistPurchase(uint256 eventId, uint256 zoneId)
        external
        whenNotPaused
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[msg.sender], "Caller is not in the waitlist for this event and zone");
        
        uint256 index = waitlist.userIndex[msg.sender];
        WaitlistEntry storage entry = waitlist.entries[index];
        require(entry.hasOffer, "Caller does not have an active ticket offer for this event and zone");
        require(block.timestamp <= entry.offerExpiry, "The ticket offer for this event and zone has expired");
        
        entry.isActive = false;
        waitlist.isWaiting[msg.sender] = false;
        
        emit WaitlistPurchaseCompleted(eventId, zoneId, msg.sender);
    }

    function expireOffer(uint256 eventId, uint256 zoneId, address user)
        external
        whenNotPaused
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[user], "User is not in the waitlist for this event and zone");
        
        uint256 index = waitlist.userIndex[user];
        WaitlistEntry storage entry = waitlist.entries[index];
        require(entry.hasOffer, "User does not have an active ticket offer for this event and zone");
        require(block.timestamp > entry.offerExpiry, "The ticket offer for this event and zone has not expired");
        
        entry.hasOffer = false;
        entry.offerExpiry = 0;
        
        emit WaitlistOfferExpired(eventId, zoneId, user);
    }

    function getNextWaitingUser(uint256 eventId, uint256 zoneId) 
        external 
        view 
        returns (address) 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        
        for (uint256 i = 0; i < waitlist.entries.length; i++) {
            WaitlistEntry memory entry = waitlist.entries[i];
            if (entry.isActive && !entry.hasOffer) {
                return entry.user;
            }
        }
        
        return address(0);
    }

    function getWaitlistPosition(uint256 eventId, uint256 zoneId, address user)
        external
        view
        returns (uint256)
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[user], "User is not in the waitlist for this event and zone");
        
        uint256 position = 1;
        uint256 userIndex = waitlist.userIndex[user];
        
        for (uint256 i = 0; i < userIndex; i++) {
            if (waitlist.entries[i].isActive) {
                position++;
            }
        }
        
        return position;
    }

    function getWaitlistLength(uint256 eventId, uint256 zoneId)
        external
        view
        returns (uint256)
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        uint256 activeCount = 0;
        
        for (uint256 i = 0; i < waitlist.entries.length; i++) {
            if (waitlist.entries[i].isActive) {
                activeCount++;
            }
        }
        
        return activeCount;
    }

    function isUserWaiting(uint256 eventId, uint256 zoneId, address user)
        external
        view
        returns (bool)
    {
        return waitlists[eventId][zoneId].isWaiting[user];
    }

    function hasActiveOffer(uint256 eventId, uint256 zoneId, address user)
        external
        view
        returns (bool)
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        if (!waitlist.isWaiting[user]) return false;
        
        uint256 index = waitlist.userIndex[user];
        WaitlistEntry memory entry = waitlist.entries[index];
        return entry.hasOffer && block.timestamp <= entry.offerExpiry;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function clearWaitlistEntry(uint256 eventId, uint256 zoneId, address user) 
        external 
        onlyOwner 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        if (waitlist.isWaiting[user]) {
            uint256 index = waitlist.userIndex[user];
            waitlist.entries[index].isActive = false;
            waitlist.isWaiting[user] = false;
            emit LeftWaitlist(eventId, zoneId, user);
        }
    }
}