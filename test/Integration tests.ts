import { expect } from "chai";
import { ethers } from "hardhat";
import { EventManager, TicketFactory, WaitlistManager, RefundEscrow } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// Helper function to get event data
async function getEventData(eventManager: EventManager, eventId: bigint) {
  const callResult = await eventManager.callStatic.getEvent(eventId);
  return {
    name: callResult[0],
    date: callResult[1],
    basePrice: callResult[2],
    organizer: callResult[3],
    cancelled: callResult[4],
    zoneCount: callResult[5]
  };
}

describe("Ticketing System Integration", function () {
  let eventManager: EventManager;
  let ticketFactory: TicketFactory;
  let waitlistManager: WaitlistManager;
  let refundEscrow: RefundEscrow;
  
  let owner: SignerWithAddress;
  let organizer: SignerWithAddress;
  let buyer1: SignerWithAddress;
  let buyer2: SignerWithAddress;
  let buyer3: SignerWithAddress;
  
  const EVENT_NAME = "Test Concert";
  const BASE_PRICE = ethers.parseEther("0.1");
  const ZONE_CAPACITIES = [100, 50];
  const ZONE_PRICES = [ethers.parseEther("0.2"), ethers.parseEther("0.3")];

  beforeEach(async function () {
    [owner, organizer, buyer1, buyer2, buyer3] = await ethers.getSigners();
    
    // Deploy WaitlistManager first
    const WaitlistManager = await ethers.getContractFactory("WaitlistManager");
    waitlistManager = await WaitlistManager.deploy();
    await waitlistManager.waitForDeployment();
    
    // Deploy TicketFactory with WaitlistManager address
    const TicketFactory = await ethers.getContractFactory("TicketFactory");
    ticketFactory = await TicketFactory.deploy(await waitlistManager.getAddress());
    await ticketFactory.waitForDeployment();
    
    // Deploy EventManager first without RefundEscrow
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
    
    // Deploy RefundEscrow with EventManager address
    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();
    
    // Set RefundEscrow in EventManager
    await eventManager.setRefundEscrow(await refundEscrow.getAddress());
  });

  describe("Full Ticket Lifecycle", function () {
    let eventId: bigint;
    let eventDate: bigint;

    beforeEach(async function () {
      const blockNum = await ethers.provider.getBlockNumber();
      const block = await ethers.provider.getBlock(blockNum);
      eventDate = BigInt((block?.timestamp || 0) + 30 * 24 * 60 * 60);

      const tx = await eventManager.connect(organizer).createEvent(
        EVENT_NAME,
        eventDate,
        BASE_PRICE,
        ZONE_CAPACITIES.map(cap => BigInt(cap)),
        ZONE_PRICES
      );
      await tx.wait();
      eventId = BigInt(1);
    });

    it("should handle full ticket lifecycle", async function () {
      // 1. Initial Purchase
      await eventManager.connect(buyer1).purchaseTicket(eventId, BigInt(0), {
        value: ZONE_PRICES[0]
      });
      
      // Verify purchase
      expect(await eventManager.hasTicket(eventId, buyer1.address)).to.be.true;
      
      // Get event details
      const eventData = await getEventData(eventManager, eventId);
      expect(eventData.name).to.equal(EVENT_NAME);
      expect(eventData.basePrice).to.equal(BASE_PRICE);
      expect(eventData.organizer.toLowerCase()).to.equal(organizer.address.toLowerCase());
      expect(eventData.cancelled).to.be.false;
      
      // Verify zone details
      const zoneCount = await eventManager.getZoneCount(eventId);
      expect(zoneCount).to.equal(BigInt(ZONE_CAPACITIES.length));
      
      const zonePrice = await eventManager.getZonePrice(eventId, BigInt(0));
      expect(zonePrice).to.equal(ZONE_PRICES[0]);
      
      // 2. Waitlist Testing
      await waitlistManager.connect(buyer2).joinWaitlist(eventId, BigInt(0));
      await waitlistManager.connect(buyer3).joinWaitlist(eventId, BigInt(0));
      
      const waitlistLength = await waitlistManager.getWaitlistLength(eventId, BigInt(0));
      expect(waitlistLength).to.equal(BigInt(2));
      
      const buyer2Position = await waitlistManager.getWaitlistPosition(eventId, BigInt(0), buyer2.address);
      expect(buyer2Position).to.equal(BigInt(1));
      
      // 3. Resale Process
      const ticketId = BigInt(1);
      await ticketFactory.connect(buyer1).listForResale(ticketId, ZONE_PRICES[0]);
      
      const ticketDetails = await ticketFactory.getTicketDetails(ticketId);
      expect(ticketDetails[5]).to.be.true; // isResale
      expect(ticketDetails[6]).to.equal(ZONE_PRICES[0]); // resalePrice
      
      // 4. Resale Purchase
      await ticketFactory.connect(buyer2).purchaseResaleTicket(ticketId, {
        value: ZONE_PRICES[0]
      });
      
      const newOwner = await ticketFactory.ownerOf(ticketId);
      expect(newOwner.toLowerCase()).to.equal(buyer2.address.toLowerCase());
      
      // 5. Event Cancellation and Refunds
      await eventManager.connect(organizer).cancelEvent(eventId);
      
      const updatedEventData = await getEventData(eventManager, eventId);
      expect(updatedEventData.cancelled).to.be.true;
      
      // Process refunds
      const initialBalance = await ethers.provider.getBalance(buyer2.address);
      await refundEscrow.connect(buyer2).processEventCancellationRefund(eventId, ticketId);
      const finalBalance = await ethers.provider.getBalance(buyer2.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("should verify zone details correctly", async function () {
      const zoneCount = await eventManager.getZoneCount(eventId);
      
      for (let i = 0; i < Number(zoneCount); i++) {
        const zone = await eventManager.getZone(eventId, BigInt(i));
        expect(zone.capacity).to.equal(BigInt(ZONE_CAPACITIES[i]));
        expect(zone.price).to.equal(ZONE_PRICES[i]);
        expect(zone.availableSeats).to.equal(BigInt(ZONE_CAPACITIES[i]));
      }
    });

    it("should enforce waitlist priority for new tickets", async function () {
      await waitlistManager.connect(buyer1).joinWaitlist(eventId, BigInt(0));
      await waitlistManager.connect(buyer2).joinWaitlist(eventId, BigInt(0));
      
      await eventManager.connect(buyer3).purchaseTicket(eventId, BigInt(0), {
        value: ZONE_PRICES[0]
      });
      
      const buyer1Position = await waitlistManager.getWaitlistPosition(eventId, BigInt(0), buyer1.address);
      const buyer2Position = await waitlistManager.getWaitlistPosition(eventId, BigInt(0), buyer2.address);
      
      expect(buyer1Position).to.equal(BigInt(1));
      expect(buyer2Position).to.equal(BigInt(2));
    });

    it("should handle refunds within time window", async function () {
      await eventManager.connect(buyer1).purchaseTicket(eventId, BigInt(0), {
        value: ZONE_PRICES[0]
      });
      
      const ticketId = BigInt(1);
      const initialBalance = await ethers.provider.getBalance(buyer1.address);
      
      await refundEscrow.connect(buyer1).refundPayment(eventId, ticketId);
      const finalBalance = await ethers.provider.getBalance(buyer1.address);
      
      expect(finalBalance).to.be.gt(initialBalance);
      
      const paymentStatus = await refundEscrow.getPaymentStatus(eventId, ticketId);
      expect(paymentStatus).to.equal(BigInt(2)); // Refunded status
    });
  });
});