import { expect } from "chai";
import { ethers } from "hardhat";
import { EventManager } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("EventManager", function () {
  let eventManager: EventManager;
  let owner: SignerWithAddress;
  let organizer: SignerWithAddress;
  let buyer: SignerWithAddress;

  beforeEach(async function () {
    [owner, organizer, buyer] = await ethers.getSigners();
    
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
  });

  describe("Event Creation", function () {
    it("Should create a new event with zones", async function () {
      const currentTime = await time.latest();
      const eventDate = currentTime + 86400; // 1 day from now
      const basePrice = ethers.parseEther("0.1");
      const zoneCapacities = [100, 200];
      const zonePrices = [
        ethers.parseEther("0.2"),
        ethers.parseEther("0.1")
      ];

      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        basePrice,
        zoneCapacities,
        zonePrices
      );

      const event = await eventManager.getEvent(1);
      expect(event.name).to.equal("Test Event");
      expect(event.organizer).to.equal(organizer.address);
      expect(event.cancelled).to.be.false;

      const zone0 = await eventManager.getZone(1, 0);
      expect(zone0.capacity).to.equal(100);
      expect(zone0.price).to.equal(ethers.parseEther("0.2"));
      expect(zone0.availableSeats).to.equal(100);
    });
  });

  describe("Ticket Purchase", function () {
    beforeEach(async function () {
      const currentTime = await time.latest();
      const eventDate = currentTime + 86400;
      await eventManager.connect(organizer).createEvent(
        "Test Event",
        eventDate,
        ethers.parseEther("0.1"),
        [100],
        [ethers.parseEther("0.1")]
      );
    });

    it("Should allow ticket purchase", async function () {
      const initialBalance = await ethers.provider.getBalance(organizer.address);
      
      await eventManager.connect(buyer).purchaseTicket(1, 0, {
        value: ethers.parseEther("0.1")
      });

      const zone = await eventManager.getZone(1, 0);
      expect(zone.availableSeats).to.equal(99);

      // Check organizer received payment minus platform fee
      const finalBalance = await ethers.provider.getBalance(organizer.address);
      const expectedPayment = ethers.parseEther("0.095"); // 95% of 0.1 ETH
      expect(finalBalance - initialBalance).to.equal(expectedPayment);
    });
  });
});