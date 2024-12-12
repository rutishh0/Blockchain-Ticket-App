// SPDX-License-Identifier: MIT
import { expect } from "chai";
import { ethers } from "hardhat";
import { EventManager, RefundEscrow } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("EventManager", function () {
  let eventManager: EventManager;
  let refundEscrow: RefundEscrow;
  let owner: SignerWithAddress;
  let organizer: SignerWithAddress;
  let buyer: SignerWithAddress;
  let buyer2: SignerWithAddress;

  beforeEach(async function () {
    [owner, organizer, buyer, buyer2] = await ethers.getSigners();
    
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();

    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await eventManager.setRefundEscrow(await refundEscrow.getAddress());
  });

  describe("Event Creation", function () {
    const basePrice = ethers.parseEther("0.1");
    const zoneCapacities = [100, 200];
    const zonePrices = [ethers.parseEther("0.2"), ethers.parseEther("0.1")];

    it("Should create event with correct parameters", async function () {
      const eventDate = await time.latest() + 186400;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        basePrice,
        zoneCapacities,
        zonePrices
      );

      const event = await eventManager.getEvent(1);
      expect(event.name).to.equal("Test Event");
      expect(event.basePrice).to.equal(basePrice);
      expect(event.organizer).to.equal(organizer.address);
    });

    it("Should reject invalid dates", async function () {
      const pastDate = await time.latest() - 186400;
      await expect(
        eventManager.connect(organizer).createEvent(
          "Test Event",
          pastDate,
          basePrice,
          zoneCapacities,
          zonePrices
        )
      ).to.be.revertedWith("Event date must be at least one day in the future");
    });

    it("Should validate zone prices", async function () {
      const eventDate = await time.latest() + 186400;
      const lowZonePrices = [ethers.parseEther("0.05"), ethers.parseEther("0.05")];
      
      await expect(
        eventManager.connect(organizer).createEvent(
          "Test Event",
          eventDate,
          basePrice,
          zoneCapacities,
          lowZonePrices
        )
      ).to.be.revertedWith("Zone price must be greater than or equal to the base price");
    });
  });

  describe("Ticket Purchase", function () {
    beforeEach(async function () {
      const eventDate = await time.latest() + 186400;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should process ticket purchase with fees", async function () {
      const purchasePrice = ethers.parseEther("0.1");
      const platformFee = (purchasePrice * 5n) / 100n;
      const organizerPayment = purchasePrice - platformFee;

      const initialOrganizerBalance = await ethers.provider.getBalance(organizer.address);
      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: purchasePrice
      });

      const finalOrganizerBalance = await ethers.provider.getBalance(organizer.address);
      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

      expect(finalOrganizerBalance - initialOrganizerBalance).to.equal(organizerPayment);
      expect(finalOwnerBalance - initialOwnerBalance).to.equal(platformFee);
    });

    it("Should prevent multiple purchases by same buyer", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1")
      });

      await expect(
        eventManager.connect(buyer).purchaseTicket(1, 0, {
          value: ethers.parseEther("0.1")
        })
      ).to.be.revertedWith("Caller has already purchased a ticket for this event");
    });

    it("Should track zone capacity", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1")
      });

      const zone = await eventManager.getZone(1, 0);
      expect(zone.availableSeats).to.equal(99);
    });
  });

  describe("Event Cancellation", function () {
    beforeEach(async function () {
      const eventDate = await time.latest() + 186400;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should allow organizer to cancel event", async function () {
      await eventManager.connect(organizer).cancelEvent(1);
      const event = await eventManager.getEvent(1);
      expect(event.cancelled).to.be.true;
    });

    it("Should prevent purchases after cancellation", async function () {
      await eventManager.connect(organizer).cancelEvent(1);
      await expect(
        eventManager.connect(buyer).purchaseTicket(1, 0, {
          value: ethers.parseEther("0.1")
        })
      ).to.be.revertedWith("Cannot purchase tickets for a cancelled event");
    });

    it("Should only allow organizer or owner to cancel", async function () {
      await expect(
        eventManager.connect(buyer).cancelEvent(1)
      ).to.be.revertedWith("Caller is not the event organizer or owner");
    });
  });

  describe("Revenue Management", function () {
    beforeEach(async function () {
      const eventDate = await time.latest() + 186400;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should track event revenue", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1")
      });

      const revenue = await eventManager.getEventRevenue(1);
      expect(revenue).to.equal(ethers.parseEther("0.095")); // 95% of 0.1 ETH
    });

    it("Should allow revenue withdrawal after event", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1")
      });

      await time.increase(186401); // One day + 1 second

      const initialBalance = await ethers.provider.getBalance(organizer.address);
      await eventManager.connect(organizer).withdrawEventRevenue(1);
      const finalBalance = await ethers.provider.getBalance(organizer.address);

      expect(finalBalance > initialBalance).to.be.true;
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to pause/unpause", async function () {
      await eventManager.connect(owner).pause();
      expect(await eventManager.paused()).to.be.true;

      await eventManager.connect(owner).unpause();
      expect(await eventManager.paused()).to.be.false;
    });
  });
});