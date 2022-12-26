// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract MomentumChain is Ownable {
  //挑戰id對應的挑戰內容
  mapping (uint => Challenge) public idToChallenge;
  
  //挑戰id
  uint nextId;

  enum ChallengeState{ UNINITIATED, PROGRESSING, SUCCEEDED, FAILED, GIVEUP }

  //挑戰項目的內容
  struct Challenge {
    uint8 state;
    uint32 totalDays;
    uint32 minDays;
    uint64 createdAt;
    uint96 betAmount;
    address owner;
    address token;
    string name;
    string description;
    Record[] records;
  }

  //挑戰上傳的紀錄
  struct Record {
    uint timestamp;
    string note;
  }
  
  //檢查是否是挑戰發起者
  modifier onlyChallengeOwner(uint _challengeId) {
    require(msg.sender == idToChallenge[_challengeId].owner, "not owner of this challenge");
    _;
  }

  //挑戰者創建挑戰項目
  function createChallenge (
      string memory _name,
      string memory _description,
      uint32 _totalDays,
      uint32 _minDays,
      uint96 _betAmount,
      address _token
    ) public {

      uint id = nextId++;

      //存挑戰id對應的挑戰內容
      Challenge storage challenge = idToChallenge[id]; 
      challenge.state = uint8(ChallengeState.PROGRESSING);
      challenge.totalDays = uint32(_totalDays);
      challenge.minDays = uint32(_minDays);
      challenge.createdAt = uint64(block.timestamp);
      challenge.betAmount = uint96(_betAmount);
      challenge.owner = msg.sender;
      challenge.token = _token;
      challenge.name = _name;
      challenge.description = _description;
      
      //創建項目時另外打錢進來
      IERC20(_token).transferFrom(msg.sender, address(this), _betAmount);
  }

  function uploadProgress(uint _challengeId, string memory _note) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state != uint8(ChallengeState.FAILED) && challenge.state != uint8(ChallengeState.GIVEUP), "");
    require(challenge.records.length < challenge.totalDays, ""); //記錄小於總天數才可上傳
    Record storage lastRecord = challenge.records[challenge.records.length - 1];
    require(block.timestamp - lastRecord.timestamp >= 10 hours, ""); //超過冷卻時間10小時後才可上傳
    uint finishAt = challenge.createdAt + challenge.totalDays * 1 days;
    require(block.timestamp <= finishAt, ""); //超過總天數後不可上傳

    challenge.records.push(Record(block.timestamp, _note));
    
    //超過最低天數，標記狀態為已成功
    if (challenge.records.length >= challenge.minDays) {
      challenge.state = uint8(ChallengeState.SUCCEEDED);
    }
  }

  //已達成最低次數即可贖回
  function finishAndWithdrawl(uint _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == uint8(ChallengeState.SUCCEEDED), "");
    transferTo(msg.sender, _challengeId, challenge.betAmount);
  }

  function forceEndChallenge(uint _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == uint8(ChallengeState.PROGRESSING), "");
    uint96 returnAmount = challenge.betAmount * 9 / 10; //退九成
    transferTo(msg.sender, _challengeId, returnAmount);
    challenge.betAmount -= returnAmount; //修改該挑戰剩餘的金額，到時官方回收
    challenge.state = uint8(ChallengeState.GIVEUP);
  }

  function confiscate(uint _challengeId) public onlyOwner() {
    Challenge storage challenge = idToChallenge[_challengeId];
    if (challenge.state == uint8(ChallengeState.FAILED) || challenge.state == uint8(ChallengeState.GIVEUP)) {
      transferTo(msg.sender, _challengeId, challenge.betAmount);
    } else {
      uint finishAt = challenge.createdAt + challenge.totalDays * 1 days;
      //進行中狀態但已超過天數
      if (challenge.state == uint8(ChallengeState.PROGRESSING) && block.timestamp >= finishAt) {
        transferTo(msg.sender, _challengeId, challenge.betAmount);
        
      //成功後一段時間沒有拿走，退九成拿一成
      } else if (challenge.state == uint8(ChallengeState.SUCCEEDED) && block.timestamp >= finishAt + 30 days) {
        transferTo(msg.sender, _challengeId, challenge.betAmount * 1 / 10);
        transferTo(challenge.owner, _challengeId, challenge.betAmount * 9 / 10);
      }
    }
    revert("");
  }

  function transferTo(address _receiver, uint _challengeId, uint amount) private {
    Challenge storage challenge = idToChallenge[_challengeId];
    IERC20(challenge.token).transferFrom(address(this), _receiver, amount);
  }

}

