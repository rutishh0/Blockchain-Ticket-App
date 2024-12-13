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

    const EventManagerFactory = await ethers.getContractFactory("EventManager");
    eventManager = await EventManagerFactory.deploy();
    await eventManager.waitForDeployment();

    const RefundEscrowFactory = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrowFactory.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();

    await eventManager.setRefundEscrow(await refundEscrow.getAddress());
  });

  describe("Event Creation", function () {
    const basePrice = ethers.parseEther("0.1");
    const zoneCapacities = [100n, 200n];
    const zonePrices = [ethers.parseEther("0.2"), ethers.parseEther("0.1")];

    it("Should create event with correct parameters", async function () {
      const latestTime = await time.latest();
      const eventDate = BigInt(latestTime) + 186400n;
      const tx = await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        basePrice,
        zoneCapacities,
        zonePrices
      );
      await tx.wait();

      const eventData = await eventManager.getEventData(1);
      expect(eventData[0]).to.equal("Test Event");       // name
      expect(eventData[1]).to.equal(eventDate);          // date
      expect(eventData[2]).to.equal(basePrice);          // basePrice
      expect(eventData[3]).to.equal(organizer.address);  // organizer
      expect(eventData[4]).to.be.false;                  // cancelled
      expect(eventData[5]).to.equal(2n);                 // zoneCount
    });

    it("Should reject invalid dates", async function () {
      const latestTime = await time.latest();
      const pastDate = BigInt(latestTime) - 186400n;
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
      const latestTime = await time.latest();
      const eventDate = BigInt(latestTime) + 186400n;
      const lowZonePrices = [ethers.parseEther("0.05"), ethers.parseEther("0.05")];

      await expect(
        eventManager.connect(organizer).createEvent(
          "Test Event",
          eventDate,
          basePrice,
          zoneCapacities,
          lowZonePrices
        )
      ).to.be.revertedWith("Zone price must be >= base price");
    });
  });

  describe("Ticket Purchase", function () {
    beforeEach(async function () {
      const latestTime = await time.latest();
      const eventDate = BigInt(latestTime) + 186400n;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100n],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should process ticket purchase with fees", async function () {
      const purchasePrice = ethers.parseEther("0.1");
      const platformFee = (purchasePrice * 5n) / 100n; // 5%
      const organizerPayment = purchasePrice - platformFee;

      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

      const tx = await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: purchasePrice,
      });
      await tx.wait();

      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);
      const revenue = await eventManager.getEventRevenue(1);

      expect(revenue).to.equal(organizerPayment);
      expect(finalOwnerBalance - initialOwnerBalance).to.equal(platformFee);
    });

    it("Should prevent multiple purchases by same buyer", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1"),
      });

      await expect(
        eventManager.connect(buyer).purchaseTicket(1, 0, {
          value: ethers.parseEther("0.1"),
        })
      ).to.be.revertedWith("Already purchased ticket");
    });

    it("Should track zone capacity", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1"),
      });

      const zone = await eventManager.getZone(1, 0);
      expect(zone.availableSeats).to.equal(99n);
    });
  });

  describe("Event Cancellation", function () {
    beforeEach(async function () {
      const latestTime = await time.latest();
      const eventDate = BigInt(latestTime) + 186400n;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100n],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should allow organizer to cancel event", async function () {
      const tx = await eventManager.connect(organizer).cancelEvent(1);
      await tx.wait();

      const eventData = await eventManager.getEventData(1);
      expect(eventData[4]).to.be.true;  // cancelled status
    });

    it("Should prevent purchases after cancellation", async function () {
      await eventManager.connect(organizer).cancelEvent(1);
      await expect(
        eventManager.connect(buyer).purchaseTicket(1, 0, {
          value: ethers.parseEther("0.1"),
        })
      ).to.be.revertedWith("Event cancelled");
    });

    it("Should only allow organizer or owner to cancel", async function () {
      await expect(
        eventManager.connect(buyer).cancelEvent(1)
      ).to.be.revertedWith("Not event organizer or owner");
    });
  });

  describe("Revenue Management", function () {
    let eventDate: bigint;

    beforeEach(async function () {
      const latestTime = await time.latest();
      eventDate = BigInt(latestTime) + 186400n;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100n],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should allow revenue withdrawal after event", async function () {
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1"),
      });

      await time.increaseTo(eventDate + 186400n);

      const initialBalance = await ethers.provider.getBalance(organizer.address);

      const withdrawTx = await eventManager.connect(organizer).withdrawEventRevenue(1);
      const receipt = await withdrawTx.wait();

      // Get transaction details
      const txData = await ethers.provider.getTransaction(receipt.hash);
      const gasUsed = receipt.gasUsed * txData.gasPrice;
      const finalBalance = await ethers.provider.getBalance(organizer.address);

      // Check that finalBalance + gasUsed > initialBalance means the organizer got money
      expect(finalBalance + gasUsed).to.be.gt(initialBalance);
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