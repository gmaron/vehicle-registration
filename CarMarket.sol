pragma solidity ^0.4.19;

contract Ownable {

    address public owner;

    modifier onlyOwner(){
        require (msg.sender == owner);
        //the instruction _; is to continue the execution
        //from where the modifier was called.
        _;
    }

    function Ownable() public{
        owner = msg.sender;
    }

    function setOwner (address _to) public {
        require (msg.sender == owner);
        owner = _to;
    }

}

contract CarMarket is Ownable {

    address owner;

    uint public nextcarIndexToAssign = 0;

    mapping (uint => address) public carIndexToAddress;

    /* This creates an array with all balances */
    mapping (address => uint256) public balanceOf;

    struct Offer {
        bool isForSale;
        uint carIndex;
        address seller;
        uint minValue;          // in ether
        address onlySellTo;     // specify to sell only to a specific person
    }

    struct Bid {
        bool hasBid;
        uint carIndex;
        address bidder;
        uint value;
    }

    // A record of cars that are offered for sale at a specific minimum value, and perhaps to a specific person
    mapping (uint => Offer) public carsOfferedForSale;

    // A record of the highest car bid
    mapping (uint => Bid) public carBids;

    mapping (address => uint) public pendingWithdrawals;

    event Assign(address indexed to, uint256 carIndex);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event CarTransfer(address indexed from, address indexed to, uint256 carIndex);
    event CarOffered(uint indexed carIndex, uint minValue, address indexed toAddress);
    event CarBidEntered(uint indexed carIndex, uint value, address indexed fromAddress);
    event CarBidWithdrawn(uint indexed carIndex, uint value, address indexed fromAddress);
    event CarBought(uint indexed carIndex, uint value, address indexed fromAddress, address indexed toAddress);
    event CarNoLongerToSale(uint indexed carIndex);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    function CarMarket() public {
        owner = msg.sender;
    }

    function setInitialOwner(address to, uint carIndex) onlyOwner public{
        // If is not the current owner
        if (carIndexToAddress[carIndex] != to) {
            //if is not the 0x0 address
            if (carIndexToAddress[carIndex] != 0x0) {
                //one car less for the previous owner
                balanceOf[carIndexToAddress[carIndex]]--;
            } 
            //set the new owner
            carIndexToAddress[carIndex] = to;
            //one car more for the new owner
            balanceOf[to]++;
            emit Assign(to, carIndex);
        }
    }

    function setInitialOwners(address[] addresses, uint[] indices) public {
        require(msg.sender == owner);
        uint n = addresses.length;
        for (uint i = 0; i < n; i++) {
            setInitialOwner(addresses[i], indices[i]);
        }
    }

    function getCar(uint carIndex) public {
        
        require(carIndexToAddress[carIndex] != 0x0);
        carIndexToAddress[carIndex] = msg.sender;
        
        balanceOf[msg.sender]++;
        emit Assign(msg.sender, carIndex);
    }

    // Transfer ownership of a car to another user without requiring payment
    function transferCar(address to, uint carIndex) public {
        require(carIndexToAddress[carIndex] != msg.sender);
        
        if (carsOfferedForSale[carIndex].isForSale) {
            emit CarNoLongerToSale(carIndex);
        }
        carIndexToAddress[carIndex] = to;
        balanceOf[msg.sender]--;
        balanceOf[to]++;
        emit Transfer(msg.sender, to, 1);
        emit CarTransfer(msg.sender, to, carIndex);
        
        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid bid = carBids[carIndex];
        if (bid.bidder == to) {
            // Kill bid and refund value
            pendingWithdrawals[to] += bid.value;
            carBids[carIndex] = Bid(false, carIndex, 0x0, 0);
        }
    }

    function CarNoLongerForSale(uint carIndex) public{
        require(carIndexToAddress[carIndex] == msg.sender);
        carsOfferedForSale[carIndex] = Offer(false, carIndex, msg.sender, 0, 0x0);
    }

    function offerCarForSale(uint carIndex, uint minSalePriceInWei) public {
        require(carIndexToAddress[carIndex] != msg.sender);
        emit CarOffered(carIndex, minSalePriceInWei, 0x0);
    }

    function offerCarForSaleToAddress(uint carIndex, uint minSalePriceInWei, address toAddress) public {
        require(carIndexToAddress[carIndex] != msg.sender);
        carsOfferedForSale[carIndex] = Offer(true, carIndex, msg.sender, minSalePriceInWei, toAddress);
        emit CarOffered(carIndex, minSalePriceInWei, toAddress);
    }

    
    function buyCar(uint carIndex) payable public{
        Offer offer = carsOfferedForSale[carIndex];
        require(!offer.isForSale); // car not actually for sale
        require(offer.onlySellTo != 0x0 && offer.onlySellTo != msg.sender); // car not supposed to be sold to this user
        require(msg.value < offer.minValue); // Didn't send enough ETH
        require(offer.seller != carIndexToAddress[carIndex]); // Seller no longer owner of car

        address seller = offer.seller;

        carIndexToAddress[carIndex] = msg.sender;
        balanceOf[seller]--;
        balanceOf[msg.sender]++;
        emit Transfer(seller, msg.sender, 1);

        CarNoLongerForSale(carIndex);
        pendingWithdrawals[seller] += msg.value;
        emit CarBought(carIndex, msg.value, seller, msg.sender);

        // Check for the case where there is a bid from the new owner and refund it.
        // Any other bid can stay in place.
        Bid bid = carBids[carIndex];
        if (bid.bidder == msg.sender) {
            // Kill bid and refund value
            pendingWithdrawals[msg.sender] += bid.value;
            carBids[carIndex] = Bid(false, carIndex, 0x0, 0);
        }
    }

    function withdraw() public{
        uint amount = pendingWithdrawals[msg.sender];
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        msg.sender.transfer(amount);
    }

    function enterBidForCar(uint carIndex) payable public {

        require(carIndexToAddress[carIndex] == 0x0);             
        require(carIndexToAddress[carIndex] == msg.sender);
        require(msg.value == 0); // I don't remember if it is posible to send 0 eth 
        
        Bid existing = carBids[carIndex];
        
        require(msg.value <= existing.value);
        
        if (existing.value > 0) {
            // Refund the failing bid
            pendingWithdrawals[existing.bidder] += existing.value;
        }
        carBids[carIndex] = Bid(true, carIndex, msg.sender, msg.value);
        emit CarBidEntered(carIndex, msg.value, msg.sender);
    }

    function acceptBidForCar(uint carIndex, uint minPrice) public{
                        
        require(carIndexToAddress[carIndex] == msg.sender);
        
        address seller = msg.sender;
        Bid bid = carBids[carIndex];
        
        require(bid.value != 0);
        require(bid.value > minPrice);
    
        carIndexToAddress[carIndex] = bid.bidder;
        balanceOf[seller]--;
        balanceOf[bid.bidder]++;
        emit Transfer(seller, bid.bidder, 1);

        carsOfferedForSale[carIndex] = Offer(false, carIndex, bid.bidder, 0, 0x0);
        uint amount = bid.value;
        carBids[carIndex] = Bid(false, carIndex, 0x0, 0);
        pendingWithdrawals[seller] += amount;
        emit CarBought(carIndex, bid.value, seller, bid.bidder);
    }

    function withdrawBidForCar(uint carIndex) public {
        require(carIndexToAddress[carIndex] != 0x0);
        require(carIndexToAddress[carIndex] != msg.sender);
        
        Bid bid = carBids[carIndex];
        
        require(bid.bidder == msg.sender);
        
        emit CarBidWithdrawn(carIndex, bid.value, msg.sender);
        uint amount = bid.value;
        carBids[carIndex] = Bid(false, carIndex, 0x0, 0);
        // Refund the bid money
        msg.sender.transfer(amount);
    }

}