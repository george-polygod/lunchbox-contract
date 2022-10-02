// SPDX-License-Identifier: MIT
// solhint-disable not-rely-on-time
pragma solidity ^0.8.4;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./ILunchBox.sol";



contract LunchBox is ReentrancyGuardUpgradeable,OwnableUpgradeable,AccessControlUpgradeable,ILunchBox,ChainlinkClient {
    using SafeMath for uint256;
    using Chainlink for Chainlink.Request;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20Upgradeable public token;
    address private oracle;
    bytes32 private jobId;
    uint256 public currentDraw_id;
    uint256 public fee;
    uint256 public time;
    uint256 public bnbFee; 
    uint256 public tax; // beeps
    uint256 public burnTax; // beeps
    address private dev;


    mapping(uint256 => Draw) public drawItems;
    mapping(bytes32 => DrawSetup) public drawSetup;
    mapping(address => mapping(uint256 => uint256)) public userRewardPerTokenPaid;

    function initialize(address _token) public initializer {
      __Ownable_init();
      __ReentrancyGuard_init();
      __AccessControl_init();
    
      token = IERC20Upgradeable(_token);
      setChainlinkToken(0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06);
      oracle = 0xCC79157eb46F5624204f47AB42b3906cAA40eaB7;
      jobId = "ca98366cc7314957b8c012c72f05aeeb";
      fee = 0.1 * 10 ** 18; // (Varies by network and job)
    }


    /* ========= MATCH SETUP ======== */

    function betOrder(
      uint256 _number,
      uint256 _burnBet
    ) external  nonReentrant payable{
       Draw storage item = drawItems[currentDraw_id];
       if(block.timestamp >= item.betEnd)
       {
           currentDraw_id += 1;
           item = drawItems[currentDraw_id];
       }
       require(_number > 0, "Number must be > 0");
       require(_burnBet == 1 || _burnBet == 2, "Choose 1 for down or 2 for up");
       require(item.orders[msg.sender].number == 0, "Already Betted");
       require(msg.value >= bnbFee ,"Not enought BNBs"); 
       require(token.balanceOf(msg.sender) >= _number ,"Not enought Tokens"); 
       
        if(item.drawId == 0 && item.startDate == 0)
        {
            setupMatch(_number,_burnBet,msg.sender);
        }
        else{
            setupOrder(_number,_burnBet,msg.sender);
        }

     
      
    }
    

    function setupMatch(uint256 _number,uint256 _burnBet,address _account) private {
        Draw storage item = drawItems[currentDraw_id];
        item.drawId = currentDraw_id;
        item.startDate = block.timestamp;
        item.betEnd = block.timestamp.add(time);
        item.endDate = block.timestamp.add(time*2);
        item.pool = 0;

        bytes32 requestId = requestFirstBurnData();
        drawSetup[requestId] = DrawSetup({number:_number,bet:_burnBet,account:_account,drawId:currentDraw_id});
    }


    function requestFirstBurnData() private returns (bytes32 requestId) 
    {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfillFirst.selector);
        string memory api = "https://earnz.directus.app/lunchbox/getData";
        request.add("get", api);
        request.add("path", "data,total_daily_burn"); 
        request.addInt("times", 10**2);

        return sendChainlinkRequestTo(oracle, request, fee);
    }
    
    
    /**
     * Receive the response in the form of uint256
     */ 
    function fulfillFirst(bytes32 _requestId, uint256 _burn) public recordChainlinkFulfillment(_requestId)
    {
       
        DrawSetup memory _drawSetup = drawSetup[_requestId];

        drawItems[_drawSetup.drawId].poolInital = _burn;
        setupOrder(_drawSetup.number,_drawSetup.bet,_drawSetup.account);
        
    }


    function setupOrder(uint256 _number,uint256 _burnBet,address account) private {
        Draw storage item = drawItems[currentDraw_id];
        require(block.timestamp >= item.startDate && item.betEnd > block.timestamp,"draw completed/not started");
        require(item.poolInital > 0,"pool hasn't started");

        BetOrder memory order = BetOrder({number:_number,bet:_burnBet});

        item.bets[_burnBet] = item.bets[_burnBet].add(_number);
        item.pool = item.pool.add(_number);
        item.orders[account] = order;

        token.transferFrom(account,address(this),_number);

        emit OrderCreated(currentDraw_id,block.timestamp,account,_number,_burnBet);
    }


    /* ========= DRAW RESULT ======== */

    function checkDrawresult(uint256 _drawId) external nonReentrant payable{
        Draw storage item = drawItems[_drawId];

        require(msg.value >= bnbFee ,"Not enought BNBs"); 
        require(block.timestamp >= item.endDate && item.endDate > 0,"Not finished yet");
        require(item.result == 0,"Result already live"); 

        if(item.endDateRequest == 0 || msg.sender == owner())
        {
            bytes32 requestId = requestBurnData();
            drawSetup[requestId].drawId = _drawId;
            drawSetup[requestId].account = msg.sender;
        }

        item.endDateRequest = block.timestamp;
        emit ResultRequested(_drawId,block.timestamp);
    }



    function requestBurnData() private returns (bytes32 requestId) 
    {
        Chainlink.Request memory request = buildChainlinkRequest(jobId, address(this), this.fulfill.selector);
        string memory api = string(abi.encodePacked("https://earnz.directus.app/lunchbox/getData?time=",block.timestamp));
        request.add("get", api);
        request.add("path", "data,total_daily_burn"); 
        request.addInt("times", 10**2);

        return sendChainlinkRequestTo(oracle, request, fee);
    }
    
    
    /**
     * Receive the response in the form of uint256
     */ 
    function fulfill(bytes32 _requestId, uint256 _burn) public recordChainlinkFulfillment(_requestId)
    {
        uint256 _drawId = drawSetup[_requestId].drawId;
        drawItems[_drawId].poolEnd = _burn;
        uint256 result = 0;
        if(drawItems[_drawId].poolEnd >= drawItems[_drawId].poolInital)
        {
            result = 2;
        }
        else{
            result = 1;
        }

        drawItems[_drawId].result = result;
        uint256 _pool = drawItems[_drawId].pool;
        uint256 burnTaxTotal = _pool.mul(burnTax).div(10**4);
        uint256 taxTotal = _pool.mul(tax).div(10**4);

         _pool = _pool.sub(burnTaxTotal).sub(taxTotal);

         drawItems[_drawId].pool = _pool;
         if(burnTaxTotal > 0)
         {
                token.transfer(address(0xdead), burnTaxTotal);
         }

         if(taxTotal > 0)
         {
                token.transfer(dev, taxTotal);
         }

        if(userRewardPerTokenPaid[drawSetup[_requestId].account][_drawId] == 0)
        {
            claimReward(_drawId,drawSetup[_requestId].account);
        }
        
    }

 

    function claimReward(uint256 _drawId,address account) public nonReentrant {
        Draw storage item = drawItems[_drawId];
        require(item.result > 0 && block.timestamp >= item.endDate,"Result not yet available");
        require(userRewardPerTokenPaid[account][_drawId] == 0,"No Rewards");

        uint256 reward = earned(account,_drawId);

        if (reward > 0) {
            userRewardPerTokenPaid[account][_drawId] = reward;
             token.transfer(account, reward);
            
            emit RewardPaid(_drawId,block.timestamp,account, reward);
        }
    }

    function pool(uint256 _drawId,uint256 _burn) public view  returns (uint256) {
         Draw storage item = drawItems[_drawId];
         return item.bets[_burn];
    }

  

    function payout(uint256 _drawId,uint256 _burn) public view  returns (uint256 reward) {
         Draw storage item = drawItems[_drawId];
         if(item.bets[_burn] > 0)
         {
            reward =  (item.pool).mul(100).div(item.bets[_burn]);
         }else{
            reward = (item.pool).mul(100);
         }        
    }


    function userOrder(address account,uint256 _drawId) public view  returns (uint256 number,uint256 bet) {
         Draw storage item = drawItems[_drawId];
         return (item.orders[account].number,item.orders[account].bet);      
    }

    function earned(address account,uint256 _drawId) public view  returns (uint256) {
         Draw storage item = drawItems[_drawId];
         if(item.bets[item.result] > 0 && item.orders[account].bet == item.result){
                return  (item.pool).sub(burnTax).mul(10**18).div(item.bets[item.result]).mul(item.orders[account].number).div(10**18).sub(userRewardPerTokenPaid[account][_drawId]);
         }
         else{
             return  0;
         }
         
    }
    

    /* OWNER FUNCTIONS */


    function withdrawTokenFunds(address token_add,address receiver,uint256 amount) external onlyAdmins
    {
        IERC20Upgradeable ercToken = IERC20Upgradeable(token_add);
        ercToken.transfer(receiver,amount);
    }

    function emergencyWithdraw(address payable to_, uint256 amount_) external onlyAdmins {
        to_.transfer(amount_);
    }


    function updateDev(address _dev) external onlyAdmins
    {
        dev = _dev;
    }

    function updateToken(address _token) external onlyAdmins
    {
        token = IERC20Upgradeable(_token);
    }

    function updateTime(uint256 _time) external onlyAdmins
    {
        time = _time;
    }

    function updateTax(uint256 _tax,uint256 _burnTax,uint256 _fee,uint256 _bnbFee) external onlyAdmins
    {
        tax = _tax;
        burnTax = _burnTax;
        fee = _fee;
        bnbFee = _bnbFee;
    }

    function addAdminRole(address admin) public onlyOwner{
        _setupRole(ADMIN_ROLE, admin);
    }

    function revokeAdminRole(address admin) public onlyAdmins{
        _revokeRole(ADMIN_ROLE, admin);
    }

    function adminRole(address admin) public view returns(bool){
        return hasRole(ADMIN_ROLE,admin);
    }

    modifier onlyAdmins() {
        require(hasRole(ADMIN_ROLE, msg.sender) || owner() == msg.sender, "You don't have permission");
        _;
    }


  
    event OrderCreated(uint256 indexed drawId,uint256 time,address indexed user,uint256 _number,uint256 _burnBet);
    event RewardPaid(uint256 indexed drawId,uint256 time,address indexed user, uint256 reward);
    event ResultRequested(uint256 indexed drawId,uint256 time);
 
}
