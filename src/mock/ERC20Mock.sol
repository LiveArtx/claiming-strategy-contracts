// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Token is ERC20 {
    constructor() ERC20("Mock Art Token", "ART") {}
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}