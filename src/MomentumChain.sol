// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract MomentumChain is Ownable {
  //大致功能說明：官方部署合約一次，挑戰者可用此合約發起多次不同的挑戰，挑戰相關紀錄都在此合約中

  //該地址的挑戰者資訊
  mapping (address => string[]) public addressToChallengeIds;

  //挑戰id對應的挑戰
  mapping (string => Challenge) public idToChallenge; // challengeId => Challenge

  string[] challengeIds;

  enum ChallengeState{ PROCESSING, SUCESS, FAILED, GIVEUP }
  //挑戰項目的內容
  struct Challlenge {
    string id;
    address owner;
    strign name;
    string description;
    uint _days;
    uint minRecordCount;
    uint bteAmount;
    address tokenAddress;
    ChallengeState state;
    Record[] records;
    uint createdAt;
  }
  
  //目前部署時沒想到要設定什麼參數
  constructor() {
  }
  
  //檢查是否是挑戰發起者
  modifier onlyChallengeOwner(string memory _challengeId) {
    require(msg.sender == idToChallenge[_challengeId].owner, "not owner of this challenge");
    _;
  }

  //挑戰者創建挑戰項目
  function createChallenge(
      string memory _name,
      string memory _description,
      uint _days,
      uint _minRecordCount,
      uint _betAmount,
      address _tokenAddress
    ) public {
    string memory _challengeId = genChallengeId();

    challengeIds.push(_challengeId);
    addressToChallengeIds[msg.sender].push(_challengeId);

    //存挑戰id對應的挑戰內容
    Record[] memory _records;
    idToChallenge[_challengeId] = Challlenge(
      _challengeId,
      msg.sender,
      _name,
      _description,
      _days,
      _minRecordCount,
      _betAmount,
      _tokenAddress,
      ChallengeState.PROCESSING,
      _records,
      block.timestamp
    );

    //創建項目時另外打錢進來
    withdrawl(_tokenAddress, _betAmount);
  }

  function uploadProgress(string memory _challengeId, string memory _note) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.State == ChallengeState.PROCESSING, "challenge should be processing when using this function");  //需要挑戰進行中才能做withdrawal
    uint t = block.timestamp;
    uint finishAt = challenge.createdAt + challenge._days * 1 days;
    if(t >= finishAt) {
      challenge.state = ChallengeState.FAILED;
      revert("the challenge are finished");
      return;
    }
    Record lastRecord = challenge.records[challenge.records.length - 1];
    require(t - lastRecord <= 6 hours, "upload duplicated record in the same day");
    challenge.records.push(Record(block.timestamp, _note));
  }

  function finishAndWithdrawl(string memory _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.State == ChallengeState.PROCESSING, "challenge should be processing when using this function");  //需要挑戰進行中才能做withdrawal
    require(challenge.records.length >= challenge.minRecordCount, "the records are not enough to finish this challenge"); //紀錄次數至少高於最低比數，代表挑戰成功
    //需要檢查做滿天數才能領錢嗎或及格天數就好？若要檢查要怎麼辦到？感覺無法？
    uint t = block.timestamp;
    uint finishAt = challenge.createdAt + challenge._days * 1 days;
    require(t >= finishAt, "the challenge are not finished");
    withdrawl(challenge.tokenAddress, challenge.betAmount);
    challenge.state = ChallengeState.SUCESS;
  }

  function forceEndChallenge(string memory _challengeId) public onlyChallengeOwner(_challengeId) {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.State == ChallengeState.PROCESSING, "challenge should be processing when using this function");  //需要挑戰進行中才能放棄
    uint returnAmount = challenge.betAmount * 9 / 10; //退九成
    withdrawl(challenge.tokenAddress, returnAmount);
    challenge.betAmount -= returnAmount; //修改該挑戰剩餘的金額，到時官方回收
    challenge.state = ChallengeState.GIVEUP;
  }

  function confiscate(string memory _challengeId) public onlyOwner() {
    Challenge storage challenge = idToChallenge[_challengeId];
    require(challenge.State == ChallengeState.FAILED || challenge.State == ChallengeState.GIVEUP, "challenge should be failed or giveup when using this function");  //需要挑戰失敗才能收割
    withdrawl(challenge.tokenAddress, challenge.betAmount);
  }

  function withdrawl(string memory tokenAddress, uint amount) private {
    IERC20(tokenAddress).transferFrom(address(this), msg.sender, amount);
  }

  //TODO: 確認是否有更好產生unique id的方式
  // 產生獨一無二的challenge id (先不考慮concurrency)
  function genChallengeId() private returns(string memory) {
    uint t = block.timestamp;
    address s = msg.sender;
    uint len = challengeIds.length + 1;
    return keccak256(abi.encodePacked(t, s, len));
  }

  // 獲取最新X筆的challenge id
  function getLastestChallengeIds(uint limit) public view returns(string[]) {
    string[] ids;
    for (uint i = challengeIds.length - 1; i >= challengeIds.length- limit ; i --){
      ids.push(challengeIds[i]);
    }
    return ids;
  }
}

