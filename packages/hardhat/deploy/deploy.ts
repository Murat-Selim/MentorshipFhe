import { ethers } from "ethers";
import hre from "hardhat";

async function main() {
  
  // Deploy Mentorship contract
  console.log("Deploying Mentorship contract...");
  const Mentorship = await hre.ethers.getContractFactory("Mentorship");
  const mentorship = await Mentorship.deploy("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"); // USDC contract address
  await mentorship.waitForDeployment();
  const mentorshipAddress = await mentorship.getAddress();
  console.log(`Mentorship contract deployed to: ${mentorshipAddress}`);
  
  console.log("\n=== Deployment Summary ===");
  console.log(`Mentorship: ${mentorshipAddress}`);
}

// Export the main function for hardhat-deploy
export default main;