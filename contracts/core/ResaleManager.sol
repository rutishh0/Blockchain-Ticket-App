// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/ITicketFactory.sol";

contract ResaleManager is Ownable, ReentrancyGuard, Pausable {
    ITicketFactory public ticketFactory;

    struct ResaleListing {
        address seller;
        uint256 price;
        uint256 listingTime;
        bool isActive;
    }

    mapping(uint256 => ResaleListing) public resaleListings;

    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant MAX_RESALE_MARKUP = 110; // 110% of original price
    uint256 public constant RESALE_TIMEOUT = 7 days;

    event TicketListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event TicketUnlisted(uint256 indexed tokenId, address indexed seller);
    event TicketResold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event PlatformFeeCollected(uint256 indexed tokenId, uint256 amount);

    constructor(address ticketFactoryAddress) Ownable(msg.sender) {
        require(ticketFactoryAddress != address(0), "Invalid TicketFactory address");
        ticketFactory = ITicketFactory(ticketFactoryAddress);
    }

    function listTicketForResale(uint256 tokenId, uint256 price) external whenNotPaused {
        require(ticketFactory.ownerOf(tokenId) == msg.sender, "Caller is not the owner of the ticket");

        // Properly destructure the return values
        (, uint256 originalPrice, bool used, , , , ) = ticketFactory.getTicketDetails(tokenId);

        require(!used, "Cannot list a ticket for Resale that has already been used");
        uint256 maxResalePrice = (originalPrice * MAX_RESALE_MARKUP) / 100;
        require(price <= maxResalePrice, "Resale price exceeds the maximum allowed markup of the original price");

        resaleListings[tokenId] = ResaleListing({
            seller: msg.sender,
            price: price,
            listingTime: block.timestamp,
            isActive: true
        });

        emit TicketListed(tokenId, msg.sender, price);
    }

    function cancelResaleListing(uint256 tokenId) external {
        ResaleListing storage listing = resaleListings[tokenId];
        require(listing.seller == msg.sender, "Caller is not the seller of this ticket");
        require(listing.isActive, "Cannot cancel a resale listing that is not active");

        listing.isActive = false;
        emit TicketUnlisted(tokenId, msg.sender);
    }

    function purchaseResaleTicket(uint256 tokenId) external payable nonReentrant whenNotPaused {
        ResaleListing storage listing = resaleListings[tokenId];
        require(listing.isActive, "This ticket is not listed for resale");
        require(block.timestamp <= listing.listingTime + RESALE_TIMEOUT, "This resale listing has expired");
        require(msg.value >= listing.price, "Payment amount is less than the listed ticket price");

        address seller = listing.seller;
        uint256 platformFee = (listing.price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 sellerPayment = listing.price - platformFee;

        // Refund excess payment
        if (msg.value > listing.price) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - listing.price}("");
            require(refundSuccess, "Refund of excess payment to buyer failed");
        }

        // Transfer funds
        (bool sellerSuccess, ) = payable(seller).call{value: sellerPayment}("");
        require(sellerSuccess, "Transfer of funds to the ticket seller failed");

        (bool platformFeeSuccess, ) = payable(owner()).call{value: platformFee}("");
        require(platformFeeSuccess, "Transfer of platform fee failed");

        // Transfer ticket ownership
        ticketFactory.transferFrom(seller, msg.sender, tokenId);

        // Mark listing as inactive
        listing.isActive = false;

        emit TicketResold(tokenId, seller, msg.sender, listing.price);
        emit PlatformFeeCollected(tokenId, platformFee);
    }

    function getResaleListing(uint256 tokenId)
        external
        view
        returns (
            address seller,
            uint256 price,
            uint256 listingTime,
            bool isActive
        )
    {
        ResaleListing memory listing = resaleListings[tokenId];
        return (listing.seller, listing.price, listing.listingTime, listing.isActive);
    }

    function isListingValid(uint256 tokenId) public view returns (bool) {
        ResaleListing memory listing = resaleListings[tokenId];
        return listing.isActive && block.timestamp <= listing.listingTime + RESALE_TIMEOUT;
    }

    function setTicketFactory(address newTicketFactory) external onlyOwner {
        require(newTicketFactory != address(0), "Invalid TicketFactory address");
        ticketFactory = ITicketFactory(newTicketFactory);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {
        revert("Direct payments are not accepted");
    }
}
