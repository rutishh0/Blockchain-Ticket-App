import { expect } from "chai";
import { ethers } from "hardhat";
import { TicketFactory } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TicketFactory", function () {
  let ticketFactory: TicketFactory;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    
    const TicketFactory = await ethers.getContractFactory("TicketFactory");
    ticketFactory = await TicketFactory.deploy();
    await ticketFactory.waitForDeployment();
  });

  describe("Ticket Creation", function () {
    it("Should create a new ticket", async function () {
      const eventId = 1;
      const price = ethers.parseEther("0.1");
      const seatNumber = 1;

      await ticketFactory.createTicket(eventId, price, seatNumber);
      
      const ticket = await ticketFactory.tickets(1);
      expect(ticket.eventId).to.equal(eventId);
      expect(ticket.price).to.equal(price);
      expect(ticket.used).to.equal(false);
      expect(ticket.seatNumber).to.equal(seatNumber);
    });
  });
});