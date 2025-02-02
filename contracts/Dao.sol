// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CeloDao is AccessControl, ReentrancyGuard {

    uint256 totalProposals;
    uint256 balance;

    uint256 immutable STAKEHOLDER_MIN_CONTRIBUTION = 0.1 ether;
    uint256 immutable MIN_VOTE_PERIOD = 5 minutes;
    bytes32 private immutable COLLABORATOR_ROLE = keccak256("collaborator");
    bytes32 private immutable STAKEHOLDER_ROLE = keccak256("stakeholder");

    mapping(uint256 => Proposals) private raisedProposals;
    mapping(address => uint256[]) private stakeholderVotes;
    mapping(uint256 => Voted[]) private votedOn;
    mapping(address => uint256) private contributors;

    struct Proposals {
        uint256 id;
        uint256 amount;
        uint256 upVote;
        uint256 downVotes;
        uint256 duration;
        string title;
        string description;
        bool paid;
        bool passed;
        address payable beneficiary;
        address propoper;
        address executor;
    }

    struct Voted {
        address voter;
        uint256 timestamp;
        bool chosen;
    }

    modifier stakeholderOnly(string memory message) {
        require(hasRole(STAKEHOLDER_ROLE,msg.sender),message);
        _;
    }
    modifier contributorOnly(string memory message){
        require(hasRole(COLLABORATOR_ROLE,msg.sender),message);
        _;
    }

    event ProposalAction(
        address indexed creator,
        bytes32 role,
        string message,
        address indexed beneficiary,
        uint256 amount
    );

    event VoteAction(
        address indexed creator,
        bytes32 role,
        string message,
        address indexed beneficiary,
        uint256 amount,
        uint256 upVote,
        uint256 downVotes,
        bool chosen
    );

    constructor(){
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // proposal creation
    function createProposal (
        string calldata title,
        string calldata description,
        address beneficiary,
        uint256 amount
    )external stakeholderOnly("Only stakeholders are allowed to create Proposals") returns(Proposals memory){
        uint256 currentID = totalProposals++;
        Proposals storage StakeholderProposal = raisedProposals[currentID];
        StakeholderProposal.id = currentID;
        StakeholderProposal.amount = amount;
        StakeholderProposal.title = title;
        StakeholderProposal.description = description;
        StakeholderProposal.beneficiary = payable(beneficiary);
        StakeholderProposal.duration = block.timestamp + MIN_VOTE_PERIOD;

        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            'Proposal Raised',
            beneficiary,
            amount
        );
        return StakeholderProposal;
    }

    // voting
    function performVote(uint256 proposalId,bool chosen) external
    stakeholderOnly("Only stakeholders can perform voting")
    {
        Proposals storage StakeholderProposal = raisedProposals[proposalId];
        handleVoting(StakeholderProposal);
        if(chosen) StakeholderProposal.upVote++;
        else StakeholderProposal.downVotes++;

        stakeholderVotes[msg.sender].push(
            StakeholderProposal.id
        );
        votedOn[StakeholderProposal.id].push(
            Voted(
                msg.sender,
                block.timestamp,
                chosen
            )
        );

        emit VoteAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "PROPOSAL VOTE",
            StakeholderProposal.beneficiary,
            StakeholderProposal.amount,
            StakeholderProposal.upVote,
            StakeholderProposal.downVotes,
            chosen
        );
    }

    // handling vote
    function handleVoting(Proposals storage proposal) private {
        if (proposal.passed || proposal.duration <= block.timestamp) {
            proposal.passed = true;
            revert("Time has already passed");
        }
        uint256[] memory tempVotes = stakeholderVotes[msg.sender];
        for (uint256 vote = 0; vote < tempVotes.length; vote++) {
            if (proposal.id == tempVotes[vote])
                revert("double voting is not allowed");
        }

    }

    // pay beneficiary
    function payBeneficiary(uint proposalId) external
    stakeholderOnly("Only stakeholders can make payment") nonReentrant() {
        Proposals storage stakeholderProposal = raisedProposals[proposalId];
        require(balance >= stakeholderProposal.amount, "insufficient fund");
        if(stakeholderProposal.paid == true) revert("payment already made");
        if(stakeholderProposal.upVote <= stakeholderProposal.downVotes) revert("insufficient votes");

        pay(stakeholderProposal.amount,stakeholderProposal.beneficiary);
        stakeholderProposal.paid = true;
        stakeholderProposal.executor = msg.sender;
        balance -= stakeholderProposal.amount;

        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "PAYMENT SUCCESSFULLY MADE!",
            stakeholderProposal.beneficiary,
            stakeholderProposal.amount
        );
    }

    // payment functionality
    function pay(uint256 amount,address to) internal {
        (bool success,) = payable(to).call{value : amount}("");
        require(success, "payment failed");
    }

    // contribution functionality
    function contribute() payable external returns(uint256){
        require(msg.value > 0 ether, "invalid amount");
        if (!hasRole(STAKEHOLDER_ROLE, msg.sender)) {
            uint256 totalContributions = contributors[msg.sender] + msg.value;

            if (totalContributions >= STAKEHOLDER_MIN_CONTRIBUTION) {
                contributors[msg.sender] += msg.value;
                 _grantRole(STAKEHOLDER_ROLE,msg.sender);
                 _grantRole(COLLABORATOR_ROLE, msg.sender);
            }
            else {
                contributors[msg.sender] += msg.value;
                 _grantRole(COLLABORATOR_ROLE,msg.sender);
            }
        }
        else{
            contributors[msg.sender] += msg.value;
        }

        balance += msg.value;
        emit ProposalAction(
            msg.sender,
            STAKEHOLDER_ROLE,
            "CONTRIBUTION SUCCESSFULLY RECEIVED!",
            address(this),
            msg.value
        );

        return balance;
    }

    // get single proposal
    function getProposals(uint256 proposalID) external view returns(Proposals memory) {
        return raisedProposals[proposalID];
    }

    // get all proposals
    function getAllProposals() external view returns(Proposals[] memory props){
        props = new Proposals;
        for (uint i = 0; i < totalProposals; i++) {
            props[i] = raisedProposals[i];
        }

    }

    // get a specific proposal votes
    function getProposalVote(uint256 proposalID) external view returns(Voted[] memory){
        return votedOn[proposalID];
    }

    // get stakeholders votes
    function getStakeholdersVotes() stakeholderOnly("Unauthorized") external view returns(uint256[] memory){
        return stakeholderVotes[msg.sender];
    }

    // get stakeholders balances
    function getStakeholdersBalances() stakeholderOnly("unauthorized") external view returns(uint256){
        return contributors[msg.sender];
    }

    // get total balance
    function getTotalBalance() external view returns(uint256){
        return balance;
    }

    // check if stakeholder
    function stakeholderStatus() external view returns(bool){
        return contributors[msg.sender] >= STAKEHOLDER_MIN_CONTRIBUTION;
    }

    // check if contributor
    function isContributor() external view returns(bool){
        return contributors[msg.sender] > 0;
    }

    // check contributors balance
    function getContributorsBalance() contributorOnly("unathorized") external view returns(uint256){
        return contributors[msg.sender];
    }
}
