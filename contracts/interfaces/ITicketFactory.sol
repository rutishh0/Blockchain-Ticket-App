// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITicketFactory {
    function ownerOf(uint256 tokenId) external view returns (address);
    
    function getTicketDetails(uint256 tokenId) external view returns (
        uint256 eventId,
        uint256 price,
        bool used,
        uint256 seatNumber,
        bool isWaitlisted,
        bool isResale,
        uint256 resalePrice
    );
    
    function transferFrom(address from, address to, uint256 tokenId) external;
}