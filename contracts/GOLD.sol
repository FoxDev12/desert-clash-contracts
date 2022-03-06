// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
contract GOLD is ERC20, Ownable {
  // a mapping from an address to whether or not it can mint / burn
  mapping(address => bool) controllers;
  mapping(address => uint256) lastOriginUpdate;
  constructor() ERC20("GOLD", "GOLD") {
    controllers[msg.sender] = true;
   }

  /**
   * mints $GOLD to a recipient
   * @param to the recipient of the $GOLD
   * @param amount the amount of $GOLD to mint
   */
  function mint(address to, uint256 amount) external {
    require(controllers[msg.sender], "Only controllers can mint");
    _mint(to, amount);
  }

  /**
   * burns $GOLD from a holder
   * @param from the holder of the $GOLD
   * @param amount the amount of $GOLD to burn
   */
  function burn(address from, uint256 amount) external {
    require(controllers[msg.sender], "Only controllers can burn");
    _burn(from, amount);
  }
  function balanceOf(address owner) public view override onlyIfNoOriginAccess returns(uint256 balance) {
    require(lastOriginUpdate[owner] != block.number, "um... no");
    return(super.balanceOf(owner));
  } 
  /**
   * enables an address to mint / burn
   * @param controller the address to enable
   */
  function addController(address controller) external onlyOwner {
    controllers[controller] = true;
  }
  function transferFrom(address from, address to, uint256 amount) public override onlyIfNoOriginAccess returns(bool) {
        require(lastOriginUpdate[from] != block.number, "um... no");
        super.transferFrom(from, to, amount);
        return(true);
  }
  /**
   * disables an address from minting / burning
   * @param controller the address to disbale
   */
  function removeController(address controller) external onlyOwner {
    controllers[controller] = false;
  }
  /**
   * updates the last time origin balance was updated by the controllers
   */
  function updateOriginAccess() external {
    require(controllers[msg.sender]);
    lastOriginUpdate[tx.origin] = block.number;
  }
  modifier onlyIfNoOriginAccess() {
    require(lastOriginUpdate[tx.origin] != block.number, "um... no");
    _;
  }
}
