pragma solidity ^0.4.24;


contract LNEvents {
    // fired whenever a player registers a name
    event OnBuy(uint8 resCode, uint256 roundId, uint256 timeStamp, uint256[2][] nums, address playerAddress);
    event OnWithdraw(uint8 resCode, uint256 roundId, uint256 timeStamp, uint256 ethOut, address playerAddress);
}


interface LuckyNumInterface {

    function getEthers(address addr, uint256 amount) external;

    function currentRoundId() external view returns (uint256);

    function getPlayerNums(uint256 roundId) external view returns (uint256[2][]);
  
    function getBalance() external view returns(uint256);

}


contract LuckyNum is LuckyNumInterface, LNEvents {
    using SafeMath for *;
    enum ResCode { Success, BoughtFailForEnded, BoughtFail, WithdrawFail}
    // event LogPlayer(DataSet.Player);

    struct Round {
        bool ended;     // has round end function been ran
        uint256 startTime;   // time round started
        uint256 endTime;    // time ends/ended
        uint256 blockNum;   //ended transaction block number
        uint256 luckyNum;   // lucky num
        bytes32 luckyHash;   // lucky hash
        address winner;  //win Player 
        
        mapping(address=>uint256[2][]) playerNums;
    }

    /**
     * @dev used to make sure no one can interact with contract until it has 
     * been activated. 
     */
    modifier isActivated() {
        require(activated_ == true, "its not ready yet.  check ?eta in discord"); 
        _;
    }

    modifier isOwner() {
        require(owner == msg.sender, "Owner only"); 
        _;
    }
    
    /**
     * @dev prevents contracts from interacting with lucky-num 
     */
    modifier isHuman() { 
        address _addr = msg.sender;
        uint256 _codeLength;
        
        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    mapping (uint256 => Round) public rounds;   // (rID => data) round data
    mapping (address => uint256) public winPlayers;   // (rID => data) round data
    address private  owner;   // player addresses in current round
    uint256[] private betsArray; //num and address every bet
    uint256 private betIndex = 0;   //bet index (round var)
    uint256 public currentNum = 0;  //current num this round

    // event HighestBidIncreased(address bidder, uint amount);
    // event AuctionEnd(address winner, uint amount);

    string constant public NAME = "Luckin LuckyNum";
    string constant public SYMBOL = "LNum";
    uint256 private constant NUM_COST = 1000000000000000; // 0.001 ether; 
    uint256 private constant NUM_COUNT = 1000; //10 thousand nums
    uint256 private constant ROUND_TIMESPAN = 30 seconds; //timespan between round
    uint256 private constant BENEFIAL = 2; //benefial percent

    uint256 public rId;   //round id number / total rounds that have happened

    constructor() public {
        // winPlayers[0x0ea9e6bcb35f2f859a490a6879a002db84658d46] = 1 ether;
        // winPlayers[0x4ff22faf2c635ea6efae777395bd05d433bdc451] = 1 ether;
        // winPlayers[0x8d96c32689389f1a29803c9f1aa1449be6e51882] = 1 ether;
        owner = msg.sender;
    }
    
    function() public
        isActivated()
        isHuman()
        payable
    {
        // buy core 
        buyXNum();
    }

    /** upon contract deploy, it will be deactivated.  this is a one time
     * use function that will activate the contract.  we do this so devs 
     * have time to set things up on the web end                            **/
    bool public activated_ = false;

    function activate() 
        public
        isOwner()
    {
        // only team just can activate 
        require(
            msg.sender == owner,
            "only team just can activate"
        );

        // can only be ran once
        require(activated_ == false, "Lucky Num already activated");
        
        // activate the contract 
        activated_ = true;
        
        // lets start first round
        _startNewRound();
    }

    function currentRoundId() public view returns (uint256) {
        return rId;
    }

    function getPlayerNums(uint256 roundId) public view returns (uint256[2][]) {
        require(roundId > 0 && roundId <= rId, "Round id not exists");
        return rounds[roundId].playerNums[msg.sender];
    }

    // function playerNums(address _addr) public returns (uint256[][]) {
    //     // require(rounds[rId].playerNums[_addr].addr > 0, "Player not exist");
    //     uint256[][] storage _nums = rounds[rId].playerNums[_addr];
    //     return _nums;
    // }
    function buyXNum() public
        isActivated()
        isHuman()
        payable
    {
        require(
            msg.value >= NUM_COST,
            "Pay must > 0.001eth"
        );
        if (!rounds[rId].ended) {
            _buyCore();
        } else if (now.sub(rounds[rId].endTime) < ROUND_TIMESPAN) {
            uint256[2][] memory empty;
            emit LNEvents.OnBuy(uint8(ResCode.BoughtFailForEnded), rId, now, empty, msg.sender);
            revert();  //Not permitted to select num
        }else {
            _endRound();
            _buyCore();
        }
    }

    function withdraw() public
        isActivated()
        isHuman() payable {
        // check to see if round has ended and no one has run round end yet
        if (rounds[rId].ended && now.sub(rounds[rId].endTime) >= ROUND_TIMESPAN) {
            _endRound();
        }
        uint256 _eth = winPlayers[msg.sender];
        
        if (_eth > 0 && address(this).balance >= _eth) {
            require(msg.sender.send(_eth));
            winPlayers[msg.sender] = winPlayers[msg.sender].sub(_eth);
            // fire withdraw event
            emit LNEvents.OnWithdraw(uint8(ResCode.Success), rId, now, _eth, msg.sender);
        }else {
            emit LNEvents.OnWithdraw(uint8(ResCode.WithdrawFail), rId, now, _eth, msg.sender);
        }
    }

    function getEthers(address addr, uint256 amount) 
        public
        isOwner()
        isActivated()
        isHuman() payable {
            require(msg.sender == owner);
            require(address(this).balance >= amount);
            addr.transfer(amount);
        }
  
    function getBalance() public isOwner() isActivated()
        view returns(uint256) {
        return address(this).balance;
    }
    
    function _startNewRound() private {
        rId++;
        rounds[rId].ended = false;
        rounds[rId].startTime = now;
        currentNum = 0;
        betIndex = 0;
    }

    function _buyCore() private {
        //Record user's numbers;record player
        uint256[2] memory _tmpNums;
        _tmpNums[0] = currentNum.add(1);
        
        uint256 nums = msg.value.div(NUM_COST);
        currentNum = currentNum.add(nums);
        if (currentNum > NUM_COUNT) {
            msg.sender.transfer(currentNum.sub(NUM_COUNT).mul(NUM_COST));
            currentNum = NUM_COUNT;
        }
        
        _tmpNums[1] = currentNum;
        rounds[rId].playerNums[msg.sender].push(_tmpNums);

        uint256 bet = 0;
        bet |= currentNum << 240;
        bet |= uint(msg.sender);
        
        //betsArrays.push(bets);
        if (betIndex == betsArray.length) {
            //betsArrays.length += 1;
            betsArray.push(bet);
        } else {
            betsArray[betIndex] = bet;
        }
        betIndex++;

        //End this round
        if (currentNum == NUM_COUNT) {
            rounds[rId].ended = true;
            rounds[rId].endTime = now;
            rounds[rId].blockNum = block.number;
        }
        emit LNEvents.OnBuy(uint8(ResCode.Success), rId, now, rounds[rId].playerNums[msg.sender], msg.sender);
    }

    function _getOpenNum(bytes32 openHash) private pure returns(uint256) {
        uint256 openNumber = uint256(openHash).mod(NUM_COUNT).add(1); //1~10000
        return openNumber;
    }

    function _endRound() private {
        //1. Open round win number
        uint256 blockNumber = rounds[rId].blockNum;
        uint256 openBlockNumber = blockNumber.add(1);
        // uint256 openBlockNumber = blockNumber;
        bytes32 openHash = blockhash(openBlockNumber);
        uint256 openNumber = _getOpenNum(openHash);

        rounds[rId].luckyNum = openNumber; //Round result
        rounds[rId].luckyHash = openHash;

        //2. Who win
        uint256 number = 0;
        number |= openNumber << 240;
        number = betsArray[_binarySearch(number)];
        //this number means (1<<240)-1
        number = number & (1766847064778384329583297500742918515827483896875618958121606201292619775);
        address winnerAddr = address(number);
        rounds[rId].winner = winnerAddr;

        //3. gain to win player
        uint256 benefialGain = NUM_COST.mul(NUM_COUNT).mul(BENEFIAL).div(100);  //2%
        uint256 winnerGain = NUM_COST.mul(NUM_COUNT).sub(benefialGain);

        winPlayers[winnerAddr] = winPlayers[winnerAddr].add(winnerGain);
        // emit LogPlayer(players[rounds[rId].winner]);
        //3. start new round
        _startNewRound();
    }

    function _binarySearch(uint256 num) private view returns (uint256) {
        if (betIndex == 1) return 0;
        if (num < betsArray[0]) return 0;
        
        uint low = 0;
        uint high = betIndex-1;

        while (low < high) {
            uint middle = (low+high)/2;
            if (low+1 == high) {
                return high;
            }
            if (num > betsArray[middle]) {
                low = middle;
            } else {
                high = middle;
            }
        }
        return 0;
    }

}


library SafeMath {

  /**
  * @dev Multiplies two numbers, reverts on overflow.
  */
  function mul(uint256 _a, uint256 _b) internal pure returns (uint256) {
    // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (_a == 0) {
      return 0;
    }

    uint256 c = _a * _b;
    require(c / _a == _b);

    return c;
  }

  /**
  * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
  */
  function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b > 0); // Solidity only automatically asserts when dividing by 0
    uint256 c = _a / _b;
    // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold

    return c;
  }

  /**
  * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b <= _a);
    uint256 c = _a - _b;

    return c;
  }

  /**
  * @dev Adds two numbers, reverts on overflow.
  */
  function add(uint256 _a, uint256 _b) internal pure returns (uint256) {
    uint256 c = _a + _b;
    require(c >= _a);

    return c;
  }

  /**
  * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
  * reverts when dividing by zero.
  */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}