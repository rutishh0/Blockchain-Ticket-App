// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWaitlistManager {
    function getNextWaitingUser(uint256 eventId, uint256 zoneId) external view returns (address);
    function isUserWaiting(uint256 eventId, uint256 zoneId, address user) external view returns (bool);
    function getWaitlistLength(uint256 eventId, uint256 zoneId) external view returns (uint256);
}

contract TicketFactory is ERC721, Ownable, ReentrancyGuard {
    uint256 private _tokenIds;
    IWaitlistManager public waitlistManager;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant MAX_RESALE_MARKUP = 110; // 110% of original price

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
        bool isWaitlisted;
        bool isResale;
        uint256 resalePrice;
    }

    mapping(uint256 => Event) public events;
    mapping(uint256 => Ticket) public tickets;
    
    event EventCreated(uint256 indexed eventId, uint256 maxSupply, uint256 price);
    event TicketMinted(uint256 indexed tokenId, uint256 indexed eventId, uint256 price);
    event TicketUsed(uint256 indexed tokenId);
    event WaitlistTicketIssued(uint256 indexed tokenId, uint256 indexed eventId, address indexed user);
    event TicketListedForResale(uint256 indexed tokenId, uint256 price);
    event TicketPurchased(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event TicketResold(uint256 indexed tokenId, address indexed buyer, uint256 price);

    constructor(address waitlistManagerAddress) ERC721("Event Ticket", "TCKT") Ownable(msg.sender) {
        require(waitlistManagerAddress != address(0), "Invalid waitlist manager address");
        waitlistManager = IWaitlistManager(waitlistManagerAddress);
    }

    function setWaitlistManager(address newWaitlistManager) external onlyOwner {
        require(newWaitlistManager != address(0), "Invalid address");
        waitlistManager = IWaitlistManager(newWaitlistManager);
    }

    function createEvent(
        uint256 eventId,
        uint256 maxSupply,
        uint256 price
    ) external onlyOwner {
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

    function issueTicket(
        address to,
        uint256 eventId,
        uint256 seatNumber
    ) external onlyOwner returns (uint256) {
        Event storage event_ = events[eventId];
        require(event_.isActive, "Event not active");
        require(event_.currentSupply < event_.maxSupply, "Event sold out");

        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _mint(to, newTokenId);
        tickets[newTokenId] = Ticket({
            eventId: eventId,
            price: event_.price,
            used: false,
            seatNumber: seatNumber,
            isWaitlisted: waitlistManager.isUserWaiting(eventId, 0, to),
            isResale: false,
            resalePrice: 0
        });

        event_.currentSupply++;

        if (waitlistManager.isUserWaiting(eventId, 0, to)) {
            emit WaitlistTicketIssued(newTokenId, eventId, to);
        }

        emit TicketMinted(newTokenId, eventId, event_.price);
        return newTokenId;
    }

    function purchaseTicket(uint256 eventId, uint256 seatNumber) 
        external 
        payable 
        nonReentrant 
        returns (uint256) 
    {
        Event storage event_ = events[eventId];
        require(event_.isActive, "Event not active");
        require(event_.currentSupply < event_.maxSupply, "Event sold out");
        require(msg.value >= event_.price, "Insufficient payment");

        uint256 platformFee = (event_.price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 refundAmount = msg.value - event_.price;

        (bool platformSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(platformSuccess, "Platform fee transfer failed");

        if (refundAmount > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refundAmount}("");
            require(refundSuccess, "Refund transfer failed");
        }

        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _mint(msg.sender, newTokenId);
        tickets[newTokenId] = Ticket({
            eventId: eventId,
            price: event_.price,
            used: false,
            seatNumber: seatNumber,
            isWaitlisted: false,
            isResale: false,
            resalePrice: 0
        });

        event_.currentSupply++;
        emit TicketPurchased(newTokenId, msg.sender, event_.price);
        emit TicketMinted(newTokenId, eventId, event_.price);
        return newTokenId;
    }

    function listForResale(uint256 tokenId, uint256 resalePrice) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(!tickets[tokenId].used, "Ticket used");
        uint256 maxAllowedPrice = (tickets[tokenId].price * MAX_RESALE_MARKUP) / 100;
        require(resalePrice <= maxAllowedPrice, "Price too high");

        tickets[tokenId].isResale = true;
        tickets[tokenId].resalePrice = resalePrice;
        emit TicketListedForResale(tokenId, resalePrice);
    }

    function purchaseResaleTicket(uint256 tokenId) 
        external 
        payable 
        nonReentrant 
    {
        Ticket storage ticket = tickets[tokenId];
        require(ticket.isResale, "Not for resale");
        require(!ticket.used, "Ticket used");
        require(msg.value >= ticket.resalePrice, "Insufficient payment");

        address seller = ownerOf(tokenId);
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 sellerPayment = msg.value - platformFee;

        (bool platformSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(platformSuccess, "Platform fee transfer failed");

        (bool sellerSuccess, ) = payable(seller).call{value: sellerPayment}("");
        require(sellerSuccess, "Seller transfer failed");

        _transfer(seller, msg.sender, tokenId);
        ticket.isResale = false;
        
        emit TicketResold(tokenId, msg.sender, ticket.resalePrice);
    }

    function getTicketDetails(uint256 tokenId) 
        public 
        view 
        returns (
            uint256 eventId,
            uint256 price,
            bool used,
            uint256 seatNumber,
            bool isWaitlisted,
            bool isResale,
            uint256 resalePrice
        ) 
    {
        Ticket memory ticket = tickets[tokenId];
        return (
            ticket.eventId,
            ticket.price,
            ticket.used,
            ticket.seatNumber,
            ticket.isWaitlisted,
            ticket.isResale,
            ticket.resalePrice
        );
    }

    function getWaitlistCount(uint256 eventId) public view returns (uint256) {
        return waitlistManager.getWaitlistLength(eventId, 0);
    }

    function useTicket(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "Not ticket owner");
        require(!tickets[tokenId].used, "Ticket already used");
        
        tickets[tokenId].used = true;
        emit TicketUsed(tokenId);
    }
}