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
  const eventTime = Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60; // 30 days from now

  beforeEach(async function () {
    [owner, organizer, buyer, resaleBuyer] = await ethers.getSigners();
    
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
    
    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();
  });

  describe("Payment Deposit", function () {
    it("Should accept initial ticket payment", async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
      
      const payment = await refundEscrow.getPaymentDetails(1, 1);
      expect(payment.payer).to.equal(buyer.address);
      expect(payment.amount).to.equal(ticketPrice);
      expect(payment.originalPrice).to.equal(ticketPrice);
      expect(payment.isResale).to.be.false;
    });

    it("Should accept resale payment within price limit", async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
      await refundEscrow.connect(resaleBuyer).depositPayment(1, 1, eventTime, true, { value: ticketPrice });
      
      const payment = await refundEscrow.getPaymentDetails(1, 1);
      expect(payment.isResale).to.be.true;
      expect(payment.amount).to.equal(ticketPrice);
    });

    it("Should reject resale above original price", async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
      
      const highResalePrice = ticketPrice * 2n;
      await expect(
        refundEscrow.connect(resaleBuyer).depositPayment(1, 1, eventTime, true, { value: highResalePrice })
      ).to.be.revertedWith("Price exceeds original");
    });
  });

  describe("Payment Release", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
    });

    it("Should only allow EventManager to release payment", async function () {
      await expect(
        refundEscrow.connect(buyer).releasePayment(1, 1)
      ).to.be.revertedWith("Only EventManager can call");
    });

    it("Should not release payment for cancelled event", async function () {
      await refundEscrow.connect(owner).cancelEvent(1);
      await expect(
        refundEscrow.connect(owner).releasePayment(1, 1)
      ).to.be.revertedWith("Event cancelled");
    });
  });

  describe("Refunds", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
    });

    it("Should allow refund within window", async function () {
      const beforeBalance = await ethers.provider.getBalance(buyer.address);
      await refundEscrow.connect(buyer).requestRefund(1, 1);
      const afterBalance = await ethers.provider.getBalance(buyer.address);
      
      expect(afterBalance > beforeBalance).to.be.true;
      const payment = await refundEscrow.getPaymentDetails(1, 1);
      expect(payment.status).to.equal(2); // Refunded
    });

    it("Should apply late cancellation fee", async function () {
      await time.increase(7 * 24 * 60 * 60); // 7 days later
      
      const expectedFee = (ticketPrice * 5n) / 100n;
      const expectedRefund = ticketPrice - expectedFee;
      
      const beforeBalance = await ethers.provider.getBalance(buyer.address);
      await refundEscrow.connect(buyer).requestRefund(1, 1);
      const afterBalance = await ethers.provider.getBalance(buyer.address);
      
      expect(afterBalance - beforeBalance).to.be.closeTo(expectedRefund, ethers.parseEther("0.001"));
    });

    it("Should refund full amount on event cancellation", async function () {
      await refundEscrow.connect(owner).cancelEvent(1);
      
      const beforeBalance = await ethers.provider.getBalance(buyer.address);
      await refundEscrow.connect(buyer).processEventCancellationRefund(1, 1);
      const afterBalance = await ethers.provider.getBalance(buyer.address);
      
      expect(afterBalance - beforeBalance).to.be.closeTo(ticketPrice, ethers.parseEther("0.001"));
    });
  });

  describe("Waitlist Refunds", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
    });

    it("Should enable waitlist refund", async function () {
      await refundEscrow.connect(buyer).enableWaitlistRefund(1, 1);
      
      const payment = await refundEscrow.getPaymentDetails(1, 1);
      expect(payment.waitlistRefundEnabled).to.be.true;
    });

    it("Should only allow ticket owner to enable waitlist refund", async function () {
      await expect(
        refundEscrow.connect(resaleBuyer).enableWaitlistRefund(1, 1)
      ).to.be.revertedWith("Not the payer");
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice });
    });

    it("Should return correct refund availability", async function () {
      expect(await refundEscrow.isRefundAvailable(1, 1)).to.be.true;
      
      await time.increase(15 * 24 * 60 * 60); // 15 days later
      expect(await refundEscrow.isRefundAvailable(1, 1)).to.be.false;
    });

    it("Should calculate correct refund amount", async function () {
      const fullRefund = await refundEscrow.calculateRefundAmount(1, 1);
      expect(fullRefund).to.equal(ticketPrice);

      await time.increase(7 * 24 * 60 * 60); // 7 days later
      const partialRefund = await refundEscrow.calculateRefundAmount(1, 1);
      expect(partialRefund).to.equal(ticketPrice - (ticketPrice * 5n) / 100n);
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
        refundEscrow.connect(buyer).depositPayment(1, 1, eventTime, false, { value: ticketPrice })
      ).to.be.revertedWith("Pausable: paused");
    });

    it("Should allow owner to withdraw stuck funds", async function () {
      await refundEscrow.connect(owner).withdrawStuckFunds();
    });
  });
});