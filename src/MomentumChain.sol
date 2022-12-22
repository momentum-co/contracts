// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract MomentumChain is Ownable {
  //大致功能說明：官方部署合約一次，挑戰者可用此合約發起多次不同的挑戰，挑戰相關紀錄都在此合約中

  //地址的發起過的挑戰id
  mapping (address => uint[]) public addressToChallengeIds;
  
  //挑戰id對應的挑戰內容
  mapping (uint => Challenge) public idToChallenge;

  //記錄所有挑戰id，array數量當作id使用
  uint[] public challengeIds;

  enum ChallengeState{ UNINITIATED, PROGRESSING, SUCCEEDED, FAILED, GIVEUP }

  //挑戰項目的內容
  struct Challenge {
    address challengeOwner;
    string challengeName;
    string challengeDescription;
    uint challengeDays;
    uint minDays;
    uint betAmount;
    address tokenAddress;
    ChallengeState state;
    uint createdAt;
    Record[] records;
  }

  //挑戰上傳的紀錄
  struct Record {
    uint timestamp;
    string note;
  }
  
  //目前部署時沒想到要設定什麼參數
  constructor() {
  }
  
  //檢查是否是挑戰發起者
  modifier onlyChallengeOwner(uint _challengeId) {
    require(msg.sender == idToChallenge[_challengeId].challengeOwner, "not owner of this challenge");
    _;
  }

  //挑戰者創建挑戰項目
  function createChallenge (
      string memory _challengeName,
      string memory _challengeDescription,
      uint _challengeDays,
      uint _minDays,
      uint _betAmount,
      address _tokenAddress
    ) public {
      uint _challengeId = challengeIds.length + 1;
      
      addressToChallengeIds[msg.sender].push(_challengeId);

      //存挑戰id對應的挑戰內容
      Record[] memory _records;
      idToChallenge[_challengeId] = Challenge(
        msg.sender,
        _challengeName,
        _challengeDescription,
        _challengeDays,
        _minDays,
        _betAmount,
        _tokenAddress,
        ChallengeState.PROGRESSING,
        block.timestamp,
        _records
        //!!上面的_records會有錯，error msg: Copying of type struct MomentumChain.Record memory[] memory to storage not yet supported.
        //還沒細查怎麼處理
      );

      //創建項目時另外打錢進來
      IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _betAmount);
  }

  function uploadProgress(uint _challengeId, string memory _note) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == ChallengeState.PROGRESSING, ""); //需要挑戰進行中才可上傳
    require(challenge.records.length < challenge.challengeDays, ""); //記錄小於總天數才可上傳
    Record storage lastRecord = challenge.records[challenge.records.length - 1];
    require(block.timestamp - lastRecord.timestamp >= 10 hours, ""); //超過冷卻時間10小時後才可上傳
    uint finishAt = challenge.createdAt + challenge.challengeDays * 1 days;
    require(block.timestamp <= finishAt, ""); //超過總天數後不可上傳

    challenge.records.push(Record(block.timestamp, _note));
    
    //超過最低天數，標記狀態為已成功
    if (challenge.records.length >= challenge.minDays) {
      challenge.state = ChallengeState.SUCCEEDED;
    }
  }

  function finishAndWithdrawl(uint _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == ChallengeState.SUCCEEDED, ""); //成功狀態會在uploadProgress()中改
    uint finishAt = challenge.createdAt + challenge.challengeDays * 1 days;
    require(block.timestamp >= finishAt, ""); //已超過總天數才能領
    withdrawl(_challengeId, challenge.betAmount);
  }

  function forceEndChallenge(uint _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == ChallengeState.PROGRESSING, "");//TBD:已達最低天數後還可強制終止嗎？
    uint returnAmount = challenge.betAmount * 9 / 10; //退九成
    withdrawl(_challengeId, returnAmount);
    challenge.betAmount -= returnAmount; //修改該挑戰剩餘的金額，到時官方回收
    challenge.state = ChallengeState.GIVEUP;
  }

  function confiscate(uint _challengeId) public onlyOwner() {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == ChallengeState.FAILED || challenge.state == ChallengeState.GIVEUP, "");  //需要挑戰結束或失敗才能收割
    //TBD:有幾個情形要討論一下
    //1.一直是PROGRESSING狀態，例如上傳一次就放著不玩了
    //2.SUCCEEDED狀態，但一直沒有領
    //可能寫法：非SUCCEEDED狀態且超過挑戰時限就可回收；SUCCEEDED狀態超過一定天數沒領回收？
    withdrawl(_challengeId, challenge.betAmount);
  }

  function withdrawl(uint _challengeId, uint amount) private {
    Challenge storage challenge = idToChallenge[_challengeId];
    IERC20(challenge.tokenAddress).transferFrom(address(this), msg.sender, amount);
  }

}

