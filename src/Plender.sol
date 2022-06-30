// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@rari-capital/solmate/src/tokens/ERC721.sol";

// open questions/thoughts:
//   * do we need a status enum, or can the status be inferred on the fly?
//   * maybe all we need is a nested mapping of contract address => tokenId => loan struct
//   * the above would likely be hard on on-chain svg rendering
//   * the debt should be owed to the owner of the NFT, making the plender NFT a lien
//     that way, if the NFT is transferred, the funds are owed to the new owner, and also
//     only the new owner has liquidation rights

enum CollateralType {
  NULL,
  ERC20,
  ERC721,
  ERC1155
}

// maybe stick them in an array where index = tokenId
struct Loan {
  // address of the collateral's original owner
  address owner;
  // address of the collateral
  address contractAddr;
  // tokenId of collateral, 0 if ERC20
  uint256 tokenId;
  // amount of collateral, 0 if ERC721
  uint256 amount;
  // the asset being lent
  address borrowingAsset;
  // the amount being lent
  uint256 amountLent;
  // the amount to pay back
  uint256 amountToPayBack;
  // timestamp of deadline
  uint256 deadline;
  // if offer has been accepted
  bool accepted;
}

error Unauthorized();
error TokenTypeNotSetOrUnrecognized();
error InvalidTokenType();
error TokenIdDoesNotExist();

contract Plender is ERC721 {
  /// @notice whitlisted curators of token types
  mapping (address => bool) public curators;
  /// @notice curated list of token types of contracts
  mapping (address => CollateralType) public tokenTypes;
  /// @notice array of all offers, also used as tokenId
  Loan[] public offers;

  modifier onlyCurators() {
    if(!curators[msg.sender]) revert Unauthorized();
    _;
  }

  event Deposit();
  event Offer();
  event OfferAccepeted();
  event PaidBack();
  event Liquidated();
  event TokenAdded(address token, uint8 ttype);

  function tokenURI(uint256 tokenId) view override returns(string memory) {
    if(!offers[tokenId].accepted) revert TokenIdDoesNotExist();
  }

  function getTokenType(address token) view returns(CollateralType memory) {
    CollateralType ttype = tokenTypes[token];
    if(ttype == CollateralType.NULL) revert TokenTypeNotSetOrUnrecognized();
    return ttype;
  }

  /// @notice make offer for collateral
  /// @param collateralContract the contract of the NFT or ERC20 for collateral
  /// @param tokenId the index of the NFT, 0 for ERC20
  /// @param amount amount of asset offered, 0 for ERC721
  /// @param offerAsset the address of the asset being lent
  /// @param amountToLend amount of the asset being lent
  /// @param amountToPayBack full amount due at term
  /// @param deadline timestamp of deadline for loan
  /// @return index of the offer
  function makeOffer(
    address collateralContract,
    uint256 tokenId,
    uint256 amount,
    address offerAsset,
    uint256 amountToLend,
    uint256 amountToPayBack,
    uint256 deadline
  ) external returns(uint256) {}

  function acceptOffer(uint256 offerId) external returns(bool) {}

  // for paying back the loan and getting the collateral back
  function payback(uint256 offerId) external returns(bool) {}

  function liquidate(uint256 offerId) external returns(bool) {}

  function setTokenType(address token, uint8 ttype) onlyCurators {
    if(ttype >= type(CollateralType).max) revert InvalidTokenType();
    tokenTypes[token] == CollateralType(ttype);
    emit TokenAdded(token, ttype);
  }

  // can debate putting in a 1363 or 4524 receiver for ERC20s

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return ERC721TokenReceiver.onERC721Received.selector;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return ERC1155TokenReceiver.onERC1155Received.selector;
  }

  // I don't think it should be receiving batches,
  // so I'll leave out batch 1155 receiver for now
}
