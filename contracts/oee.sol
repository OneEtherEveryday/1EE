pragma solidity ^0.5.0;

import "./Ownable.sol";
import "./strings.sol";
import "./usingOraclize.sol";


contract oee is Ownable, usingOraclize{

  using strings for *;

  uint16[100] stopCandidateBlocks = [
      1638,1981,2213,2394,2544,2674,2789,2892,2987,3074,
      3155,3231,3302,3369,3433,3494,3553,3608,3662,3714,
      3763,3811,3858,3903,3947,3989,4030,4071,4110,4148,
      4185,4222,4257,4292,4326,4359,4392,4424,4456,4487,
      4517,4547,4576,4605,4633,4661,4688,4715,4742,4768,
      4794,4819,4845,4869,4894,4918,4942,4965,4988,5011,
      5034,5056,5078,5100,5122,5143,5164,5185,5206,5226,
      5247,5267,5287,5306,5326,5345,5364,5383,5402,5420,
      5439,5457,5475,5493,5511,5528,5546,5563,5580,5597,
      5614,5631,5648,5664,5680,5697,5713,5729,5745,5760
  ];

  uint public stage = 0;
  uint public addBlocksRange = 20;  // if there was transaction in recent 5 minutes
  uint public addBlocks = 40; // this game is extended 10 minutes!

  uint public gasPriceForOracleQuery = 10000000000; // 10 Gwei
  uint public gasLimitForOracleQuery = 400000;

  mapping(uint=>uint) public mapStageState;  // the first buyer after endingBlock will make this flag to TRUE. he will be refunded.
  mapping(uint=>address[]) public accountHistory;
  mapping(uint=>uint[]) public updatedBlockHistory;

  mapping(uint=>address) public mapWinnerAddress; // winners
  mapping(uint=>uint) public mapPrizeEthersInFinney;      // prize ethers
  mapping(uint=>uint) public mapWinnerChanged;    // change count
  mapping(uint=>uint) public mapStartingBlock;    // starting block
  mapping(uint=>uint) public mapEndingBlock;      // ending block
 

  mapping(bytes32=>bool) internal RNReqTable;


  address public winnerAddress = 0x3220cd96DF6bF3e9Fd4c4c14286691017E3CEb4f;
  uint public winnerChangeFee = 60; // in finney, 0.06 eth
  uint public winnerChangeCnt = 0;
  //uint public prizeEthers = 0;

  uint private startingBlock = 0;
  uint private endingBlock = 0;
  
  uint256 constant STATE_READY = 0;
  uint256 constant STATE_RUNNING = 1;
  uint256 constant STATE_FINISHED = 2;


  constructor() public{
    //OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);  // for ethereum-bridge
    OAR = OraclizeAddrResolverI(0x146500cfd35B22E4A392Fe0aDc06De1a1368Ed48);  // for RINKEBY TESTNET
    //OAR = OraclizeAddrResolverI(0x1d3B2638a7cC9f2CB3D298A3DA7a90B67E5506ed);  // for MAINNET
    mapStageState[0] = STATE_READY;
  }


  function GetAccountHistory(uint stage)public view returns(address[] memory){
    return accountHistory[stage];
  }
  function GetUpdatedBlockHistory(uint stage)public view returns(uint[] memory){
    return updatedBlockHistory[stage];
  }
  
  function GetStageTrials(uint stage) public view returns(uint){
    return accountHistory[stage].length;
  }

  function GetBlockNumber() public view returns(uint){
    return block.number;
  }

  function GetState() public view returns(uint){
    return mapStageState[stage];
  }

  function ChangeWinner() public payable returns(bool){
    require(msg.value == winnerChangeFee * 10**15, "Winner Change Fee Not Matched");
    require(mapStageState[stage] == STATE_RUNNING, "1EE is not available at this moment!");

    // Stage closer! this player's payment have to be refunded!
    if(endingBlock < block.number){
      mapWinnerAddress[stage] = winnerAddress;
      mapStartingBlock[stage] = startingBlock;
      mapEndingBlock[stage] = endingBlock;
      mapWinnerChanged[stage] = winnerChangeCnt;
      mapStageState[stage] = STATE_FINISHED;
      TransferFund(msg.sender, msg.value);  // execute refund
      mapPrizeEthersInFinney[stage] = address(this).balance / 10**15;
      TransferFund(winnerAddress, address(this).balance);
      stage++;
      mapStageState[stage] = STATE_READY;
      return false;
    }

    if(block.number > endingBlock - addBlocksRange){
      endingBlock = endingBlock + addBlocks;  // HAVE TO BE RELEASED ON MAINNET!!!!!!!
    }

    winnerChangeCnt++;
    winnerAddress = msg.sender;
    
    accountHistory[stage].push(msg.sender);
    updatedBlockHistory[stage].push(block.number);

    //prizeEthers = prizeEthers + (winnerChangeFee)/2;
    TransferFund(owner, msg.value/2);
    return true;
  }


  function ConfigNewGame() public payable onlyOwner{
    require(mapStageState[stage] == STATE_READY, "Stage has to be under READY STATE, before starting the new one!");
    require(address(this).balance >= 1 ether, "Insufficient Fund!");
    
    if (oraclize_getPrice("WolframAlpha") > msg.sender.balance) {
      require(false, "first err");
      //LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
    } else {
      oraclize_setCustomGasPrice(gasPriceForOracleQuery); // set gas price to 10 Gwei
      bytes32 queryId = oraclize_query("WolframAlpha", "2 unique random numbers between 0 to 99", gasLimitForOracleQuery);
      //emit EventRNRequested(queryId, block.number, block.timestamp);
      SetRNReqTable(queryId, true);
    }
  }


  function SetRNReqTable(bytes32 _id, bool _val) internal{
    RNReqTable[_id] = _val;
  }
  function SetRNReqTable_Manual(bytes32 _id, bool _val) public onlyOwner{
    RNReqTable[_id] = _val;
  }

  function SetGasPrice(uint price) external onlyOwner{ // default : 10000000000 (10 Gwei)
    gasPriceForOracleQuery = price;
  }

  function SetGasLimit(uint limit) external onlyOwner{ // default : 400000 gas
    gasLimitForOracleQuery = limit;
  }

  function __callback(bytes32 queryId, string memory result) public {  // callback function of GetNewRandomNumbersFromOracle()

    require(msg.sender == oraclize_cbAddress(), "cbAddress not matched, malicious user detected");
    require(RNReqTable[queryId] == true, "invalid response with wrong id");
    SetRNReqTable(queryId, false);

    uint rn1 = 0;
    uint rn2 = 0;

    strings.slice memory s = result.toSlice();
    strings.slice memory delim = ", ".toSlice();
    s.beyond("{".toSlice()).until("}".toSlice());

    rn1 = parseInt(s.split(delim).toString());
    require(((0 <= rn1) && (rn1 <= 99)), "RN out of range");

    startingBlock = block.number;
    endingBlock = block.number + stopCandidateBlocks[rn1];  // HAVE TO BE RELEASED ON MAINNET!!!!!!!
    //endingBlock = block.number + 50 + (rn1);    // HAVE TO REMOVE ON MAINNET!!!! JUST FOR LOCAL TESTNET !!

    winnerAddress = owner;
    winnerChangeCnt = 0;
    mapStageState[stage] = STATE_RUNNING;
  }

  function EmergencyWithdrawal() external onlyOwner{
    address payable addrTo = address(uint160(owner));
    addrTo.transfer(address(this).balance);
  }

  function TransferFund(address _addressTo, uint _amountInWei) internal{
    address payable addrTo = address(uint160(_addressTo));
    addrTo.transfer(_amountInWei);
  }

  function GetBalance() public view returns(uint){
    return address(this).balance;
  }

  function GetBalanceInFinny() public view returns(uint){
    return address(this).balance/(10**15);
  }

  function GetBlockPassed() public view returns(uint){
    if(mapStageState[stage] == STATE_RUNNING){
      return (block.number - startingBlock);
    }else{
      return (0);
    }
  }


  

  function parseInt(string memory _a) public pure returns (uint) {
      return parseInt(_a, 0);
  }

  // parseInt(parseFloat*10^_b)
  function parseInt(string memory _a, uint _b) public pure returns (uint) {
      bytes memory bresult = bytes(_a);
      uint mint = 0;
      bool decimals = false;
      for (uint i=0; i<bresult.length; i++){
          if ((uint8(bresult[i]) >= 48)&&(uint8(bresult[i]) <= 57)){
              if (decimals){
                  if (_b == 0) break;
                  else _b--;
              }
              mint *= 10;
              mint += uint(uint8(bresult[i])) - 48;
          } else if (uint8(bresult[i]) == 46) decimals = true;
      }
      if (_b > 0) mint *= 10**_b;
      return mint;
  }

}
