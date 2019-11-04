pragma solidity ^0.4.24;

interface ERC20 {
    function totalSupply() external view returns (uint supply);
    function balanceOf(address _owner) external view returns (uint balance);
    function transfer(address _to, uint _value) external returns (bool success);
    function transferFrom(address _from, address _to, uint _value) external returns (bool success);
    function approve(address _spender, uint _value) external returns (bool success);
    function allowance(address _owner, address _spender) external view returns (uint remaining);
    function decimals() external view returns(uint digits);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}

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

contract DefyDelta {
    using SafeMath for uint;

    address public admin;
    address public feeAccount;
    address public accountLevelsAddr;

    uint public feeMake;
    uint public feeTake;

    uint256 public orderNonce;

    mapping (address => mapping (address => uint)) public tokens; //mapping of token addresses to mapping of account balances (token=0 means Ether)
    mapping (address => mapping (bytes32 => bool)) public orders;
    mapping (address => mapping (bytes32 => uint)) public orderFills; //mapping of user accounts to mapping of order hashes to uints (amount of order that has been filled)

    event Order(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user);
    event Cancel(address tokenGet, uint amountGet, address tokenGive, uint amountGive, uint expires, uint nonce, address user, uint8 v, bytes32 r, bytes32 s);
    event Trade(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address get, address give, uint nonce, uint fill);
    event Deposit(address token, address user, uint amount, uint balance);
    event Withdraw(address token, address user, uint amount, uint balance);

    function () public payable {
        revert("Fallback not available");
    }
    
    function setAdmin(address newAdmin) public {
        admin = newAdmin;
    }

    function setFeeAccount(address newFeeAccount) public {
        feeAccount = newFeeAccount;
    }

    function setAccountLevelsAddr(address newAccountLevelsAddr) public {
        accountLevelsAddr = newAccountLevelsAddr;
    }

    function depositKlay() public payable {
        tokens[0][msg.sender] = tokens[0][msg.sender].add(msg.value);
        emit Deposit(0, msg.sender, msg.value, tokens[0][msg.sender]);
    }

    function withdrawKlay(uint256 amount) public {
        require (tokens[0][msg.sender] >= amount, "Can't withdraw exceeding amount");
        tokens[0][msg.sender] = tokens[0][msg.sender].sub(amount);
        msg.sender.transfer(amount);
        emit Withdraw(0, msg.sender, amount, tokens[0][msg.sender]);
    }

    function depositToken(address token, uint256 amount) public {
        require (token != address(0));
        require (ERC20(token).transferFrom(msg.sender, this, amount));
        tokens[token][msg.sender] = tokens[token][msg.sender].add(amount);
        emit Deposit(token, msg.sender, amount, tokens[token][msg.sender]);
    }

    function withdrawToken(address token, uint256 amount) public {
        require (token != address(0));
        require (tokens[token][msg.sender] >= amount, "Can't withdraw exceeding amount");
        require (ERC20(token).transfer(msg.sender, amount));
        tokens[token][msg.sender] = tokens[token][msg.sender].sub(amount);
        emit Withdraw(token, msg.sender, amount, tokens[token][msg.sender]);
    }

    function order(address tokenGet, uint256 amountGet, address tokenGive, uint256 expires, uint256 amountGive) public {
        orderNonce += 1;
        bytes32 hashData = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, orderNonce));
        orders[msg.sender][hashData] = true;
        emit Order(tokenGet, amountGet, tokenGive, amountGive, expires, orderNonce, msg.sender);
    }

    function trade(address tokenGet, uint256 amountGet, address tokenGive, uint256 expires, uint256 amountGive, uint256 nonce, address user, uint amount) public {
        bytes32 hashData = keccak256(abi.encodePacked(this, tokenGet, amountGet, tokenGive, amountGive, nonce));
        require(orders[user][hashData] == true);
        require(block.number <= expires);
        require(orderFills[user][hashData].add(amount) <= amountGet);

        tradeBalances(tokenGet, amountGet, tokenGive, amountGive, user, amount);
        orderFills[user][hashData] = orderFills[user][hashData].add(amount);

        emit Trade(tokenGet, amount, tokenGive, amountGive * amount / amountGet, user, msg.sender, nonce, orderFills[user][hashData]);
    }

    function tradeBalances(address tokenGet, uint amountGet, address tokenGive, uint amountGive, address user, uint amount) private {
        uint feeMakeXfer = amount.mul(feeMake) / (1 ether);
        uint feeTakeXfer = amount.mul(feeTake) / (1 ether);
        uint feeRebateXfer = 0;


        // if (accountLevelsAddr != 0x0) {
        //     uint accountLevel = AccountLevels(accountLevelsAddr).accountLevel(user);
        //     if (accountLevel==1) feeRebateXfer = amount.mul(feeRebate) / (1 ether);
        //     if (accountLevel==2) feeRebateXfer = feeTakeXfer;
        // }

        tokens[tokenGet][msg.sender] = tokens[tokenGet][msg.sender].sub(amount.add(feeTakeXfer));

        tokens[tokenGet][user] = tokens[tokenGet][user].add(amount.add(feeRebateXfer).sub(feeMakeXfer));

        tokens[tokenGet][feeAccount] = tokens[tokenGet][feeAccount].add(feeMakeXfer.add(feeTakeXfer).sub(feeRebateXfer));

        tokens[tokenGive][user] = tokens[tokenGive][user].sub(amountGive.mul(amount) / amountGet);

        tokens[tokenGive][msg.sender] = tokens[tokenGive][msg.sender].add(amountGive.mul(amount) / amountGet);
    }
}
