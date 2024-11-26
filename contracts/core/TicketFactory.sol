// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract TicketFactory is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Ticket {
        uint256 eventId;
        uint256 price;
        bool used;
        uint256 seatNumber;
    }

    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => uint256) public eventToSupply;

    event TicketMinted(uint256 indexed tokenId, uint256 indexed eventId, uint256 price);
    event TicketUsed(uint256 indexed tokenId);

    constructor() ERC721("Event Ticket", "TCKT") Ownable(msg.sender) {}

    function createTicket(
        uint256 eventId,
        uint256 price,
        uint256 seatNumber
    ) public onlyOwner returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        tickets[newTokenId] = Ticket(eventId, price, false, seatNumber);
        eventToSupply[eventId]++;

        emit TicketMinted(newTokenId, eventId, price);
        return newTokenId;
    }

    function useTicket(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        require(!tickets[tokenId].used, "Ticket already used");
        
        tickets[tokenId].used = true;
        emit TicketUsed(tokenId);
    }
}