// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract TicketFactory is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Event {
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 price;
        bool isActive;
    }

    struct Ticket {
        uint256 eventId;
        uint256 price;
        bool used;
        uint256 seatNumber;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;

    event EventCreated(uint256 indexed eventId, uint256 maxSupply, uint256 price);
    event TicketMinted(uint256 indexed tokenId, uint256 indexed eventId, uint256 price);
    event TicketUsed(uint256 indexed tokenId);

    constructor() ERC721("Event Ticket", "TCKT") Ownable(msg.sender) {}

    // Creates a new event
    function createEvent(
        uint256 eventId,
        uint256 maxSupply,
        uint256 price
    ) public onlyOwner {
        require(!events[eventId].isActive, "Event already exists");
        require(maxSupply > 0, "Invalid supply");
        require(price > 0, "Invalid price");

        events[eventId] = Event({
            maxSupply: maxSupply,
            currentSupply: 0,
            price: price,
            isActive: true
        });

        emit EventCreated(eventId, maxSupply, price);
    }

    // Issues a new ticket
    function issueTicket(
        address to,
        uint256 eventId,
        uint256 seatNumber
    ) public onlyOwner returns (uint256) {
        Event storage event_ = events[eventId];
        require(event_.isActive, "Event not active");
        require(event_.currentSupply < event_.maxSupply, "Event sold out");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(to, newTokenId);
        tickets[newTokenId] = Ticket({
            eventId: eventId,
            price: event_.price,
            used: false,
            seatNumber: seatNumber
        });

        event_.currentSupply++;

        emit TicketMinted(newTokenId, eventId, event_.price);
        return newTokenId;
    }

    // Gets ticket details
    function getTicketDetails(uint256 tokenId) 
        public 
        view 
        returns (
            uint256 eventId,
            uint256 price,
            bool used,
            uint256 seatNumber
        ) 
    {
        Ticket memory ticket = tickets[tokenId];
        return (
            ticket.eventId,
            ticket.price,
            ticket.used,
            ticket.seatNumber
        );
    }

    // Marks ticket as used
    function useTicket(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        require(!tickets[tokenId].used, "Ticket already used");
        
        tickets[tokenId].used = true;
        emit TicketUsed(tokenId);
    }
}