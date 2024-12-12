// SPDX-License-Identifier: MIT
import { expect } from "chai";
import { ethers } from "hardhat";
import { TicketFactory, WaitlistManager } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("TicketFactory", function () {
  let ticketFactory: TicketFactory;
  let waitlistManager: WaitlistManager;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addr3: SignerWithAddress;

  const ticketPrice = ethers.parseEther("0.1");

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    
    const WaitlistManager = await ethers.getContractFactory("WaitlistManager");
    waitlistManager = await WaitlistManager.deploy();
    await waitlistManager.waitForDeployment();

    const TicketFactory = await ethers.getContractFactory("TicketFactory");
    ticketFactory = await TicketFactory.deploy(await waitlistManager.getAddress());
    await ticketFactory.waitForDeployment();
  });

  describe("Event Creation", function () {
    it("Should create event with correct parameters", async function () {
      await ticketFactory.createEvent(1, 100, ticketPrice);
      
      const event = await ticketFactory.events(1);
      expect(event[0]).to.equal(100n);        // maxSupply
      expect(event[1]).to.equal(0n);          // currentSupply
      expect(event[2]).to.equal(ticketPrice); // price
      expect(event[3]).to.be.true;            // isActive
    });

    it("Should prevent duplicate event IDs", async function () {
      await ticketFactory.createEvent(1, 100, ticketPrice);
      await expect(
        ticketFactory.createEvent(1, 100, ticketPrice)
      ).to.be.revertedWith("An active event with this ID already exists");
    });
  });

  describe("Ticket Purchase", function () {
    beforeEach(async function () {
      await ticketFactory.createEvent(1, 100, ticketPrice);
    });

    it("Should process direct purchase correctly", async function () {
      await ticketFactory.connect(addr1).purchaseTicket(1, 1, { value: ticketPrice });
      
      const ticket = await ticketFactory.getTicketDetails(1);
      expect(ticket[0]).to.equal(1n);     // eventId
      expect(ticket[3]).to.equal(1n);     // seatNumber
      expect(ticket[2]).to.be.false;      // used
    });

    it("Should handle platform fees correctly", async function () {
      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);
      
      const tx = await ticketFactory.connect(addr1).purchaseTicket(1, 1, { value: ticketPrice });
      await tx.wait();
      
      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);
      const platformFee = (ticketPrice * 5n) / 100n;
      expect(finalOwnerBalance - initialOwnerBalance).to.equal(platformFee);
    });

    it("Should track ticket supply", async function () {
      await ticketFactory.connect(addr1).purchaseTicket(1, 1, { value: ticketPrice });
      const event = await ticketFactory.events(1);
      expect(event[1]).to.equal(1n);  // currentSupply
    });
  });

  describe("Ticket Resale", function () {
    beforeEach(async function () {
      await ticketFactory.createEvent(1, 100, ticketPrice);
      await ticketFactory.connect(addr1).purchaseTicket(1, 1, { value: ticketPrice });
    });

    it("Should list ticket for resale", async function () {
      await ticketFactory.connect(addr1).listForResale(1, ticketPrice);
      const ticket = await ticketFactory.getTicketDetails(1);
      expect(ticket[5]).to.be.true;           // isResale
      expect(ticket[6]).to.equal(ticketPrice); // resalePrice
    });

    it("Should prevent resale above markup limit", async function () {
      const highPrice = (ticketPrice * 120n) / 100n;
      await expect(
        ticketFactory.connect(addr1).listForResale(1, highPrice)
      ).to.be.revertedWith("Price too high");
    });

    it("Should process resale purchase", async function () {
      await ticketFactory.connect(addr1).listForResale(1, ticketPrice);
      const tx = await ticketFactory.connect(addr2).purchaseResaleTicket(1, { value: ticketPrice });
      await tx.wait();
      
      expect(await ticketFactory.ownerOf(1)).to.equal(addr2.address);
      const ticket = await ticketFactory.getTicketDetails(1);
      expect(ticket[5]).to.be.false;  // isResale
    });
  });

  describe("Waitlist Integration", function () {
    beforeEach(async function () {
      await ticketFactory.createEvent(1, 2, ticketPrice);
      await ticketFactory.issueTicket(addr1.address, 1, 1);
    });

    it("Should enforce waitlist priority", async function () {
      await waitlistManager.connect(addr2).joinWaitlist(1, 0);
      await waitlistManager.connect(addr3).joinWaitlist(1, 0);
      
      await expect(
        ticketFactory.issueTicket(addr3.address, 1, 2)
      ).to.be.revertedWith("Must issue to waitlist");
      
      await ticketFactory.issueTicket(addr2.address, 1, 2);
      
      // Clear waitlist entry for addr2
      await waitlistManager.clearWaitlistForUser(1, 0, addr2.address);
      
      const waitlistLength = await waitlistManager.getWaitlistLength(1, 0);
      expect(waitlistLength).to.equal(1n);
    });

    it("Should track waitlist status in tickets", async function () {
      await waitlistManager.connect(addr2).joinWaitlist(1, 0);
      await ticketFactory.issueTicket(addr2.address, 1, 2);
      
      const ticket = await ticketFactory.getTicketDetails(2);
      expect(ticket[4]).to.be.true; // isWaitlisted
    });
  });

  describe("Ticket Usage", function () {
    beforeEach(async function () {
      await ticketFactory.createEvent(1, 100, ticketPrice);
      await ticketFactory.connect(addr1).purchaseTicket(1, 1, { value: ticketPrice });
    });

    it("Should mark ticket as used", async function () {
      await ticketFactory.connect(addr1).useTicket(1);
      const ticket = await ticketFactory.getTicketDetails(1);
      expect(ticket[2]).to.be.true;  // used
    });

    it("Should prevent reuse", async function () {
      await ticketFactory.connect(addr1).useTicket(1);
      await expect(
        ticketFactory.connect(addr1).useTicket(1)
      ).to.be.revertedWith("This ticket has already been used");
    });

    it("Should prevent non-owner usage", async function () {
      await expect(
        ticketFactory.connect(addr2).useTicket(1)
      ).to.be.revertedWith("Caller is not the owner of the ticket");
    });
  });
});