import { ethers } from "hardhat";
import {
    providers,
    Wallet,
} from "ethers";
import {
    getArbitrumNetwork,
    ParentToChildMessageStatus
} from "@arbitrum/sdk";
import {
    AdminErc20Bridger,
    Erc20Bridger
} from "@arbitrum/sdk/dist/lib/assetBridger/erc20Bridger";
import dotenv from "dotenv";

dotenv.config();

async function main() {
    console.log('Starting script execution');

    // Validate environment variables
    const walletPrivateKey = process.env.PRIVATE_KEY;
    const l1ChainRpc = process.env.L1_CHAIN_RPC;
    const l2ChainRpc = process.env.L2_CHAIN_RPC;
    const tokenSupply = process.env.TOKEN_SUPPLY_AMOUNT
    const tokenBridgeAmount = process.env.TOKEN_BRIDGE_AMOUNT

    if (!walletPrivateKey || !l1ChainRpc || !l2ChainRpc || !tokenSupply || !tokenBridgeAmount) {
        throw new Error('Missing required environment variables');
    }

    // Set initial supply amount
    const initialSupply = ethers.utils.parseUnits(tokenSupply, 0);

    // Set up providers and wallets
    const l1ChainProvider = new providers.JsonRpcProvider(l1ChainRpc);
    const l2ChainProvider = new providers.JsonRpcProvider(l2ChainRpc);

    const l1ChainWallet = new Wallet(walletPrivateKey, l1ChainProvider);
    const l2ChainWallet = new Wallet(walletPrivateKey, l2ChainProvider);


    const l2ChainNetwork = await getArbitrumNetwork(l2ChainProvider)

    // Ensure token bridge exists
    if (!l2ChainNetwork.tokenBridge) {
        throw new Error('Token bridge not found for the network');
    }

    console.log('### Stage 1 - Deploying the token bridge ###');

    const erc20Bridger = new Erc20Bridger(l2ChainNetwork);
    const adminTokenBridger = new AdminErc20Bridger(l2ChainNetwork);

    const l1ChainRouter = l2ChainNetwork.tokenBridge.parentGatewayRouter;
    const l2ChainRouter = l2ChainNetwork.tokenBridge.childGatewayRouter;
    const inbox = l2ChainNetwork.ethBridge.inbox;

    // Deploy L1 Token Bridge
    const L1TokenBridge = await ethers.getContractFactory('L1TokenBridge', l1ChainWallet);
    const l1TokenBridge = await L1TokenBridge.deploy(
        l1ChainRouter,
        inbox
    );

    await l1TokenBridge.deployed();

    const l1TokenBridgeAddress = l1TokenBridge.address;
    console.log(`Token bridge deployed to l1 chain at ${l1TokenBridgeAddress}`);

    // Deploy L2 Token Bridge
    const L2TokenBridge = await ethers.getContractFactory('L2TokenBridge', l2ChainWallet);
    const l2TokenBridge = await L2TokenBridge.deploy(
        l2ChainRouter
    );

    await l2TokenBridge.deployed();

    const l2TokenBridgeAddress = l2TokenBridge.address;
    console.log(`Token bridge deployed to l2 chain at ${l2TokenBridgeAddress}`);


    console.log('### Stage 2 - Deploy ERC20 token ###');
    // Deploy L1 ERC20 Token
    const L1ERC20Token = await ethers.getContractFactory('L1ERC20Token', l1ChainWallet);
    const l1ERC20Token = await L1ERC20Token.deploy(
        l1TokenBridgeAddress,
        l1ChainRouter,
        initialSupply
    );

    await l1ERC20Token.deployed();

    const l1ERC20TokenAddress = l1ERC20Token.address;
    console.log(`ERC20 token deployed to L1 at ${l1ERC20TokenAddress}`);

    // Deploy L2 ERC20 Token
    const L2ERC20Token = await ethers.getContractFactory('L2ERC20Token', l2ChainWallet);
    const l2ERC20Token = await L2ERC20Token.deploy(
        l2TokenBridgeAddress,
        l1ERC20TokenAddress
    );

    await l2ERC20Token.deployed();

    const l2ERC20TokenAddress = l2ERC20Token.address;
    console.log(`ERC20 token deployed to L2 at ${l2ERC20TokenAddress}`);

    // Set token bridge information on L1
    console.log('Setting token bridge information on L1TokenBridge:');
    const setTokenBridgeInfoOnL1 = await l1TokenBridge.setTokenBridgeInformation(
        l1ERC20TokenAddress,
        l2ERC20TokenAddress,
        l2TokenBridgeAddress
    );
    const setTokenBridgeInfoOnL1Receipt = await setTokenBridgeInfoOnL1.wait();

    console.log(
        `Token bridge information set on L1TokenBridge! Tx receipt on l1: ${setTokenBridgeInfoOnL1Receipt?.transactionHash}`
    );

    // Set token bridge information on L2
    console.log('Setting token bridge information on L2TokenBridge:');
    const setTokenBridgeInfoOnL2Tx = await l2TokenBridge.setTokenBridgeInformation(
        l1ERC20TokenAddress,
        l2ERC20TokenAddress,
        l1TokenBridgeAddress
    );
    const setTokenBridgeInfoOnL2TxReceipt = await setTokenBridgeInfoOnL2Tx.wait();

    console.log(
        `Token bridge information set on L2TokenBridge! Tx receipt on l2: ${setTokenBridgeInfoOnL2TxReceipt?.transactionHash}`
    );

    // Register ERC20 token
    console.log('Registering ERC20 token on L2..');
    const registerTokenTx = await adminTokenBridger.registerCustomToken(
        l1ERC20TokenAddress,
        l2ERC20TokenAddress,
        l1ChainWallet as any,
        l2ChainProvider as any
    );

    const registerTokenTxReceipt = await registerTokenTx.wait();

    console.log(
        `Registering token tx confirmed on L1. Receipt hash: ${registerTokenTxReceipt?.transactionHash}.`
    );

    console.log(
        `Waiting for the registration tx to be executed on L2. This step can take a few minutes`
    );

    // Get l1 to l2 messages
    const messages = await registerTokenTxReceipt?.getParentToChildMessages(
        l2ChainProvider as any
    );

    // Validate messages
    if (!messages || messages.length !== 1) {
        throw new Error(`Expected 1 message, but got ${messages?.length || 0}`);
    }

    const tempSetup = await messages[0].waitForStatus();

    if (tempSetup.status !== ParentToChildMessageStatus.REDEEMED) {
        throw new Error(`Set gateways not redeemed. Status: ${tempSetup.status}`);
    }

    console.log(
        'ERC20 token and Token Bridge are now registered!'
    );


    console.log('### Stage 3 - Bridging ERC20 tokens ###');

    // Calculate token deposit amount considering decimals
    const tokenDecimals = await l1ERC20Token.decimals();
    const tokenTransferAmount = ethers.utils.parseUnits(tokenBridgeAmount, tokenDecimals);

    // Approve L1TokenBridge to transfer tokens
    console.log('Approving L1TokenBridge:');
    const approveTx = await erc20Bridger.approveToken({
        parentSigner: l1ChainWallet as any,
        erc20ParentAddress: l1ERC20TokenAddress,
    });

    const approveTxReceipt = await approveTx.wait();
    console.log(
        `You successfully allowed the Arbitrum Bridge to spend the L1 ERC20 Token. Tx hash: ${approveTxReceipt.transactionHash}`
    );

    // Deposit L1 ERC20 Token to the l2 chain
    console.log('Transferring L1 ERC20 Token to the L2 chain:');
    const depositTx = await erc20Bridger.deposit({
        amount: tokenTransferAmount,
        erc20ParentAddress: l1ERC20TokenAddress,
        parentSigner: l1ChainWallet as any,
        childProvider: l2ChainProvider as any,
    });

    console.log(
        `Token bridging initiated. This step can take a few minutes)`
    );

    const depositTxReceipt = await depositTx.wait();
    const l2ChainDepositResult = await depositTxReceipt.waitForChildTransactionReceipt(
        l2ChainProvider as any
    );

    // Check if the deposit was successful
    if (l2ChainDepositResult.complete) {
        console.log(
            `Token bridging to the L2 chain complete. Status: ${ParentToChildMessageStatus[l2ChainDepositResult.status]}`
        );
    } else {
        throw new Error(
            `Token bridging to the L2 chain failed. Status ${ParentToChildMessageStatus[l2ChainDepositResult.status]}`
        );
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });