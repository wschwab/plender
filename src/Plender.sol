// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "@rari-capital/solmate/src/tokens/ERC721.sol";
import "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

// open questions/thoughts:
//   * do we need a status enum, or can the status be inferred on the fly?
//   * maybe all we need is a nested mapping of contract address => tokenId => loan struct
//   * the above would likely be hard on on-chain svg rendering
//   * the debt should be owed to the owner of the NFT, making the plender NFT a lien
//     that way, if the NFT is transferred, the funds are owed to the new owner, and also
//     only the new owner has liquidation rights
//   * currently not every tokenId will necessarily have an NFT, only the accepted offers will
//   * currently assuming loans are always ERC20, but should we?
//   * I go back and forth, but am leaning towards being optimistic on ownership at offer generation
//     meaning not checking that proposer actually posseses the assets and/or escrowing, which
//     makes offering cheap and accepting more expensive (comprative to offering), also UIs
//     can check for ownership and filter
//   * the underlying NFTs should have 4494 Permits (ofc)
//   * in case you're reading this, this is not meant to be efficient yet, still brainstorming

interface ERC1155 {
  function balanceOf(address owner, uint256 id) external view returns(uint256);
  function safeTransferFrom(address from, address to, uint256 id, uint256 amount) external;
}

enum Status {
  NULL,
  CREATED,
  ACCEPTED,
  RESOLVED
}

enum CollateralType {
  NULL,
  ERC20,
  ERC721,
  ERC1155
}

enum OfferType {
  COLLATERAL,
  LOAN
}

