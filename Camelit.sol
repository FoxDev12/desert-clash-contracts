// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./ICamelit.sol";
import "./IPool.sol";
import "./ITraits.sol";
import "./GOLD.sol";
// @NOTE Look more deeply into the whole trait mechanism 
contract Camelit is ICamelit, ERC721Enumerable, Ownable, Pausable {

  // mint price
  uint256 public constant MINT_PRICE = 0.03 ether;
  // max number of tokens that can be minted - 15000 in production
  uint256 public immutable MAX_TOKENS;
  // number of tokens that are minted with WETH - 50% of MAX_TOKENS
  uint256 public immutable PAID_TOKENS;
  // number of tokens have been minted so far
  uint16 public minted;
  uint256 public banditsMinted;
  uint256 public immutable MAX_BANDITS;
  // mapping from tokenId to a struct containing the token's traits
  mapping(uint256 => CamelBandit) public tokenTraits;
  // mapping from hashed(tokenTrait) to the tokenId it's associated with
  // used to ensure there are no duplicates
  mapping(uint256 => uint256) public existingCombinations;
  struct SingleTrait {
      uint8 pNothing;
      uint8 numTraits;
    }
  SingleTrait[] traitsProbabilities;  


  // reference to the Pool for choosing random Bandit
  IPool public pool;
  // reference to $GOLD for burning on mint
  GOLD public gold;
  // reference to Traits
  ITraits public traits;
  // NOTE well i like code that i can understand, upon reading about AJ Walkers alias algorithm, it sounds absolutely great, but im stupid so i'll do without x) 
  /** 
   * instantiates contract and rarity tables
   */

  constructor(address _gold, address _traits, uint256 _maxTokens) ERC721("Desert Clash Game", 'DesertGAME') { 
    gold = GOLD(_gold);
    traits = ITraits(_traits);
    MAX_TOKENS = _maxTokens;
    PAID_TOKENS = _maxTokens / 2;
    MAX_BANDITS = _maxTokens / 10;
    // Rewriting gen algo TODO : we only have 2 cases : all with same rarities / Nothing or all with same rarities, probably only store p(nothing) and the number of traits for each trait. 

    // background
    traitProbabilities[0] = (0,9);
    // trees
    traitProbabilities[1] = (0,6);
    // Necklace
    traitProbabilities[2] = (8,2); // 1/8 chance of something
    // Headwear
    traitProbabilities[3] = (4,5);
    // Back Accessories
    traitProbabilities[4] = (2,9);
    // Smoking Stuff
    traitProbabilities[5] = (4,4);
    

    // Bandits
    // Background
    traitProbabilities[6] = (0,9);
    // Eyes
    traitProbabilities[7] = (0,4);
    // Face Accessories
    traitProbabilities[8] = (10,5);
    // Weapons
    traitProbabilities[9] = (2,5);
    // Companions
    traitProbabilities[10] = (5,6);
    // Have to add in a whole special case for 11 


  /** EXTERNAL */

  /** 
   * mint a token - 90% Camel , 10% Bandit
   * The first 50% are free to claim (no), the remaining cost $GOLD
   */
  // NOTE price logic now ok  TODO look into generation
  // TODO Make gold fully ERC20 if not already 
  function mint(uint256 amount, bool stake) external payable whenNotPaused {
    require(tx.origin == _msgSender(), "Only EOA");
    require(minted + amount <= MAX_TOKENS, "All tokens minted");
    require(amount > 0 && amount <= 5, "Invalid mint amount");
    if (minted < PAID_TOKENS) {
      require(minted + amount <= PAID_TOKENS, "All tokens on-sale already sold");
      require(WETH.transferFrom(msg.sender, address(this), amount * MINT_PRICE), "CamelNFT: transferFrom failed");  
    } else {
      require(gold.burn(msg.sender, getPrice(amount, firstTokenID)), "CamelNFT: $GOLD burn failed");
    }

    uint256 totalGold = 0;
    uint16[] memory tokenIds = stake ? new uint16[](amount) : new uint16[](0);
    uint256 seed;
    for (uint i = 0; i < amount; i++) {
      minted++;
      seed = random(minted);
      generate(minted, seed);
      address recipient = selectRecipient(seed);
      if (!stake || recipient != _msgSender()) {
        _safeMint(recipient, minted);
      } else {
        _safeMint(address(pool), minted);
        tokenIds[i] = minted;
      }
    }
    
    if (totalGold > 0) gold.burn(_msgSender(), totalGold);
    if (stake) pool.addManyToPool(_msgSender(), tokenIds);
  }


  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public virtual override {
    // Hardcode the Pool's approval so that users don't have to waste gas approving // NOTE I dont like this that much
    if (_msgSender() != address(pool)) {
      require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
    }
    _transfer(from, to, tokenId);
  }

  /** INTERNAL */
  /**
  * returns the price in $GOLD of 'amount' of tokens
  * @param amount the amount of tokens to be minted
  * @param firstTokenID the ID of the first token to be minted
  * @return the required amount to be taken from the minter's address
  * @dev a 'for' loop is okay since we're in memory, and it won't loop more than 5 times anyways
   */
  // @NOTE more efficient than the previous implementation, and cleaner imo 

  function getPrice(uint256 amount, uint256 firstTokenID) internal pure returns(uint256) {
    uint256 totalPrice;
    for(uint i; i < amount; i++) {
      totalPrice += (((firstTokenID + i - 5000) / 200) * 20) + 150;
    }
    return totalPrice;
  }
  /**
   * generates traits for a specific token, checking to make sure it's unique
   * @param tokenId the id of the token to generate traits for
   * @param seed a pseudorandom 256 bit number to derive traits from
   * @return t - a struct of traits for the given token ID
   */
  function generate(uint256 tokenId, uint256 seed) internal returns (CamelBandit memory t) {
    t = selectTraits(seed);
    if (existingCombinations[structToHash(t)] == 0) {
      tokenTraits[tokenId] = t;
      existingCombinations[structToHash(t)] = tokenId;
      return t;
    }
    return generate(tokenId, random(seed));
  }

  /**
   * uses A.J. Walker's Alias algorithm for O(1) rarity table lookup
   * ensuring O(1) instead of O(n) reduces mint cost by more than 50%
   * probability & alias tables are generated off-chain beforehand
   * @param seed portion of the 256 bit seed to remove trait correlation
   * @param traitType the trait type to select a trait for 
   * @return the ID of the randomly selected trait
   */
  function selectTrait(uint16 seed, uint8 traitType) internal view returns (uint8) {
    uint8 trait = uint8(seed) % uint8(rarities[traitType].length);
    if (seed >> 8 < rarities[traitType][trait]) return trait;
    return aliases[traitType][trait];
  }

  /**
   * the first 50% (ETH purchases) go to the minter
   * the remaining 50% have a 10% chance to be given to a random staked wolf
   * @param seed a random value to select a recipient from
   * @return the address of the recipient (either the minter or the bandit's owner)
   */
  function selectRecipient(uint256 seed) internal view returns (address) {
    if (minted <= PAID_TOKENS || ((seed >> 245) % 10) != 0) return _msgSender(); // top 10 bits haven't been used
    address thief = pool.randomWolfOwner(seed >> 160); // 160 bits reserved for trait selection
    if (thief == address(0x0)) return _msgSender();
    return thief;
  }

  /**
   * selects the species and all of its traits based on the seed value
   * @param seed a pseudorandom 256 bit number to derive traits from
   * @return t -  a struct of randomly selected traits
   */
  function selectTraits(uint256 seed) internal view returns (CamelBandit memory t) {    
    // 1/10, doesnt enforce that theres actually 10% bandits though, hardcode this.  
    t.isCamel = (seed & 0xFFFF) % 10 != 0;
    // NOTE Mitigation
    if (!t.isCamel) {
      // NOTE superior or equal, even if it should never happen anyways)
      if(banditsMinted >= MAX_BANDITS) {
        t.isCamel = true;
      }
      else {
        banditsMinted++;
      }
    }
    uint8 shift = t.isCamel ? 0 : 6;
    // NOTE
    /**
    *
    * Select 2 bytes from the seed 
    * (sequentially, so 1st 2 bytes are used to generate the 1st trait etc) 
    * (given that the seed is 32 bytes and we generate 7 traits, some of the seed is actually never used )
    * logical AND them with 0xFFFF, which um... does nothing? Why? Is it supposed to make the code look scarier?
    * (Wastes gas anyways, so cut that out)
    * 
    */  
    // TLDR this code is awful 
    seed >>= 16;
    t.fur = selectTrait(uint16(seed), 0 + shift);
    seed >>= 16;
    t.head = selectTrait(uint16(seed), 1 + shift);
    seed >>= 16;
    t.ears = selectTrait(uint16(seed), 2 + shift);
    seed >>= 16;
    t.eyes = selectTrait(uint16(seed), 3 + shift);
    seed >>= 16;
    t.nose = selectTrait(uint16(seed), 4 + shift);
    seed >>= 16;
    // yeah. 
    if(t.isCamel) {
    t.mouth = selectTrait(uint16(seed), 5 + shift);    }
    else{
      t.mouth = 0;
    } 
  }

  /**
   * converts a struct to a 256 bit hash to check for uniqueness
   * @param s the struct to pack into a hash
   * @return the 256 bit hash of the struct
   */
  function structToHash(CamelBandit memory s) internal pure returns (uint256) {
    return uint256(keccak256(
      abi.encodePacked(
        s.isCamel,
        s.fur,
        s.head,
        s.eyes,
        s.nose,
        s.mouth,
        s.ears,
        s.neck,
        s.body,
        s.legs,
        s.feet
      )
    ));
  }

  /**
   * generates a pseudorandom number
   * @param seed a value ensure different outcomes for different sources in the same block
   * @return a pseudorandom value
   */
   // NOTE somewhat vulnerable, a lil better now, 
   // TODO which chain? ask owners. block.coinbase is a bad randomness factor on chains with MEV and on ultra restricted chains like the bsc
  function random(uint256 seed) internal view returns (uint256) {
    return uint256(keccak256(abi.encodePacked(
      tx.origin,
      blockhash(block.number - 1),
      block.timestamp,
      block.coinbase,

      seed
    )));
  }

  /** READ */

  function getTokenTraits(uint256 tokenId) external view override returns (CamelBandit memory) {
    return tokenTraits[tokenId];
  }

  function getPaidTokens() external view override returns (uint256) {
    return PAID_TOKENS;
  }

  /** ADMIN */

  /**
   * called after deployment so that the contract can get random wolf thieves
   * @param _pool the address of the Barn
   */
  function setBarn(address _pool) external onlyOwner {
    pool = IPool(_pool);
  }

  /**
   * allows owner to withdraw funds from minting 
   */
  // @NOTE talk with owners about hardcoding equity 
  function withdraw() external onlyOwner {
    payable(owner()).transfer(address(this).balance);
  }

  /**
   * updates the number of tokens for sale
   */
  function setPaidTokens(uint256 _paidTokens) external onlyOwner {
    PAID_TOKENS = _paidTokens;
  }

  /**
   * enables owner to pause / unpause minting
   */
  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }

  /** RENDER */

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
    return traits.tokenURI(tokenId);
  }
}