// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IOSAToken {
    function mintByChef(address account, uint256 amount) external;
}

contract LPChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor() {
        _creator = msg.sender;
        awardPerSecond = 0.05 * 1e18;
        rewardWithdrawSwitch = true;
        osaToken = 0x4E4e45Ed7eF3DFBCa324f0D09854188C79aA890e;
        micUsdtPair = 0xB6539EAFA70e162Fdbff8655B62E31839e086666;
        usdtToken = 0x426554d98c6a35098f68A7C87f7FF605D2121a7e;
        micToken = 0x5f9C8287a59519d9D2d14807c4c96a72833E0019;
    }

    address _creator;
    bool public rewardWithdrawSwitch;
    address public osaToken;
    address public micToken;
    address public usdtToken;
    address public micUsdtPair;
    uint256 public startTimestamp = block.timestamp;
    uint256 public endTimestamp = block.timestamp + 30 * 24 * 3600;
    uint256 public userDepositInterval;
    mapping(address => uint256) public lastDepositTimestamp;

    function setRewardWithdrawSwitch(bool _bool) public onlyOwner {
        rewardWithdrawSwitch = _bool;
    }

    function setUserDepositInterval(uint256 _userDepositInterval) public onlyOwner {
        userDepositInterval = _userDepositInterval;
    }

    function initToken(
        address _osaToken,
        address _micToken,
        address _usdtToken,
        address _micUsdtPair
    ) public onlyOwner {
        osaToken = _osaToken;
        micToken = _micToken;
        usdtToken = _usdtToken;
        micUsdtPair = _micUsdtPair;
    }

    function setStartTimestamp(uint256 _startTimestamp) public onlyOwner {
        startTimestamp = _startTimestamp;
    }

    function setEndTimestamp(uint256 _endTimestamp) public onlyOwner {
        endTimestamp = _endTimestamp;
    }

    mapping(address => address) public parentAddress;
    mapping(address => address[]) public childrenAddress;

    function setParentAddress(address _addr) public {
        require(_addr != msg.sender, "ParentAddress can not set to youself");
        require(parentAddress[msg.sender] == address(0), "ParentAddress is exist");
        require(parentAddress[_addr] != address(0) || _addr == _creator, "ParentAddress is not actived");
        parentAddress[msg.sender] = _addr;
        childrenAddress[_addr].push(msg.sender);
    }

    function getChildrenAddress(address _addr) public view returns (address[] memory) {
        return childrenAddress[_addr];
    }

    struct UserCurrentInfo {
        uint256 amount;
        uint256 amountLp;
        uint256 rewardDebt;
        uint256 totalAward;
    }
    struct UserDepositInfo {
        uint256 amount;
        uint256 amountLp;
        uint256 rewardDebt;
        uint256 totalAward;
        uint256 lockTimestampUtil;
        bool status;
    }
    struct PoolInfo {
        uint256 allocPoint;
        uint256 lockSecond;
        uint256 lastRewardTimestamp;
        uint256 accAwardPerShare;
        uint256 totalAmount;
    }

    uint256 public awardPerSecond;
    uint256 public totalAllocPoint = 0;
    PoolInfo[] public poolInfos;
    mapping(address => UserCurrentInfo) public userCurrentInfos;
    mapping(address => mapping(uint256 => UserDepositInfo[])) public userDepositInfos;
    mapping(address => uint256) public availableWithdrawBalance;

    function setAwardPerSecond(uint256 _awardPerSecond) public onlyOwner {
        awardPerSecond = _awardPerSecond;
    }

    function allPool() public view returns (PoolInfo[] memory) {
        return poolInfos;
    }

    function add(
        uint256 _allocPoint,
        uint256 _lockSecond,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfos.push(PoolInfo({allocPoint: _allocPoint, lockSecond: _lockSecond, lastRewardTimestamp: lastRewardTimestamp, accAwardPerShare: 0, totalAmount: 0}));
    }

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _lockSecond,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        require(_pid < poolInfos.length, "Pool id is not exist");
        totalAllocPoint = totalAllocPoint.sub(poolInfos[_pid].allocPoint).add(_allocPoint);
        poolInfos[_pid].allocPoint = _allocPoint;
        poolInfos[_pid].lockSecond = _lockSecond;
    }

    function massUpdatePools() public {
        uint256 length = poolInfos.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public returns (PoolInfo memory pool) {
        pool = poolInfos[_pid];
        if (block.timestamp > pool.lastRewardTimestamp) {
            uint256 timeSeconds;
            if (pool.totalAmount > 0) {
                if (block.timestamp > endTimestamp) {
                    timeSeconds = endTimestamp.sub(pool.lastRewardTimestamp);
                } else {
                    timeSeconds = block.timestamp.sub(pool.lastRewardTimestamp);
                }
                uint256 reward = timeSeconds.mul(awardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
                pool.accAwardPerShare = pool.accAwardPerShare.add(reward.mul(1e18).div(pool.totalAmount));
            }
            pool.lastRewardTimestamp = pool.lastRewardTimestamp.add(timeSeconds);
            poolInfos[_pid] = pool;
        }
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        require(parentAddress[msg.sender] != address(0), "Your are not actived");
        uint256 _micWorth = calcMicWorth(_amount);
        PoolInfo memory pool = updatePool(_pid);
        if (pool.lockSecond == 0) {
            userCurrentInfos[msg.sender].amount = userCurrentInfos[msg.sender].amount.add(_micWorth);
            userCurrentInfos[msg.sender].amountLp = userCurrentInfos[msg.sender].amountLp.add(_amount);
            userCurrentInfos[msg.sender].rewardDebt = userCurrentInfos[msg.sender].rewardDebt.add(_micWorth.mul(poolInfos[_pid].accAwardPerShare).div(1e18));
        } else {
            require(lastDepositTimestamp[msg.sender].add(userDepositInterval) <= block.timestamp, "Operation limit");
            userDepositInfos[msg.sender][_pid].push(
                UserDepositInfo({amount: _micWorth, amountLp: _amount, rewardDebt: _micWorth.mul(pool.accAwardPerShare).div(1e18), totalAward: 0, lockTimestampUtil: block.timestamp.add(pool.lockSecond), status: true})
            );
            lastDepositTimestamp[msg.sender] = block.timestamp;
        }
        IERC20(micUsdtPair).safeTransferFrom(address(msg.sender), address(this), _amount);
        pool.totalAmount = pool.totalAmount.add(_micWorth);
        poolInfos[_pid] = pool;
    }

    function withdraw(
        uint256 _pid,
        uint256 _amount,
        uint256 _index
    ) public {
        PoolInfo memory pool = updatePool(_pid);
        if (pool.lockSecond == 0) {
            require(userCurrentInfos[msg.sender].amountLp >= _amount, "Insufficient balance of currentAmount");
            uint256 withdrawRate = _amount.mul(1e18).div(userCurrentInfos[msg.sender].amountLp);
            uint256 withdrawUsdt = userCurrentInfos[msg.sender].amount.mul(withdrawRate).div(1e18);

            uint256 accumulatedAward = userCurrentInfos[msg.sender].amount.mul(pool.accAwardPerShare).div(1e18);
            uint256 _pending = accumulatedAward.sub(userCurrentInfos[msg.sender].rewardDebt);
            userCurrentInfos[msg.sender].rewardDebt = accumulatedAward.sub(withdrawUsdt.mul(pool.accAwardPerShare).div(1e18));
            userCurrentInfos[msg.sender].amount = userCurrentInfos[msg.sender].amount.sub(withdrawUsdt);
            userCurrentInfos[msg.sender].amountLp = userCurrentInfos[msg.sender].amountLp.sub(_amount);
            userCurrentInfos[msg.sender].totalAward = userCurrentInfos[msg.sender].totalAward.add(_pending);

            availableWithdrawBalance[msg.sender] = availableWithdrawBalance[msg.sender].add(_pending);
            IERC20(micUsdtPair).safeTransfer(msg.sender, _amount);
            pool.totalAmount = pool.totalAmount.sub(withdrawUsdt);
        } else {
            UserDepositInfo storage depositInfo = userDepositInfos[msg.sender][_pid][_index];
            require(depositInfo.status, "The deposit is withdraw");
            require(depositInfo.lockTimestampUtil <= block.timestamp, "The deposit is not unlock");
            require(depositInfo.amountLp == _amount, "You must withdraw all amount of deposit");
            depositInfo.status = false;
            uint256 accumulatedAward = depositInfo.amount.mul(pool.accAwardPerShare).div(1e18);
            depositInfo.totalAward = accumulatedAward.sub(depositInfo.rewardDebt);

            availableWithdrawBalance[msg.sender] = availableWithdrawBalance[msg.sender].add(depositInfo.totalAward);
            IERC20(micUsdtPair).safeTransfer(msg.sender, _amount);
            pool.totalAmount = pool.totalAmount.sub(depositInfo.amount);
        }

        poolInfos[_pid] = pool;
    }

    function harvest(uint256 _pid) public {
        require(rewardWithdrawSwitch, "Can not harvest now");
        PoolInfo memory pool = updatePool(_pid);
        if (pool.lockSecond == 0) {
            uint256 accumulatedAward = userCurrentInfos[msg.sender].amount.mul(pool.accAwardPerShare).div(1e18);
            uint256 _pending = accumulatedAward.sub(userCurrentInfos[msg.sender].rewardDebt);
            userCurrentInfos[msg.sender].rewardDebt = accumulatedAward;
            if (availableWithdrawBalance[msg.sender] > 0) {
                _pending = _pending.add(availableWithdrawBalance[msg.sender]);
                availableWithdrawBalance[msg.sender] = 0;
            }
            if (_pending != 0) {
                userCurrentInfos[msg.sender].totalAward = userCurrentInfos[msg.sender].totalAward.add(_pending);
                IOSAToken(osaToken).mintByChef(msg.sender, _pending);
            }
        } else {
            UserDepositInfo[] storage userDepositInfosPool = userDepositInfos[msg.sender][_pid];
            uint256 totalPedding = 0;
            uint256 accAwardPerShare = pool.accAwardPerShare;
            for (uint256 i = 0; i < userDepositInfosPool.length; i++) {
                if (!userDepositInfosPool[i].status) {
                    continue;
                }
                uint256 _pending = userDepositInfosPool[i].amount.mul(accAwardPerShare).div(1e18).sub(userDepositInfosPool[i].rewardDebt);
                userDepositInfosPool[i].rewardDebt = userDepositInfosPool[i].rewardDebt.add(_pending);
                userDepositInfosPool[i].totalAward = userDepositInfosPool[i].totalAward.add(_pending);
                totalPedding = totalPedding.add(_pending);
            }
            if (availableWithdrawBalance[msg.sender] > 0) {
                totalPedding = totalPedding.add(availableWithdrawBalance[msg.sender]);
                availableWithdrawBalance[msg.sender] = 0;
            }
            if (totalPedding != 0) {
                IOSAToken(osaToken).mintByChef(msg.sender, totalPedding);
            }
        }
    }

    function harvestBatch() public {
        require(rewardWithdrawSwitch, "Can not harvest now");
        massUpdatePools();
        uint256 totalPedding = 0;
        for (uint256 i = 0; i < poolInfos.length; i++) {
            if (poolInfos[i].lockSecond == 0) {
                uint256 accumulatedAward = userCurrentInfos[msg.sender].amount.mul(poolInfos[i].accAwardPerShare).div(1e18);
                uint256 _pending = accumulatedAward.sub(userCurrentInfos[msg.sender].rewardDebt);
                userCurrentInfos[msg.sender].rewardDebt = accumulatedAward;
                if (_pending != 0) {
                    userCurrentInfos[msg.sender].totalAward = userCurrentInfos[msg.sender].totalAward.add(_pending);
                    totalPedding = totalPedding.add(_pending);
                }
            } else {
                UserDepositInfo[] storage userDepositInfosPool = userDepositInfos[msg.sender][i];
                uint256 accAwardPerShare = poolInfos[i].accAwardPerShare;
                for (uint256 j = 0; j < userDepositInfosPool.length; j++) {
                    if (!userDepositInfosPool[j].status) {
                        continue;
                    }
                    uint256 _pending = userDepositInfosPool[j].amount.mul(accAwardPerShare).div(1e18).sub(userDepositInfosPool[j].rewardDebt);
                    userDepositInfosPool[j].rewardDebt = userDepositInfosPool[j].rewardDebt.add(_pending);
                    userDepositInfosPool[j].totalAward = userDepositInfosPool[j].totalAward.add(_pending);
                    totalPedding = totalPedding.add(_pending);
                }
            }
        }
        if (availableWithdrawBalance[msg.sender] > 0) {
            totalPedding = totalPedding.add(availableWithdrawBalance[msg.sender]);
            availableWithdrawBalance[msg.sender] = 0;
        }
        if (totalPedding != 0) {
            IOSAToken(osaToken).mintByChef(msg.sender, totalPedding);
        }
    }

    function pending(address _addr, uint256 _pid) external view returns (uint256) {
        uint256 accAwardPerShare = poolInfos[_pid].accAwardPerShare;
        uint256 lpSupply = poolInfos[_pid].totalAmount;
        if (poolInfos[_pid].lockSecond == 0) {
            if (block.timestamp > poolInfos[_pid].lastRewardTimestamp && lpSupply != 0) {
                uint256 timeSeconds = (block.timestamp > endTimestamp) ? endTimestamp.sub(poolInfos[_pid].lastRewardTimestamp) : block.timestamp.sub(poolInfos[_pid].lastRewardTimestamp);
                uint256 reward = timeSeconds.mul(awardPerSecond).mul(poolInfos[_pid].allocPoint).div(totalAllocPoint);
                accAwardPerShare = accAwardPerShare.add(reward.mul(1e18).div(lpSupply));
            }
            return uint256(userCurrentInfos[_addr].amount.mul(accAwardPerShare).div(1e18)).sub(userCurrentInfos[_addr].rewardDebt);
        } else {
            uint256 totalPeding = 0;
            UserDepositInfo[] memory userDepositInfosPool = userDepositInfos[_addr][_pid];
            for (uint256 i = 0; i < userDepositInfosPool.length; i++) {
                totalPeding = totalPeding.add(pendingDeposit(_addr, _pid, i));
            }
            return totalPeding;
        }
    }

    function pendingDeposit(
        address _addr,
        uint256 _pid,
        uint256 _index
    ) public view returns (uint256) {
        UserDepositInfo storage userDepositInfo = userDepositInfos[_addr][_pid][_index];
        if (!userDepositInfo.status) {
            return 0;
        }
        uint256 accAwardPerShare = poolInfos[_pid].accAwardPerShare;
        uint256 lpSupply = poolInfos[_pid].totalAmount;
        if (block.timestamp > poolInfos[_pid].lastRewardTimestamp && lpSupply != 0) {
            uint256 timeSeconds = (block.timestamp > endTimestamp) ? endTimestamp.sub(poolInfos[_pid].lastRewardTimestamp) : block.timestamp.sub(poolInfos[_pid].lastRewardTimestamp);
            uint256 reward = timeSeconds.mul(awardPerSecond).mul(poolInfos[_pid].allocPoint) / totalAllocPoint;
            accAwardPerShare = accAwardPerShare.add(reward.mul(1e18).div(lpSupply));
        }
        return uint256(userDepositInfo.amount.mul(accAwardPerShare).div(1e18)).sub(userDepositInfo.rewardDebt);
    }

    function calcMicWorth(uint256 lpAmount) public view returns (uint256) {
        uint256 usdtPairBalance = IERC20(usdtToken).balanceOf(micUsdtPair);
        uint256 totalSupply = IERC20(micUsdtPair).totalSupply();
        return lpAmount.mul(usdtPairBalance).div(totalSupply);
    }

    function childrenTotal(address _addr) public view returns (UserCurrentInfo memory currentTotal, UserDepositInfo memory depositTotal) {
        address[] memory children = childrenAddress[_addr];
        currentTotal = UserCurrentInfo({amount: 0, amountLp: 0, rewardDebt: 0, totalAward: 0});
        depositTotal = UserDepositInfo({amount: 0, amountLp: 0, rewardDebt: 0, totalAward: 0, lockTimestampUtil: 0, status: false});
        for (uint256 i = 0; i < children.length; i++) {
            currentTotal.amount += userCurrentInfos[children[i]].amount;
            currentTotal.amountLp = userCurrentInfos[children[i]].amountLp;
            currentTotal.rewardDebt = userCurrentInfos[children[i]].rewardDebt;
            currentTotal.totalAward = userCurrentInfos[children[i]].totalAward;
            UserDepositInfo memory depositSubTotal = userDepositTotal(children[i]);
            depositTotal.amount += depositSubTotal.amount;
            depositTotal.amountLp += depositSubTotal.amountLp;
            depositTotal.rewardDebt += depositSubTotal.rewardDebt;
            depositTotal.totalAward += depositSubTotal.totalAward;
        }
    }

    function userDepositPoolInfos(address _addr, uint256 _pid) public view returns (UserDepositInfo[] memory) {
        return userDepositInfos[_addr][_pid];
    }

    function userDepositTotal(address _addr) public view returns (UserDepositInfo memory depositTotal) {
        for (uint256 i = 0; i < poolInfos.length; i++) {
            UserDepositInfo[] memory depositsPool = userDepositInfos[_addr][i];
            for (uint256 j; j < depositsPool.length; j++) {
                if (depositsPool[j].status) {
                    depositTotal.amount += depositsPool[j].amount;
                    depositTotal.amountLp += depositsPool[j].amountLp;
                    depositTotal.rewardDebt += depositsPool[j].rewardDebt;
                    depositTotal.totalAward += depositsPool[j].totalAward;
                }
            }
        }
    }
}