// maybe stick them in an array where index = tokenId
struct Loan {
  // address of the collateral's original owner
  address borrower;
  // address of the collateral
  address contractAddr;
  // tokenId of collateral, 0 if ERC20
  uint256 tokenId;
  // amount of collateral, 0 if ERC721
  uint256 amount;
  // asset lender
  address lender;
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
error OfferDoesNotExist();
error TransferFailed();
error OfferAlreadyPaidBack();
error ThisShouldNotHappen();

contract Plender is ERC721 {
  using SafeTransferLib for ERC20;

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
  event CollateralOffer();
  event LoanOffer();
  event OfferAccepeted();
  event PaidBack();
  event Liquidated();
  event TokenAdded(address token, uint8 ttype);

  constructor() ERC721("Plender", "PLNDR") {}

  function tokenURI(uint256 tokenId) public view override returns(string memory) {
    // offers are only minted as an NFT once accepted
    if(!offers[tokenId].accepted) revert TokenIdDoesNotExist();
    return "";
  }

  function getOfferStatus(offerId) public view returns(Status) {
    if(offerId > offers.length) revert OfferDoesNotExist();
    try this.tokenURI(offerId) returns (string memory) {
      return Status.Accepted;
    } catch  {
      if(offers[offerId].accepted) return Status.RESOLVED;
      if(offers[offerId].deadline != 0) return Status.CREATED;
      // I don't think this should ever be triggered, but just in case
      return Status.NULL;
    }
  }

  /// @notice make offer for collateral or loan
  /// @dev currently written to only accept recognized assets (tokenTypes)
  /// @param offerType if offer is from collateral owner (borrower) or lender
  /// @param collateralContract the contract of the NFT or ERC20 for collateral
  /// @param tokenId the index of the NFT, 0 for ERC20
  /// @param amount amount of asset offered, 0 for ERC721
  /// @param offerAsset the address of the asset being lent
  /// @param amountToLend amount of the asset being lent
  /// @param amountToPayBack full amount due at term
  /// @param deadline timestamp of deadline for loan
  /// @return index of the offer
  function makeOffer(
    OfferType offerType,
    address collateralContract,
    uint256 tokenId,
    uint256 amount,
    address offerAsset,
    uint256 amountToLend,
    uint256 amountToPayBack,
    uint256 deadline
  ) external returns(uint256) {
    // check that collateral is recognized
    CollateralType ttype = tokenTypes[collateralContract];
    if(ttype == CollateralType.NULL) revert TokenTypeNotSetOrUnrecognized();

    uint256 offerId = offers.length;

    // COLLATERAL OFFER
    if(offerType == OfferType.COLLATERAL) {
      // ownership check?

      offers[offerId] = Loan({
        borrower: msg.sender,
        contractAddr: collateralContract,
        tokenId: tokenId,
        amount: amount,
        lender: address(0),
        borrowingAsset: offerAsset,
        amountLent: amountToLend,
        amountToPayBack: amountToPayBack,
        deadline: deadline,
        accepted: false
      });
      // short hook?
      emit CollateralOffer();
    }
    // LOAN OFFER
    if(offerType == OfferType.LOAN) {
      offers[offerId] = Loan({
        borrower: address(0),
        contractAddr: collateralContract,
        tokenId: tokenId,
        amount: amount,
        lender: msg.sender,
        borrowingAsset: offerAsset,
        amountLent: amountToLend,
        amountToPayBack: amountToPayBack,
        deadline: deadline,
        accepted: false
      });
      // long hook?
      emit LoanOffer();
    }

    return offerId;
  }

  // TODO: reentrancy guard
  function acceptOffer(uint256 offerId) external returns(bool) {
    Loan memory offer = offers[offerId];
    // if offer originated from lender, we assume collateral owner is msg.sender
    if(offer.borrower == address(0)) {
      offers[offerId].borrower = msg.sender;
      offer.borrower =  msg.sender;

    // if offer originated from borrower, we assume lender is msg.sender
    } else if(offer.lender == address(0)) {
      offers[offerId].lender = msg.sender;
      offer.lender = msg.sender;

    } else {
      revert ThisShouldNotHappen();
    }
    offers[offerId].accepted == true;

    CollateralType ttype = tokenTypes[offer.contractAddr];
    // escrow collateral in this contract
    transferTrusted(
      ttype,
      offer.contractAddr,
      offer.tokenId,
      offer.amount,
      offer.borrower,
      address(this)
    );
    // transfer loan to borrower
    transferTrusted(
      CollateralType.ERC20,
      offer.borrowingAsset,
      0,
      offer.amountLent,
      offer.lender,
      offer.borrower
    );
    // maybe there should be a hook for shorting/longing NFTs here
    // longing - can offer alternative collateral to NFT, if defaults, gets NFT?
    //   should be cheaper than buying the actual offer NFT? not sure
    //   does this only work if the lender is accepting?
    _mint(offer.lender, offerId);
    emit OfferAccepeted();
    return true;
  }

  // for paying back the loan and getting the collateral back
  function payback(uint256 offerId) external payable returns(bool) {
    Loan memory offer = offers[offerId];
    if(msg.sender != offer.borrower) revert Unauthorized();
    transferTrusted(
      CollateralType.ERC20,
      offer.borrowingAsset,
      0,
      offer.amountToPayBack,
      msg.sender,
      ownerOf(offerId);
    );

    // is burning the offer NFT enough to show it's paid back?
    _burn(offerId);

    // return NFT collateral to original owner
    transferTrusted(
      tokenTypes[offer.contractAddr],
      offer.contractAddr,
      offer.tokenId,
      offer.amountLent,
      address(this),
      msg.sender
    );

    // this probably needs some kind of event, tho maybe the burn Transfer is enough

    return true;
  }

  function liquidate(uint256 offerId) external returns(bool) {
    Loan memory offer = offers[offerId];
    if(offer.deadline > block.timestamp) revert Unauthorized();
    // need to check that loan was accepted so this can't be use to liquidate identical collateral
    // ie there's an unaccepted offer with 5 of a particular 1155 id as collateral
    // but someone else has put up that collateral in an accepted offer
    if(!offer.accepted) revert Unauthorized();
    // do we need to check if it's been paid back?
    // just in case, since we know it was accepted, we just need to check for the offer NFT
    tokenURI(offerId);

    // burn offer NFT (so it can't be collected twice)
    _burn(offerId);
    
    // send collateral to lender
    transferTrusted(
      tokenTypes[offer.contractAddr],
      offer.contractAddr,
      offer.tokenId,
      offer.amountLent,
      address(this),
      ownerOf(offerId)
    );

    return true;
  }

  function setTokenType(address token, uint8 ttype) external onlyCurators {
    if(ttype >= 4) revert InvalidTokenType();
    tokenTypes[token] == CollateralType(ttype);
    emit TokenAdded(token, ttype);
  }

  /// @dev transfers assets recognized in the tokenTypes mapping
  function transferTrusted(
    CollateralType ttype,
    address asset,
    uint256 tokenId,
    uint256 amount,
    address from,
    address destination
  ) internal {
    if(ttype == CollateralType.ERC20) {
      ERC20(asset).safeTransferFrom(
        from,
        destination,
        amount
      );
    } else if(ttype == CollateralType.ERC721) {
      ERC721(asset).safeTransferFrom(
        from,
        destination,
        tokenId
      );
      if(ERC721(asset).ownerOf(tokenId) != destination) revert TransferFailed();
    } else if(ttype == CollateralType.ERC1155) {
      uint256 initialBalance = ERC1155(asset).balanceOf(destination, tokenId);
      ERC1155(asset).safeTransferFrom(
        from,
        destination,
        tokenId,
        amount
      );
      if(ERC1155(asset).balanceOf(destination, tokenId) != initialBalance + amount) {
        revert TransferFailed();
      }
    }
  }

  // can debate putting in a 1363 or 4524 receiver for ERC20s

  function onERC721Received(
    address,
    address,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return this.onERC721Received.selector;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return this.onERC1155Received.selector;
  }

  // I don't think it should be receiving batches,
  // so I'll leave out batch 1155 receiver for now
}
