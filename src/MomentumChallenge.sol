// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/token/ERC721/ERC721.sol";

contract MomentumChallenge is Ownable, ERC721 {
  using SafeERC20 for IERC20;

  //挑戰id對應的挑戰內容
  mapping (uint => Challenge) public idToChallenge;
  
  //挑戰id
  uint nextId;

  enum ChallengeState{ UNINITIATED, PROGRESSING, SUCCEEDED, FAILED, GIVEUP }

  ///@dev 挑戰項目的內容
  struct Challenge {
    uint8 state;
    uint32 totalDays;
    uint32 minDays;
    uint64 createdAt;
    uint96 betAmount;
    address token;
    string name;
    string description;
    Record[] records;
  }

  ///@dev 挑戰上傳的紀錄
  struct Record {
    uint timestamp;
    string note;
  }
  
  //檢查是否是挑戰發起者
  modifier onlyChallengeOwner(uint _challengeId) {
    require(msg.sender == ownerOf(_challengeId), "not owner of this challenge");
    _;
  }

  constructor() ERC721("Momentum Challenge", "Momentum") {}

  //挑戰者創建挑戰項目
  function createChallenge (
      string memory _name,
      string memory _description,
      uint32 _totalDays,
      uint32 _minDays,
      uint96 _betAmount,
      address _token
    ) external {

      uint id = nextId++;

      //存挑戰id對應的挑戰內容
      Challenge storage challenge = idToChallenge[id]; 
      challenge.state = uint8(ChallengeState.PROGRESSING);
      challenge.totalDays = uint32(_totalDays);
      challenge.minDays = uint32(_minDays);
      challenge.createdAt = uint64(block.timestamp);
      challenge.betAmount = uint96(_betAmount);
      challenge.token = _token;
      challenge.name = _name;
      challenge.description = _description;

      // create NFT for msg.sender as proof of ownership
      _mint(msg.sender, id);
      
      //創建項目時另外打錢進來
      IERC20(_token).transferFrom(msg.sender, address(this), _betAmount);
  }

  function uploadProgress(uint _challengeId, string memory _note) external onlyChallengeOwner(_challengeId) {
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
  function finishAndWithdrawl(uint _challengeId) external onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == uint8(ChallengeState.SUCCEEDED), "");
    IERC20(challenge.token).safeTransfer(msg.sender, challenge.betAmount);
  }

  function forceEndChallenge(uint _challengeId) external onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.state == uint8(ChallengeState.PROGRESSING), "");
    uint96 returnAmount = challenge.betAmount * 9 / 10; //退九成
    IERC20(challenge.token).safeTransfer(msg.sender, returnAmount);
    challenge.betAmount -= returnAmount; //修改該挑戰剩餘的金額，到時官方回收
    challenge.state = uint8(ChallengeState.GIVEUP);
  }

  function confiscate(uint _challengeId) external onlyOwner() {
    Challenge storage challenge = idToChallenge[_challengeId];
    IERC20 token = IERC20(challenge.token); // cache token
    if (challenge.state == uint8(ChallengeState.FAILED) || challenge.state == uint8(ChallengeState.GIVEUP)) {
      token.safeTransfer(msg.sender, challenge.betAmount);
    } else {
      uint finishAt = challenge.createdAt + challenge.totalDays * 1 days;
      //進行中狀態但已超過天數
      if (challenge.state == uint8(ChallengeState.PROGRESSING) && block.timestamp >= finishAt) {
        token.safeTransfer(msg.sender, challenge.betAmount);
        
      //成功後一段時間沒有拿走，退九成拿一成
      } else if (challenge.state == uint8(ChallengeState.SUCCEEDED) && block.timestamp >= finishAt + 30 days) {
        token.safeTransfer(msg.sender, challenge.betAmount * 1 / 10);
        token.safeTransfer(ownerOf(_challengeId), challenge.betAmount * 9 / 10);
      }
    }
  }

}

