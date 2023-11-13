/*  
helper script below (setup_validator.sh) is great for setting up validators but is missing
some key steps to fully automated Pulsechain validator registration
this script complements it by handling 32M deposit automation

ref: https://github.com/tdslaine/install_pulse_node/blob/main/setup_validator.sh
ref: https://scan.pulsechain.com/address/0x3693693693693693693693693693693693693693/contracts#address-tabs

v0.1
barchef @ projectpi
*/

var fs = require('fs')
var Web3 = require('web3')

var web3 = new Web3(new Web3.providers.HttpProvider('https://rpc.pulsechain.com/'))
var depositAmtWei = web3.utils.toWei("32000000", 'ether');

console.log('depositAmt in Wei:', depositAmtWei)

var depositData = JSON.parse(fs.readFileSync('deposit_data-1699482137.json', 'utf-8'))[0];
var pubkey = depositData.pubkey;
var withdrawal_credentials = depositData.withdrawal_credentials;
var signature = depositData.signature;
var deposit_data_root = depositData.deposit_data_root;

console.log(`Deposit info: 
    pubkey: ${pubkey}\n
    withdrawal creds: ${withdrawal_credentials}\n
    signature: ${signature}\n
    deposit root: ${deposit_data_root}
`);

var res = makeDeposit(pubkey, withdrawal_credentials, signature, deposit_data_root);
console.log(res);

async function makeDeposit(pubkey, withdrawal_credentials, signature, deposit_data_root) {
    console.log('in make deposit');
    
    var senderAddr = "0xACbAd6A1500aF68FBF41A7913b02975d731C7f1B";
    var senderPK = Buffer.from("51dsit05ye95tigp51dsit05ye95tigp51dsit05ye95tigp", 'hex');
    var depositContractAddr = "0x3693693693693693693693693693693693693693";
    var depositContractAbi = JSON.parse(fs.readFileSync('pls-deposit-abi.json', 'utf-8'));
    var depositContract = new web3.eth.Contract(depositContractAbi, depositContractAddr, {from: senderAddr});
    
    console.log(`
        Transaction Info
        ================
        deposit Amt: ${web3.utils.fromWei(depositAmtWei)} (PLS)
        account: ${senderAddr}
        balance: ${web3.utils.fromWei(await web3.eth.getBalance(senderAddr))}
        gasprice ${web3.eth.gasPrice}
    `)

    
    var data = depositContract.methods.deposit(
        pubkey,
        withdrawal_credentials,
        signature,
        deposit_data_root,
    );
    console.log('data:',data)
/*
    var count = await web3.eth.getTransactionCount(senderAddr, 'latest');

    var rawTransaction = {
        to: routerAddress,
        value: web3.utils.toHex(amountToBuyWith),
        gas: web3.utils.toHex(100000.00),
        //gasPrice: web3.utils.toHex(510000) || 5000000000, // 5 Gwei
        nonce: web3.utils.toHex(count),
        data: data.encodeABI()
    }

    const signed = await web3.eth.accounts.signTransaction(
        rawTransaction,
        senderPK
    )
    const hash = await web3.eth.sendSignedTransaction(signed.rawTransaction)  
    console.log('tx ', hash)
    */
}
