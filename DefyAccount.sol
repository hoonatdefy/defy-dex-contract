pragma solidity ^0.4.24;

interface AccountLevels {
    function accountLevel(address user) public view returns(uint256);
}

contract AccountLevelStorage is AccountLevels {
    mapping (address => uint256) public accountLevels;

    function accountLevel(address user) public view returns(uint256) {
        return accountLevels[user];
    }

    function setAccountLevel(address user, uint256 level) public {
        accountLevels[user] = level;
    }
}