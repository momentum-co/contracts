// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/token/ERC721/ERC721.sol";

/**
 * @title MomentumChallenge
 */
contract MomentumChallenge is Ownable, ERC721 {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    enum ChallengeState {
        UNINITIATED,
        PROGRESSING,
        SUCCEEDED,
        FAILED,
        GIVEUP
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          Structs                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ///@dev 挑戰項目的內容
    struct Challenge {
        uint8 state;
        uint32 totalDays;
        uint32 minDays;
        uint64 finishedAt;
        uint96 betAmount;
        address token;
        string name;
        string description;
        Record[] records;
    }

    ///@dev 挑戰上傳的紀錄
    struct Record {
        uint256 timestamp;
        string note;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      State Variables                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ///@dev mapping from challenge ID to detail
    mapping(uint256 => Challenge) public idToChallenge;

    ///@dev id that will be assigned to the next challenge
    uint256 public nextId;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    ///@dev challenge not in progress, cannot upload progress
    error ChallengeEnded();

    ///@dev challenge not in progress, cannot giveup
    error NotInProgress();

    ///@dev challenge has reached the max amount of uploads
    error ChallengeFinished();

    ///@dev cannot upload twice within 10 hours
    error UploadInCoolDown();

    ///@dev challenge has passed the expiration
    error ChallengeExpired();

    ///@dev challenge has not passed the expiration
    error ChallengeNotExpired();

    ///@dev caller is not the challenge caller
    error NotChallengeOwner();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Events                             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        Modifiers                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //檢查是否是挑戰發起者
    modifier onlyChallengeOwner(uint256 _challengeId) {
        require(msg.sender == ownerOf(_challengeId), "not owner of this challenge");
        _;
    }

    constructor() ERC721("Momentum Challenge", "Momentum") {}

    /**
     * @notice create a challenge
     * @return id id of the new created challenge
     */
    function createChallenge(
        string memory _name,
        string memory _description,
        uint32 _totalDays,
        uint32 _minDays,
        uint96 _betAmount,
        address _token
    ) external returns (uint256 id) {
        id = nextId++;

        // update the staet for the challenge
        Challenge storage challenge = idToChallenge[id];
        challenge.state = uint8(ChallengeState.PROGRESSING);
        challenge.totalDays = uint32(_totalDays);
        challenge.minDays = uint32(_minDays);
        challenge.finishedAt = uint64(block.timestamp + _totalDays * 1 days);
        challenge.betAmount = uint96(_betAmount);
        challenge.token = _token;
        challenge.name = _name;
        challenge.description = _description;

        // create NFT for msg.sender as proof of ownership
        _mint(msg.sender, id);

        // pull token from msg.sender
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _betAmount);
    }

    /**
     * @notice upload progress for a challenge
     * @dev can only be called by challenge owner
     * @param _challengeId id of the challenge
     */
    function uploadProgress(uint256 _challengeId, string memory _note) external onlyChallengeOwner(_challengeId) {
        Challenge storage challenge = idToChallenge[_challengeId];

        // cannot upload if challenge is already marked as failed or given up
        if (challenge.state != uint8(ChallengeState.PROGRESSING) && challenge.state != uint8(ChallengeState.SUCCEEDED)) {
            revert ChallengeEnded();
        }

        //記錄小於總天數才可上傳
        if (challenge.records.length >= challenge.totalDays) revert ChallengeFinished();

        if (block.timestamp > challenge.finishedAt) revert ChallengeExpired();

        Record storage lastRecord = challenge.records[challenge.records.length - 1];
        if (block.timestamp - lastRecord.timestamp < 10 hours) revert UploadInCoolDown(); //超過冷卻時間10小時後才可上傳

        challenge.records.push(Record(block.timestamp, _note));

        //達最低天數，標記狀態為已成功並退款。之後再上傳不會再觸發
        if (challenge.records.length == challenge.minDays) {
            challenge.state = uint8(ChallengeState.SUCCEEDED);
            // Send back the money after you finish the challenge!
            IERC20(challenge.token).safeTransfer(msg.sender, challenge.betAmount);
        }
    }

    /**
     * @notice give up a challenge and get back 90% of deposit
     * @dev can only be called by challenge owner
     * @param _challengeId id of the challenge
     */
    function giveup(uint256 _challengeId) external onlyChallengeOwner(_challengeId) {
        Challenge storage challenge = idToChallenge[_challengeId];
        if (challenge.state != uint8(ChallengeState.PROGRESSING)) revert NotInProgress();

        // too late to give up!
        if (block.timestamp > challenge.finishedAt) revert ChallengeExpired();

        challenge.state = uint8(ChallengeState.GIVEUP);

        uint96 total = challenge.betAmount;

        // 90% go back to the challenger
        uint96 returnAmount = total * 9 / 10;
        IERC20(challenge.token).safeTransfer(msg.sender, returnAmount);
        // 10% go to the contract owner
        IERC20(challenge.token).safeTransfer(owner(), total - returnAmount);
    }

    /**
     * @notice collect token from a failed challenge
     * @dev can only be called by contract owner
     * @param _challengeId id of the challenge
     */
    function confiscate(uint256 _challengeId) external onlyOwner {
        Challenge storage challenge = idToChallenge[_challengeId];
        if (challenge.state != uint8(ChallengeState.PROGRESSING)) revert NotInProgress();

        // the challenge is still in progress.
        if (block.timestamp < challenge.finishedAt) revert ChallengeNotExpired();

        // 進行中狀態但已超過天數，挑戰失敗
        challenge.state = uint8(ChallengeState.FAILED);
        IERC20(challenge.token).safeTransfer(msg.sender, challenge.betAmount);
    }
}
