// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

abstract contract ILunchBox  {

    struct Draw {
      uint256 drawId;
      uint256 startDate;
      uint256 endDate;
      uint256 poolInital;
      uint256 poolEnd;
      uint256 result;
      uint256 pool;
      mapping(uint256 => uint256) bets;
      mapping(address => BetOrder) orders;
    }

    struct BetOrder {
      uint256 number;
      uint256 bet;
    }

    struct DrawSetup {
      uint256 number;
      uint256 bet;
      address account;
      uint256 drawId;
    }

    // function betOrder(uint256 drawId,uint256 _number,uint256 _bet) external payable virtual;
    // function checkMatchresult(uint256 _drawId) external payable virtual;


}
