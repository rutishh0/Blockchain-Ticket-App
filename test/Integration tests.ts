import { expect } from "chai";
import { ethers } from "hardhat";
import { EventManager, TicketFactory, WaitlistManager, RefundEscrow } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

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
  const ZONE_CAPACITIES = [100n, 50n];
  const ZONE_PRICES = [ethers.parseEther("0.2"), ethers.parseEther("0.3")];

  let eventId: number;
  let eventDate: bigint;

  beforeEach(async function () {
    [owner, organizer, buyer1, buyer2, buyer3] = await ethers.getSigners();
    
    const WaitlistManager = await ethers.getContractFactory("WaitlistManager");
    waitlistManager = await WaitlistManager.deploy();
    await waitlistManager.waitForDeployment();
    
    const TicketFactory = await ethers.getContractFactory("TicketFactory");
    ticketFactory = await TicketFactory.deploy(await waitlistManager.getAddress());
    await ticketFactory.waitForDeployment();
    
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
    
    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();
    
    await eventManager.setRefundEscrow(await refundEscrow.getAddress());

    const latestTime = await time.latest();
    eventDate = BigInt(latestTime) + 186400n; // 2 days in the future

    const tx = await eventManager.connect(organizer).createEvent(
      EVENT_NAME,
      eventDate,
      BASE_PRICE,
      ZONE_CAPACITIES,
      ZONE_PRICES
    );
    await tx.wait();
    eventId = 1; // First event

    // Initialize event in TicketFactory
    await ticketFactory.connect(owner).createEvent(eventId, ZONE_CAPACITIES[0], ZONE_PRICES[0]);
  });

  describe("Full Ticket Lifecycle", function () {
    it("should handle full ticket lifecycle", async function () {
      // 1. Initial Purchase
      const purchaseTx = await eventManager.connect(buyer1).purchaseTicket(eventId, 0, {
        value: ZONE_PRICES[0]
      });
      await purchaseTx.wait();
      
      // Issue ticket in TicketFactory
      const ticketId = 1n;
      await ticketFactory.connect(owner).issueTicket(buyer1.address, eventId, 1);
      expect(await ticketFactory.ownerOf(ticketId)).to.equal(buyer1.address);
      
      // Deposit payment into RefundEscrow
      await refundEscrow.connect(buyer1).depositPayment(BigInt(eventId), ticketId, { value: ZONE_PRICES[0] });
      
      // Verify purchase
      expect(await eventManager.hasTicket(eventId, buyer1.address)).to.be.true;
      
      // Get event details
      const eventData = await eventManager.getEventData(eventId);
      expect(eventData[0]).to.equal(EVENT_NAME);           // name
      expect(eventData[1]).to.equal(eventDate);            // date
      expect(eventData[2]).to.equal(BASE_PRICE);           // basePrice
      expect(eventData[3]).to.equal(organizer.address);    // organizer
      expect(eventData[4]).to.be.false;                    // cancelled
      expect(eventData[5]).to.equal(BigInt(ZONE_CAPACITIES.length));  // zoneCount
      
      // 2. Waitlist Testing
      await waitlistManager.connect(buyer2).joinWaitlist(BigInt(eventId), 0n);
      await waitlistManager.connect(buyer3).joinWaitlist(BigInt(eventId), 0n);
      
      const waitlistLength = await waitlistManager.getWaitlistLength(BigInt(eventId), 0n);
      expect(waitlistLength).to.equal(2n);
      
      const buyer2Position = await waitlistManager.getWaitlistPosition(BigInt(eventId), 0n, buyer2.address);
      expect(buyer2Position).to.equal(1n);
      
      // 3. Resale Process
      await ticketFactory.connect(buyer1).approve(await ticketFactory.getAddress(), ticketId);
      await ticketFactory.connect(buyer1).listForResale(ticketId, ZONE_PRICES[0]);
      
      const ticketDetails = await ticketFactory.getTicketDetails(ticketId);
      expect(ticketDetails[5]).to.be.true;                 // isResale
      expect(ticketDetails[6]).to.equal(ZONE_PRICES[0]);   // resalePrice
      
      // 4. Resale Purchase
      await ticketFactory.connect(buyer2).purchaseResaleTicket(ticketId, {
        value: ZONE_PRICES[0]
      });
      
      expect(await ticketFactory.ownerOf(ticketId)).to.equal(buyer2.address);
      
      // 5. Event Cancellation and Refunds
      await eventManager.connect(organizer).cancelEvent(eventId);
      
      const updatedEventData = await eventManager.getEventData(eventId);
      expect(updatedEventData[4]).to.be.true;  // cancelled status
      
      const initialBalance = await ethers.provider.getBalance(buyer2.address);
      const refundTx = await refundEscrow.connect(buyer2).processEventCancellationRefund(BigInt(eventId), ticketId);
      const receipt = await refundTx.wait();
      const gasUsed = receipt ? receipt.gasUsed * receipt.gasPrice : 0n;
      
      const finalBalance = await ethers.provider.getBalance(buyer2.address);
      expect(finalBalance + gasUsed).to.be.gt(initialBalance);
    });

    // Rest of the tests remain the same...
    it("should verify zone details correctly", async function () {
      const zoneCount = await eventManager.getZoneCount(eventId);
      
      for (let i = 0; i < Number(zoneCount); i++) {
        const zone = await eventManager.getZone(eventId, i);
        expect(zone.capacity).to.equal(ZONE_CAPACITIES[i]);
        expect(zone.price).to.equal(ZONE_PRICES[i]);
        expect(zone.availableSeats).to.equal(ZONE_CAPACITIES[i]);
      }
    });

    it("should enforce waitlist priority for new tickets", async function () {
      await waitlistManager.connect(buyer1).joinWaitlist(BigInt(eventId), 0n);
      await waitlistManager.connect(buyer2).joinWaitlist(BigInt(eventId), 0n);
      
      await eventManager.connect(buyer3).purchaseTicket(eventId, 0, {
        value: ZONE_PRICES[0]
      });
      
      const buyer1Position = await waitlistManager.getWaitlistPosition(BigInt(eventId), 0n, buyer1.address);
      const buyer2Position = await waitlistManager.getWaitlistPosition(BigInt(eventId), 0n, buyer2.address);
      
      expect(buyer1Position).to.equal(1n);
      expect(buyer2Position).to.equal(2n);
    });

    it("should handle refunds within time window", async function () {
      const purchaseTx = await eventManager.connect(buyer1).purchaseTicket(eventId, 0, {
        value: ZONE_PRICES[0]
      });
      await purchaseTx.wait();
      
      const ticketId = 1n;
      // Issue ticket in TicketFactory
      await ticketFactory.connect(owner).issueTicket(buyer1.address, eventId, 1);
      
      await refundEscrow.connect(buyer1).depositPayment(BigInt(eventId), ticketId, { value: ZONE_PRICES[0] });

      const initialBalance = await ethers.provider.getBalance(buyer1.address);
      
      const refundTx = await refundEscrow.connect(buyer1).refundPayment(BigInt(eventId), ticketId);
      const receipt = await refundTx.wait();
      const gasUsed = receipt ? receipt.gasUsed * receipt.gasPrice : 0n;
      
      const finalBalance = await ethers.provider.getBalance(buyer1.address);
      expect(finalBalance + gasUsed).to.be.gt(initialBalance);
      
      const paymentStatus = await refundEscrow.getPaymentStatus(BigInt(eventId), ticketId);
      expect(paymentStatus).to.equal(2n); // Refunded status
    });
  });
});