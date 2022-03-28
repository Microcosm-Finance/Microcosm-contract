// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MIC is ERC20, Ownable {
    using SafeMath for uint256;

    constructor() ERC20("MIC", "MIC") {
        super._mint(msg.sender, 21000 * 1e18);
        maxHoldBalancelimit = 100 * 1e18;
    }

    uint256 public maxHoldBalancelimit;
    mapping(address => bool) public whitelist;

    function setWhitelist(address _addr, bool _bool) public onlyOwner {
        whitelist[_addr] = _bool;
    }

    function setMaxHoldBalancelimit(uint256 _maxHoldBalancelimit) public onlyOwner {
        maxHoldBalancelimit = _maxHoldBalancelimit;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20) {
        require(maxHoldBalancelimit == 0 || whitelist[to] || super.balanceOf(to) + amount <= maxHoldBalancelimit, "Recipient is over MaxHoldBalancelimit");
    }
}
