// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract WaitlistManager is Ownable, ReentrancyGuard, Pausable {
    struct WaitlistEntry {
        address user;
        uint256 timestamp;
        bool isActive;
    }

    struct ZoneWaitlist {
        WaitlistEntry[] entries;
        mapping(address => uint256) userIndex; // Maps user address to their position in waitlist
        mapping(address => bool) isWaiting;    // Quick lookup for if user is in waitlist
    }

    // eventId => zoneId => ZoneWaitlist
    mapping(uint256 => mapping(uint256 => ZoneWaitlist)) private waitlists;
    
    // Events
    event JoinedWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event LeftWaitlist(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseOffered(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistPurchaseCompleted(uint256 indexed eventId, uint256 indexed zoneId, address user);
    event WaitlistOfferExpired(uint256 indexed eventId, uint256 indexed zoneId, address user);

    constructor() Ownable(msg.sender) {}

    // Join the waitlist for a specific event zone
    function joinWaitlist(uint256 eventId, uint256 zoneId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(!waitlist.isWaiting[msg.sender], "Already in waitlist");
        
        // Add new entry
        waitlist.entries.push(WaitlistEntry({
            user: msg.sender,
            timestamp: block.timestamp,
            isActive: true
        }));
        
        // Update mappings
        waitlist.userIndex[msg.sender] = waitlist.entries.length - 1;
        waitlist.isWaiting[msg.sender] = true;
        
        emit JoinedWaitlist(eventId, zoneId, msg.sender);
    }

    // Leave the waitlist
    function leaveWaitlist(uint256 eventId, uint256 zoneId) 
        external 
        whenNotPaused 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[msg.sender], "Not in waitlist");
        
        uint256 index = waitlist.userIndex[msg.sender];
        waitlist.entries[index].isActive = false;
        waitlist.isWaiting[msg.sender] = false;
        
        emit LeftWaitlist(eventId, zoneId, msg.sender);
    }

    // Get the next person in line
    function getNextWaitingUser(uint256 eventId, uint256 zoneId) 
        external 
        view 
        returns (address) 
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        
        for (uint256 i = 0; i < waitlist.entries.length; i++) {
            WaitlistEntry memory entry = waitlist.entries[i];
            if (entry.isActive) {
                return entry.user;
            }
        }
        
        return address(0);
    }

    // Get user's position in waitlist
    function getWaitlistPosition(uint256 eventId, uint256 zoneId, address user)
        external
        view
        returns (uint256)
    {
        ZoneWaitlist storage waitlist = waitlists[eventId][zoneId];
        require(waitlist.isWaiting[user], "Not in waitlist");
        
        uint256 position = 1;
        uint256 userIndex = waitlist.userIndex[user];
        
        for (uint256 i = 0; i < userIndex; i++) {
            if (waitlist.entries[i].isActive) {
                position++;
            }
        }
        
        return position;
    }

    // Get total number of people on waitlist
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

    // Check if a user is on the waitlist
    function isUserWaiting(uint256 eventId, uint256 zoneId, address user)
        external
        view
        returns (bool)
    {
        return waitlists[eventId][zoneId].isWaiting[user];
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency function to clear stuck entries
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