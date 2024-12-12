// SPDX-License-Identifier: MIT
import { expect } from "chai";
import { ethers } from "hardhat";
import { RefundEscrow, EventManager } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("RefundEscrow", function () {
  let refundEscrow: RefundEscrow;
  let eventManager: EventManager;
  let owner: SignerWithAddress;
  let organizer: SignerWithAddress;
  let buyer: SignerWithAddress;
  let resaleBuyer: SignerWithAddress;
  
  const ticketPrice = ethers.parseEther("0.1");
  let eventTime: bigint;

  beforeEach(async function () {
    [owner, organizer, buyer, resaleBuyer] = await ethers.getSigners();
    
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
    
    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();

    // Set RefundEscrow in EventManager
    await eventManager.setRefundEscrow(await refundEscrow.getAddress());

    // Get latest block time and set event time
    const latestTime = await time.latest();
    eventTime = BigInt(latestTime) + 186400n; // 2 days in the future

    // Create an event for testing
    await eventManager.connect(organizer).createEvent(
      "Test Event",
      eventTime,
      ticketPrice,
      [100n],
      [ticketPrice]
    );
  });

  describe("Payment Deposit", function () {
    it("Should accept initial ticket payment", async function () {
      const tx = await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
      await tx.wait();
      
      const payment = await refundEscrow.getPaymentDetails(1n, 1n);
      expect(payment[0]).to.equal(buyer.address);  // payer
      expect(payment[1]).to.equal(ticketPrice);    // amount
      expect(payment[5]).to.be.false;              // isCancelled
    });

    it("Should accept resale payment within price limit", async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
      const tx = await refundEscrow.connect(resaleBuyer).depositPayment(1n, 2n, { value: ticketPrice });
      await tx.wait();
      
      const payment = await refundEscrow.getPaymentDetails(1n, 2n);
      expect(payment[0]).to.equal(resaleBuyer.address); // payer
      expect(payment[1]).to.equal(ticketPrice);         // amount
    });

    it("Should reject duplicate payments for same ticket", async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
      await expect(
        refundEscrow.connect(resaleBuyer).depositPayment(1n, 1n, { value: ticketPrice })
      ).to.be.revertedWith("A payment for this ticket already exists");
    });
  });

  describe("Payment Release", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
    });

    it("Should only allow EventManager to release payment", async function () {
      await expect(
        refundEscrow.connect(buyer).releasePayment(1n, 1n)
      ).to.be.revertedWith("Caller is not the EventManager");
    });

    it("Should not release payment for cancelled event", async function () {
      await eventManager.connect(organizer).cancelEvent(1n);

      // Impersonate the EventManager contract
      const eventManagerAddress = await eventManager.getAddress();
      await ethers.provider.send("hardhat_impersonateAccount", [eventManagerAddress]);
      const eventManagerSigner = await ethers.provider.getSigner(eventManagerAddress);

      // Fund the impersonated EventManager address with some ETH for gas
      await ethers.provider.send("hardhat_setBalance", [
        eventManagerAddress,
        "0x1000000000000000000" // A large enough amount of Wei (e.g., 1 ETH)
      ]);

      await expect(
        refundEscrow.connect(eventManagerSigner).releasePayment(1n, 1n)
      ).to.be.revertedWith("Cannot release payment for a cancelled event");

      // Stop impersonating
      await ethers.provider.send("hardhat_stopImpersonatingAccount", [eventManagerAddress]);
    });
  });

  describe("Refunds", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
    });

    it("Should allow refund within window", async function () {
      const beforeBalance = await ethers.provider.getBalance(buyer.address);
      const tx = await refundEscrow.connect(buyer).refundPayment(1n, 1n);
      const receipt = await tx.wait();
      const gasUsed = receipt ? receipt.gasUsed * receipt.gasPrice : 0n;
      
      const afterBalance = await ethers.provider.getBalance(buyer.address);
      expect(afterBalance + gasUsed).to.be.gt(beforeBalance);
      
      const paymentStatus = await refundEscrow.getPaymentStatus(1n, 1n);
      expect(paymentStatus).to.equal(2n); // Refunded status
    });

    it("Should process event cancellation refund", async function () {
      await eventManager.connect(organizer).cancelEvent(1n);
      
      const beforeBalance = await ethers.provider.getBalance(buyer.address);
      const tx = await refundEscrow.connect(buyer).processEventCancellationRefund(1n, 1n);
      const receipt = await tx.wait();
      const gasUsed = receipt ? receipt.gasUsed * receipt.gasPrice : 0n;
      
      const afterBalance = await ethers.provider.getBalance(buyer.address);
      expect(afterBalance + gasUsed).to.be.gt(beforeBalance);
    });
  });

  describe("Waitlist Refunds", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
    });

    it("Should enable waitlist refund", async function () {
      await refundEscrow.connect(buyer).enableWaitlistRefund(1n, 1n);
      const payment = await refundEscrow.getPaymentDetails(1n, 1n);
      expect(payment[3]).to.be.true; // waitlistRefundEnabled
    });

    it("Should only allow ticket owner to enable waitlist refund", async function () {
      await expect(
        refundEscrow.connect(resaleBuyer).enableWaitlistRefund(1n, 1n)
      ).to.be.revertedWith("Caller is not the payer of this ticket");
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice });
    });

    it("Should return payment details", async function () {
      const payment = await refundEscrow.getPaymentDetails(1n, 1n);
      expect(payment[0]).to.equal(buyer.address); // payer
      expect(payment[1]).to.equal(ticketPrice);   // amount
      expect(payment[2]).to.equal(0n);            // status (Pending)
    });

    it("Should return payment status", async function () {
      const status = await refundEscrow.getPaymentStatus(1n, 1n);
      expect(status).to.equal(0n); // Pending status
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to pause/unpause", async function () {
      await refundEscrow.connect(owner).pause();
      expect(await refundEscrow.paused()).to.be.true;
      
      await refundEscrow.connect(owner).unpause();
      expect(await refundEscrow.paused()).to.be.false;
    });

    it("Should reject deposits when paused", async function () {
      await refundEscrow.connect(owner).pause();
      await expect(
        refundEscrow.connect(buyer).depositPayment(1n, 1n, { value: ticketPrice })
      ).to.be.reverted;
    });

    it("Should allow owner to withdraw stuck funds", async function () {
      const tx = await refundEscrow.connect(owner).withdrawStuckFunds();
      await tx.wait();
    });
  });
});
