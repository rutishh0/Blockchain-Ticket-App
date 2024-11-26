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
  
  const ticketPrice = ethers.parseEther("0.1");

  beforeEach(async function () {
    [owner, organizer, buyer] = await ethers.getSigners();
    
    // Deploy EventManager first
    const EventManager = await ethers.getContractFactory("EventManager");
    eventManager = await EventManager.deploy();
    await eventManager.waitForDeployment();
    
    // Deploy RefundEscrow with EventManager address
    const RefundEscrow = await ethers.getContractFactory("RefundEscrow");
    refundEscrow = await RefundEscrow.deploy(await eventManager.getAddress());
    await refundEscrow.waitForDeployment();
  });

  describe("Payment Deposit", function () {
    it("Should accept payment deposit", async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, { value: ticketPrice });
      
      expect(await refundEscrow.getPaymentStatus(1, 1)).to.equal(0); // Pending
      expect(await refundEscrow.getPaymentAmount(1, 1)).to.equal(ticketPrice);
    });
  });

  describe("Payment Release", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, { value: ticketPrice });
    });

    it("Should release payment with correct fee distribution", async function () {
      const initialOrganizerBalance = await ethers.provider.getBalance(organizer.address);
      const initialOwnerBalance = await ethers.provider.getBalance(owner.address);

      await refundEscrow.connect(owner).releasePayment(1, 1);

      const finalOrganizerBalance = await ethers.provider.getBalance(organizer.address);
      const finalOwnerBalance = await ethers.provider.getBalance(owner.address);

      // Check balances changed correctly
      expect(await refundEscrow.getPaymentStatus(1, 1)).to.equal(1); // Released
    });
  });

  describe("Refunds", function () {
    beforeEach(async function () {
      await refundEscrow.connect(buyer).depositPayment(1, 1, { value: ticketPrice });
    });

    it("Should process refund when conditions are met", async function () {
      const initialBuyerBalance = await ethers.provider.getBalance(buyer.address);
      
      await refundEscrow.connect(owner).refundPayment(1, 1);
      
      const finalBuyerBalance = await ethers.provider.getBalance(buyer.address);
      expect(await refundEscrow.getPaymentStatus(1, 1)).to.equal(2); // Refunded
    });
  });
});