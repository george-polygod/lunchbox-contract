// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

abstract contract ILunchBox  {

    struct Draw {
      uint256 drawId;
      uint256 startDate;
      uint256 endDate;
      uint256 endDateRequest;
      uint256 poolInital;
      uint256 betEnd;
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

    function betOrder(uint256 _number,uint256 _bet) external payable virtual;
    function checkDrawresult(uint256 _drawId) external payable virtual;
    function claimReward(uint256 _drawId,address account)  public virtual;
    function earned(address account,uint256 _drawId) public view virtual returns (uint256);
    function userOrder(address account,uint256 _drawId) public view virtual returns (uint256 number,uint256 bet);
    function pool(uint256 _drawId,uint256 _burn) public view virtual returns (uint256);
    function payout(uint256 _drawId,uint256 _burn) public view virtual returns (uint256 reward);


}
