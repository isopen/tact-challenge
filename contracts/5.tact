import "@stdlib/deploy";

/*
  TASK 5 - NFT random swap 
  The smart contract contains a bunch of different NFTs.
  A user brings his NFT (sends it to the smart contract), with 2.1 TON (2 for admin's profit, 0.1 for gas) in attachment (as fee for swap).
  The smart contract randomly chooses some NFT from the available NFTs (including the newly incoming one) and gives it to the user in exchange for the brought NFT (but occasionally just returns user's NFT in some cases).
  Admin can deposit NFTs without swap logic. Any NFT received from the admin is considered deposited. Admin can't swap.
  Admin can withdraw all NFTs at once, and also all TONs collected from users as fees.
  Implement getter that will return NFT addresses held by the smart contract.
  Implement getter that will return the amount of admin`s profit collected.

  In details, the smart contract (later: SC) should have this logic:
  Messages
  * AdminWithdrawalProfit 
   - SC should check that sender is the admin / otherwise throw "Insufficient privelegies"
   - SC should send all collected fees to admin except 0.1 TON (use AdminFetchProfit message as body)
     In other words: after each such operation, the contract's balance should be equal to 0.1 TON (which are reserved for storage) and the rest should be sent to the admin
  * AdminWithdrawalAllNFTs
   - SC should check that incoming tx TON value is enough for NFT withdrawal. Specifically, at least: (1 + totalNftsHeld * 0.08) TONs. Otherwise throw "Insufficent funds"
   - SC should check that sender is the admin, throw "Invalid sender" otherwise
   - If all checks pass, SC should send NFTs one by one to the admin 
  * OwnershipAssigned 
   - if prevOwner is the owner's (admin) address, then add NFT to the collection
   - if value of TON attached is less then 2.1 TON then stop execution and return NFT back,
     but only in case that TON attached is enough to process refund without losing TONs on the SC's balance
   - randomly select NFT to send from all the NFTs that smart contract has
   - send the selected NFT to the sender with all remaining balance (except for admin profit = fees collected from this and other swaps)
     In other words: the contract's balance should increase by exactly 2 TON, some incoming TONs will be consumed for gas and the remainings of the incoming TONs should be refunded to the sender
  
  Getters
  * profit
   - returns how much collected fees is available to withdraw for the admin (all fees minus 0.1 TON)
  * nfts
   - returns dict of held NFTs with NFT indexes (sequential numbers from 0, 1, 2 ... and up to 'totalNftsHeld-1') as keys and NFT address as values 
     the order of NFTs in this dictionary doesn't matter
*/

message AdminWithdrawalFees {
  queryId: Int as uint64;
}

message AdminWithdrawalAllNFTs {
  queryId: Int as uint64;
}

message AdminFetchFees {
  queryId: Int as uint64;
}

message(0x05138d91) OwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining; 
}

message(0x5fcc3d14) Transfer { 
    queryId: Int as uint64;            
    newOwner: Address; 
    responseDestination: Address; 
    customPayload: Cell?; 
    forwardAmount: Int as coins; 
    forwardPayload: Slice as remaining; 
}

contract Task5 with Deployable {
  seed: Int as uint128;
  owner: Address;
  profitBalance: Int as coins;
  nftCounter: Int as uint16;
  nfts: map<Int as uint16, Address>;
  
  init(seed: Int, owner: Address) {
    self.owner = owner;
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
    self.profitBalance = 0;
    self.nftCounter = 0;
    self.nfts = emptyMap();
  }

  receive(msg: OwnershipAssigned) {
    if (msg.prevOwner == self.owner) {
      // add nft to collection
      self.nfts[self.nftCounter] = msg.prevOwner;
      self.nftCounter += 1;

      if (msg.forwardAmount < ton("2.1") && myBalance() < ton("2")) {
        // back-send nft
        send(SendParameters{
          to: msg.prevOwner,
          value: 0,
          mode: SendRemainingValue,
          body: Transfer{
            queryId: msg.queryId,
            newOwner: msg.prevOwner,
            responseDestination: msg.prevOwner,
            customPayload: null,
            forwardAmount: msg.forwardAmount,
            forwardPayload: emptySlice()
          }.toCell()
        });
      } else {
        // random-select nft for send
        let randomIndex: Int = random(0, self.nftCounter);
        let selectedNft: Address = self.nfts.get(randomIndex);

        // calc back sum
        let returnAmount = msg.forwardAmount - ton("2");

        // back-send selected nft to user
        send(SendParameters{
          to: selectedNft,
          value: 0,
          mode: SendRemainingValue,
          body: Transfer{
            queryId: msg.queryId,
            newOwner: msg.prevOwner,
            responseDestination: msg.prevOwner,
            customPayload: null,
            forwardAmount: returnAmount,
            forwardPayload: emptySlice()
          }.toCell()
        });

        self.profitBalance += ton("0.1");

        // del selected nft
        self.nfts.set(randomIndex, null);
      }
    } else {
      // send-back nft
      if (msg.forwardAmount >= ton("2.1")) {
        send(SendParameters{
          to: msg.prevOwner,
          value: 0,
          mode: SendRemainingValue,
          body: Transfer{
            queryId: msg.queryId,
            newOwner: msg.prevOwner,
            responseDestination: msg.prevOwner,
            customPayload: null,
            forwardAmount: msg.forwardAmount,
            forwardPayload: emptySlice()
          }.toCell()
        });
      }
    }
  }

  receive(msg: AdminWithdrawalFees) {
    require(sender() == self.owner, "Insufficient privileges");

    let profitAmount = self.profitBalance;

    if (profitAmount > 0) {
      // TODO
      self.profitBalance = ton("0.1"); // reserve 0.1 TON
    } else {
      // no reserve
      // TODO
    }
  }

  receive(msg: AdminWithdrawalAllNFTs) {
    require(sender() == self.owner, "Invalid sender");

    let requiredBalance = (1 + (self.nftCounter * 0.08)) * ton();

    if (self.balance < requiredBalance) {
      // No TON for send all nft
      // TODO
    } else {
      // send all nft to admin
      for (let index in self.nfts.keys()) {
        let nftAddress = self.nfts[index];
        sdk.transfer(self.owner, nftAddress, 0, msg.queryId);
      }

      // clean collection NFT
      self.nfts = emptyMap();
      self.nftCounter = 0;
    }
  }

  get fun profit(): Int {
    return self.profitBalance;
  }
  
  get fun nfts(): map<Int as uint16, Address> {
    return self.nfts;
  }
}
