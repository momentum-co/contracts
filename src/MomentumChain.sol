// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract MomentumChain is Ownable {
  //大致功能說明：官方部署合約一次，挑戰者可用此合約發起多次不同的挑戰，挑戰相關紀錄都在此合約中

  //該地址的挑戰者資訊
  mapping (address => ChallengerInfo) public addressToChallengerInfo;
  
  //要存挑戰者數量嗎？想像若要顯示出其他挑戰者內容時，配合上方addressToChallengerInfo使用
  address[] public challengerAddresses;
  
  //挑戰id對應的挑戰者地址，用於判斷是否是挑戰發起者
  mapping (string => address) public eventIdToChallenger; // eventId => ChallengerＡddress
  
  //挑戰id對應的挑戰項目
  mapping (string => ChallengeEvent) public eventIdToEvent; // eventId => ChallengeEvent

  //挑戰者資料與其發起的挑戰內容
  struct ChallengerInfo {
    string name; //挑戰者名稱

    //存挑戰者有多少挑戰項目的id，再去用id去mapping查對應項目細節
    string[] eventIds;
    //承上，或是存成巢狀結構？優缺點之類的？目前寫法是用上面的eventIds
    // ChallengeEvent[] challengeEvents;
  }

  //挑戰項目的內容
  struct ChallengeEvent {
    string eventId;
    string challengeName;
    string challengeDescription;
    uint challengeDays;
    uint minDays;
    uint betAmount;
    address tokenAddress;
    bool challengeClosed;
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
  modifier onlyChallengeOwner(string memory _eventId) {
    require(msg.sender == eventIdToChallenger[_eventId], "not owner of this challenge");
    _;
  }

  //挑戰者創建挑戰項目
  function createChallengeEvent(
      string memory _challengeName,
      string memory _challengeDescription,
      uint _challengeDays,
      uint _minDays,
      uint _betAmount,
      address _tokenAddress
    ) public {
    //todo:產生id，確認什麼型態uint, string, byte?
    string memory _eventId = 'id123';
    
    //增加挑戰者名稱與新增挑戰id，若是第一次創建下面寫法應該有問題？
    ChallengerInfo storage challengerInfo = addressToChallengerInfo[msg.sender];
    //創建時名字已存在就不修改嗎之類的？
    challengerInfo.name = _challengeName;
    challengerInfo.eventIds.push(_eventId);
    
    //存挑戰id對應的挑戰者地址，用於判斷是否是發起者，ex:onlyChallengeOwner()
    eventIdToChallenger[_eventId] = msg.sender;

    //存挑戰id對應的挑戰內容
    Record[] memory _records;
    eventIdToEvent[_eventId] = ChallengeEvent(
      _eventId,
      _challengeName,
      _challengeDescription,
      _challengeDays,
      _minDays,
      _betAmount,
      _tokenAddress,
      false, //challengeClosed
      _records 
      //!!上面的_records會有錯，error msg: Copying of type struct MomentumChain.Record memory[] memory to storage not yet supported.
      //還沒細查怎麼處理
    );

    //創建項目時另外打錢進來
    IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _betAmount);
  }

  function uploadProgress(string memory _eventId, string memory _note) public onlyChallengeOwner(_eventId) {
    ChallengeEvent storage cEvent = eventIdToEvent[_eventId];
    require(!cEvent.challengeClosed, ""); //需要挑戰未結束
    require(cEvent.records.length < cEvent.challengeDays, ""); //記錄小於總天數才可上傳
    //todo: 冷卻時間限制;
    cEvent.records.push(Record(block.timestamp, _note));
  }

  function finishAndWithdrawl(string memory _eventId) public onlyChallengeOwner(_eventId) {
    ChallengeEvent storage cEvent = eventIdToEvent[_eventId];
    require(!cEvent.challengeClosed, "");
    require(cEvent.records.length >= cEvent.minDays, ""); //紀錄次數至少高於最低天數，代表挑戰成功
    //需要檢查做滿天數才能領錢嗎或及格天數就好？若要檢查要怎麼辦到？感覺無法？
    withdrawl(_eventId, cEvent.betAmount);
    cEvent.challengeClosed = true;
  }

  function forceEndChallenge(string memory _eventId) public onlyChallengeOwner(_eventId) {
    ChallengeEvent storage cEvent = eventIdToEvent[_eventId];
    require(!cEvent.challengeClosed, "");
    uint returnAmount = cEvent.betAmount * 9 / 10; //退九成
    withdrawl(_eventId, returnAmount);
    cEvent.betAmount -= returnAmount; //修改該挑戰剩餘的金額，到時官方回收
    cEvent.challengeClosed = true;
  }

  function confiscate(string memory _eventId) public onlyOwner() {
    ChallengeEvent storage cEvent = eventIdToEvent[_eventId];
    require(cEvent.challengeClosed, "");  //需要挑戰已結束才能收割
    withdrawl(_eventId, cEvent.betAmount);
  }

  function withdrawl(string memory _eventId, uint amount) private {
    ChallengeEvent storage cEvent = eventIdToEvent[_eventId];
    IERC20(cEvent.tokenAddress).transferFrom(address(this), msg.sender, amount);
  }

}

