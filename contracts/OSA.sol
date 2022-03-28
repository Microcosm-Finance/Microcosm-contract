// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract OSA is ERC20, Ownable {
    using SafeMath for uint256;

    constructor() ERC20("OSA", "OSA") {
        _mint(msg.sender, 100_0000 * 1e18);
    }

    address public LPChefAddress;

    function setLPChefAddress(address _addr) public onlyOwner {
        require(LPChefAddress != _addr, "LPChefAddress is already this value");
        LPChefAddress = _addr;
    }

    function mintByChef(address account, uint256 amount) public {
        require(msg.sender == LPChefAddress, "Only LPChefAddress call");
        require(totalSupply() + amount <= 1000_0000 * 1e18, "TotalSupply is exceed");
        super._mint(account, amount);
    }
}
