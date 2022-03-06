// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./ICamelit.sol";
import "./IPool.sol";
import "./ITraits.sol";
import "./GOLD.sol";
contract Camelit is ICamelit, ERC721Enumerable, Ownable, Pausable {
  
  mapping (uint256 => uint256) private mintedAt;
  // mint price
  uint256 public constant MINT_PRICE = 0.015 ether;
  // max number of tokens that can be minted - 15000 in production
  uint256 public immutable MAX_TOKENS = 12500;
  // number of tokens that are minted with WETH - 50% of MAX_TOKENS
  uint256 public paidTokens = 5000;
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
  SingleTrait[11] traitProbabilities;  
// Addresses for withdraw function (dev = me)
  address public immutable devWallet = 0xb9110CE83EaF19ce6722e5970c2f2A25860b1d61;
  address public immutable ownerWallet = 0xC6Aaa1326b2A7111A196eEedD4B2e76e74e51a3D;
  address public immutable liquidityWallet = 0x4eaf95f633b6CCf22B38Ecb5bf9739748912F2D3;
  // reference to the Pool for choosing random Bandit
  IPool public pool;
  // reference to $GOLD for burning on mint
  GOLD public gold;
  // The WETH token contract (WETH9 on rinkeby testnet)
  IERC20 public WETH = IERC20(0xc778417E063141139Fce010982780140Aa0cD5Ab);
  // reference to Traits
  ITraits public traits;
  mapping(address => uint8) _minted;
  /** 
   * instantiates contract */

  constructor(address _gold, address _traits, uint256 _maxTokens) ERC721("Desert Clash", 'DesertGAME') { 
    gold = GOLD(_gold);
    traits = ITraits(_traits);
    MAX_TOKENS = _maxTokens;
    MAX_BANDITS = _maxTokens / 10;
    devWallet = _devWallet;
    ownerWallet = _ownerWallet;
    liquidityWallet = _liquidityWallet;
    // background
    traitProbabilities[0] = SingleTrait({pNothing: 0, numTraits: 9});
    // trees 
    traitProbabilities[1] = SingleTrait({pNothing: 0, numTraits: 6});
    // Necklace 
    traitProbabilities[2] = SingleTrait({pNothing: 8, numTraits: 2}); 
    // Headwear
    traitProbabilities[3] = SingleTrait({pNothing: 4, numTraits: 5});
    // Back Accessories 
    traitProbabilities[4] = SingleTrait({pNothing: 2, numTraits: 9});
    // Smoking Stuff 
    traitProbabilities[5] = SingleTrait({pNothing: 4, numTraits: 4});
    

    // Bandits
    // Background 
    traitProbabilities[6] = SingleTrait({pNothing: 0, numTraits: 9});
    // Eyes
    traitProbabilities[7] = SingleTrait({pNothing: 0, numTraits: 4});
    // Face Accessories
    traitProbabilities[8] = SingleTrait({pNothing: 10, numTraits: 5});
    // Weapons
    traitProbabilities[9] = SingleTrait({pNothing: 2, numTraits: 5});
    // Companions
    traitProbabilities[10] = SingleTrait({pNothing: 5, numTraits: 6});
  }
  /** EXTERNAL */

  /** 
   * mint a token - 90% Camel , 10% Bandit
   * The first 5000 cost WETH, the remaining cost $GOLD
   */
  function mint(uint256 amount, bool stake) external payable whenNotPaused {
    require(tx.origin == _msgSender(), "Only EOA");
    require(minted + amount <= MAX_TOKENS, "All tokens minted");
    require(amount > 0 && amount <= 10, "Invalid mint amount");
    require(_minted[msg.sender] + amount <= 40, "Can't mint more tokens");
    if (minted < paidTokens) {
      require(minted + amount <= paidTokens, "All tokens on-sale already sold");
      require(WETH.transferFrom(msg.sender, address(this), amount * MINT_PRICE), "CamelNFT: transferFrom failed");  
    } else {
      gold.burn(msg.sender, getPrice(amount, minted));
    }

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
      _minted[msg.sender]++;
      

    }
    
    if (stake) pool.addManyToPool(_msgSender(), tokenIds);
  }
  function ownerMint(uint256 amount) external onlyOwner {
    require(minted + amount <= 500);
    for (uint i = 0; i < amount; i++) {
      uint256 seed = random(minted);
      generate(minted, seed);   
      _safeMint(msg.sender, minted);
      minted++;
      }
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
   * @param seed portion of the 256 bit seed to remove trait correlation
   * @param traitType the trait type to select a trait for 
   * @return the ID of the randomly selected trait
   */
  function selectTrait(uint16 seed, uint8 traitType) internal view returns (uint8) {
    if(traitProbabilities[traitType].pNothing != 0) {
      if (uint8(seed) % traitProbabilities[traitType].pNothing != 0) {
          return(0);
      }
    }
    uint8 trait = (uint8(seed) % (traitProbabilities[traitType].numTraits - 1)) + 1;
    return trait;
  }

  /**
   * the first 5000 (ETH purchases) go to the minter
   * the remaining have a 10% chance to be given to a random staked bandit
   * @param seed a random value to select a recipient from
   * @return the address of the recipient (either the minter or the bandit's owner)
   */
  function selectRecipient(uint256 seed) internal view returns (address) {
    if (minted <= paidTokens || ((seed >> 245) % 10) != 0) return _msgSender(); // top 10 bits haven't been used
    address thief = pool.randomBanditOwner(seed >> 160); // 160 bits reserved for trait selection
    if (thief == address(0x0)) return _msgSender();
    return thief;
  }

  /**
   * selects the species and all of its traits based on the seed value
   * @param seed a pseudorandom 256 bit number to derive traits from
   * @return t -  a struct of randomly selected traits
   */
  function selectTraits(uint256 seed) internal returns (CamelBandit memory t) {    
    t.isCamel = (seed & 0xFFFF) % 10 != 0;
    if (!t.isCamel) {
      if(banditsMinted >= MAX_BANDITS) {
        t.isCamel = true;
      }
      else {
        banditsMinted++;
      }
    }
    uint8 shift = t.isCamel ? 0 : 6;

    seed >>= 16;
    t.background = selectTrait(uint16(seed), 0 + shift);
    seed >>= 16;
    t.eyesOrTree = selectTrait(uint16(seed), 1 + shift);
    seed >>= 16;
    t.faceOrNeck = selectTrait(uint16(seed), 2 + shift);
    seed >>= 16;
    t.weaponsOrHead = selectTrait(uint16(seed), 3 + shift);
    seed >>= 16;
    t.companionsOrBack = selectTrait(uint16(seed), 4 + shift);
    seed >>= 16;
    // yeah. 
    if(t.isCamel) {
    t.nullOrSmokingStuff = selectTrait(uint16(seed), 5 + shift);    }
    else{
      t.nullOrSmokingStuff = 0;
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
        s.background,
        s.eyesOrTree,
        s.faceOrNeck,
        s.weaponsOrHead,
        s.companionsOrBack,
        s.nullOrSmokingStuff
      )
    ));
  }

  /**
   * generates a pseudorandom number
   * @param seed a value ensure different outcomes for different sources in the same block
   * @return a pseudorandom value
   */
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

  function getTokenTraits(uint256 tokenId) external view override onlyIfNotJustMinted(tokenId) returns (CamelBandit memory) {
    return tokenTraits[tokenId];
  }

  function getPaidTokens() external view override returns (uint256) {
    return paidTokens;
  }

  /** ADMIN */

  /**
   * called after deployment so that the contract can get random wolf thieves
   * @param _pool the address of the Barn
   */
  function setPool(address _pool) external onlyOwner {
    pool = IPool(_pool);
  }

  /**
   * allows owner to withdraw funds from minting 
   */
  function withdraw() external onlyOwner {
    uint256 balance = WETH.balanceOf(address(this)); 
    WETH.transfer(liquidityWallet, (35*balance)/100);
    WETH.transfer(devWallet, (3*balance)/100);
    // Transfer whats left
    WETH.transfer(ownerWallet, WETH.balanceOf(address(this)));
  }

  /**
   * updates the number of tokens for sale
   */
  function setPaidTokens(uint256 _paidTokens) external onlyOwner {
    paidTokens = _paidTokens;
  }

  /**
   * enables owner to pause / unpause minting
   */
  function setPaused(bool _paused) external onlyOwner {
    if (_paused) _pause();
    else _unpause();
  }

  /** RENDER */

  function tokenURI(uint256 tokenId) public view override onlyIfNotJustMinted(tokenId) returns (string memory)  {
    require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
    return traits.tokenURI(tokenId);
  }
  function tokenMinted(uint256 id) internal {
     mintedAt[id]= block.number;
  }
  modifier onlyIfNotJustMinted(uint256) {
    require(msg.sender == address(pool) || mintedAt[tokenId] != block.number, "um... no");
    _;
  }
}

