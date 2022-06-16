// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// open questions:
//   * do we need a status enum, or can the status be inferred on the fly?

enum CollateralType {
  ERC20,
  ERC721,
  ERC1155
}

// maybe store in an array
struct Collateral {
  address owner;
  address contractAddr;
  uint256 tokenId;
  CollateralType collateralType;
}

// maybe stick them in an array where index = tokenId
struct Loan {
  // the asset being put up as collateral
  uint256 collateralId;
  // the asset being lent
  address borrowingAsset;
  // the amount being lent
  uint256 amountLent;
  // the amount to pay back
  uint256 amountToPayBack;
  // timestamp of deadline
  uint256 deadline;
}

contract Plender {
  uint256 collateralCounter;
  uint256 tokenIdCounter;

  function depositCollateral(
    address collateralContract,
    uint256 tokenId,
    CollateralType collateralType
    ) external returns(uint256) {}

  function makeOffer(
    address offerAsset,
    uint256 amountToLend,
    uint256 amountToPayBack,
    uint256 deadline
  ) external returns(uint256) {}

  function acceptOffer(uint256 offerId) external returns(bool) {}

  function payback(uint256 offerId) external returns(bool) {}

  function liquidate(uint256 offerId) external returns(bool) {}

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
