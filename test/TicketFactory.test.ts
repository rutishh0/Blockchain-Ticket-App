import { expect } from "chai";
import { ethers } from "hardhat";
import { TicketFactory, WaitlistManager } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("TicketFactory with Waitlist", function () {
  let ticketFactory: TicketFactory;
  let waitlistManager: WaitlistManager;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // Deploy WaitlistManager
    const WaitlistManager = await ethers.getContractFactory("WaitlistManager");
    waitlistManager = await WaitlistManager.deploy();
    await waitlistManager.waitForDeployment();

    // Deploy TicketFactory with WaitlistManager address
    const TicketFactory = await ethers.getContractFactory("TicketFactory");
    ticketFactory = await TicketFactory.deploy(await waitlistManager.getAddress());
    await ticketFactory.waitForDeployment();
  });

  describe("Waitlist Integration", function () {
    beforeEach(async function () {
      // Create event with 2 max supply
      await ticketFactory.createEvent(1, 2, ethers.parseEther("0.1"));
      // Issue first ticket to addr1
      await ticketFactory.issueTicket(addr1.address, 1, 1);
    });

    it("Should allow joining waitlist and issue ticket to waitlisted user", async function () {
      // addr2 joins waitlist
      await waitlistManager.connect(addr2).joinWaitlist(1, 0);
      
      // Issue last ticket - should only work for waitlisted user
      await expect(
        ticketFactory.issueTicket(owner.address, 1, 2)
      ).to.be.revertedWith("Must issue to waitlist");

      // Should succeed for waitlisted user
      await ticketFactory.issueTicket(addr2.address, 1, 2);
      
      const ticket = await ticketFactory.getTicketDetails(2);
      expect(ticket[4]).to.be.true; // isWaitlisted
    });

    it("Should track waitlist count", async function () {
      await waitlistManager.connect(addr2).joinWaitlist(1, 0);
      expect(await ticketFactory.getWaitlistCount(1)).to.equal(1);
    });

    it("Should emit WaitlistTicketIssued event", async function () {
      await waitlistManager.connect(addr2).joinWaitlist(1, 0);
      
      await expect(ticketFactory.issueTicket(addr2.address, 1, 2))
        .to.emit(ticketFactory, "WaitlistTicketIssued")
        .withArgs(2, 1, addr2.address);
    });
  });
});