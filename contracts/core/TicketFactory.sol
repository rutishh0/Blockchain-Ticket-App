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
        require(waitlistManagerAddress != address(0), "Invalid Waitlist manager address");
        waitlistManager = IWaitlistManager(waitlistManagerAddress);
    }

    function setWaitlistManager(address newWaitlistManager) external onlyOwner {
        require(newWaitlistManager != address(0), "Invalid Waitlist manager address");
        waitlistManager = IWaitlistManager(newWaitlistManager);
    }

    function createEvent(
        uint256 eventId,
        uint256 maxSupply,
        uint256 price
    ) external onlyOwner {
        require(!events[eventId].isActive, "An active event with this ID already exists");
        require(maxSupply > 0, "Ticket supply must be greater than zero");
        require(price > 0, "Event ticket price must be greater than zero");

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
        require(event_.isActive, "Tickets cannot be issued for an inactive event");
        require(event_.currentSupply < event_.maxSupply, "Cannot issue tickets as the event is sold out");

        // Check waitlist priority
        address nextInWaitlist = waitlistManager.getNextWaitingUser(eventId, 0);
        require(
            nextInWaitlist == address(0) || nextInWaitlist == to,
            "Must issue to waitlist"
        );

        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _mint(to, newTokenId);
        bool isWaitlisted = waitlistManager.isUserWaiting(eventId, 0, to);
        tickets[newTokenId] = Ticket({
            eventId: eventId,
            price: event_.price,
            used: false,
            seatNumber: seatNumber,
            isWaitlisted: isWaitlisted,
            isResale: false,
            resalePrice: 0
        });

        event_.currentSupply++;

        if (isWaitlisted) {
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
        require(event_.isActive, "Tickets cannot be purchased for an inactive event");
        require(event_.currentSupply < event_.maxSupply, "Tickets for this event are sold out");
        require(msg.value >= event_.price, "Payment must be at least the ticket price");

        // Check if there are users in waitlist
        address nextInWaitlist = waitlistManager.getNextWaitingUser(eventId, 0);
        require(nextInWaitlist == address(0) || nextInWaitlist == msg.sender, "Must respect waitlist priority");

        uint256 platformFee = (event_.price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 refundAmount = msg.value - event_.price;

        (bool platformSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(platformSuccess, "Transfer of platform fee to the contract owner failed");

        if (refundAmount > 0) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: refundAmount}("");
            require(refundSuccess, "Refund of excess payment to buyer failed");
        }

        _tokenIds++;
        uint256 newTokenId = _tokenIds;

        _mint(msg.sender, newTokenId);
        bool isWaitlisted = waitlistManager.isUserWaiting(eventId, 0, msg.sender);
        tickets[newTokenId] = Ticket({
            eventId: eventId,
            price: event_.price,
            used: false,
            seatNumber: seatNumber,
            isWaitlisted: isWaitlisted,
            isResale: false,
            resalePrice: 0
        });

        event_.currentSupply++;
        
        if (isWaitlisted) {
            emit WaitlistTicketIssued(newTokenId, eventId, msg.sender);
        }
        
        emit TicketPurchased(newTokenId, msg.sender, event_.price);
        emit TicketMinted(newTokenId, eventId, event_.price);
        return newTokenId;
    }

    // Rest of the functions remain unchanged...
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
        require(ticket.isResale, "Ticket not listed for resale");
        require(!ticket.used, "Cannot purchase a used ticket");
        require(msg.value >= ticket.resalePrice, "Payment must be at least the resale price");

        address seller = ownerOf(tokenId);
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 sellerPayment = msg.value - platformFee;

        (bool platformSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(platformSuccess, "Transfer of platform fee to the contract owner failed");

        (bool sellerSuccess, ) = payable(seller).call{value: sellerPayment}("");
        require(sellerSuccess, "Transfer of payment to the ticket seller failed");

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
        require(ownerOf(tokenId) == msg.sender, "Caller is not the owner of the ticket");
        require(!tickets[tokenId].used, "This ticket has already been used");
        
        tickets[tokenId].used = true;
        emit TicketUsed(tokenId);
    }
}