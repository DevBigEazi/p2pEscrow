// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

    enum Trade {
        NONE,
        CANCELLED,
        ACTIVE,
        DISPUTED,
        COMPLETED
    }

    enum Delivery {
        UNSHIPPED,
        SHIPPED,
        DELIVERED
    }

contract P2PEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private owner;
    address private escrowAcc;
    uint256 public escrowBal;

    uint256 public tradeCount;

    uint128 constant ESCROWFEE_PERCENTAGE = 250; // 2.5% of the product price
    uint256 constant SCALING_FACTOR = 10000;

    struct Product {
        string name;
        uint price;
    }

    struct TradeInfo {
        uint256 tradeId;
        address seller;
        address buyer;
        Product[] products;
        uint256 escrowFee;
        uint256 logisticFee;
        uint256 totalTradingCost;
        Trade tradeStatus;
        Delivery deliveryStatus;
    }

    mapping(uint256 => TradeInfo) private trade;

    constructor() payable {
        owner = msg.sender;
        escrowAcc = address(0);
    }

    modifier preventAddressZero() {
        require(msg.sender != address(0), "Address zero not allowed");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender != address(0), "Address zero not allowed");
        require(msg.sender == owner, "No access");
        _;
    }

    event TradeActive(
        address indexed buyer,
        address indexed seller,
        uint256 escrowFee,
        uint256 totalTradingCost
    );
    event TradeCompleted(address indexed buyer, address indexed seller);
    event Transfer(
        address indexed buyer,
        address indexed spender,
        uint256 amount
    );
    event Action(string actionType, address indexed executor);

    function openTrade(
        IERC20 _token,
        address _seller,
        string[] memory _products,
        uint256[] memory _productPrices,
        uint256 _logisticFee
    ) external preventAddressZero nonReentrant returns (bool success_) {
        require(msg.sender == _seller, "Seller can not buy their product");
        require(_products.length > 0, "At least one product required");
        require(_products.length <= 5, "You can not trade more than 5 products in a trade");

        uint productTotalPrice = 0;
        for (uint i = 0; i < _productPrices.length; i++) {
            productTotalPrice += _productPrices[i];
        }

        require(
            productTotalPrice > 0,
            "Product toatal price cannot be zero ethers"
        );

        uint256 tradeId = tradeCount++;

        TradeInfo memory tradeInfo = trade[tradeId];
        tradeInfo.tradeId = tradeId;
        tradeInfo.seller = _seller;
        tradeInfo.buyer = msg.sender;
        tradeInfo.tradeStatus = Trade.ACTIVE;

        for (uint i = 0; i < _products.length; i++) {
            trade[tradeId].products.push(
                Product(_products[i], _productPrices[i])
            );
        }

        uint256 escrowFee = calcEscrowFee(productTotalPrice);

        tradeInfo.escrowFee = escrowFee;
        tradeInfo.logisticFee = _logisticFee;

        uint256 totalTradingCost = productTotalPrice + _logisticFee + escrowFee;

        tradeInfo.totalTradingCost = totalTradingCost;

        require(
            _token.balanceOf(msg.sender) >= totalTradingCost,
            "Insufficient balance"
        );

        require(
            _token.allowance(msg.sender, escrowAcc) >= totalTradingCost,
            "Amount is not allowed"
        );

        // Transfer _token to the seller
        _token.safeTransferFrom(msg.sender, escrowAcc, totalTradingCost);

        // update escrow balance
        escrowBal += totalTradingCost;

        emit Transfer(msg.sender, escrowAcc, totalTradingCost);
        emit TradeActive(msg.sender, _seller, escrowFee, totalTradingCost);

        return success_;
    }

    function shipProducts(
        uint256 _tradeId
    ) external preventAddressZero returns (bool success_) {
        TradeInfo memory tradeInfo = trade[_tradeId];

        address seller = tradeInfo.seller;

        require(msg.sender == seller, "Unauthorized!");

        require(
            tradeInfo.tradeStatus == Trade.ACTIVE,
            "Trade is not active or does not exist"
        );

        tradeInfo.deliveryStatus = Delivery.SHIPPED;

        emit Action("Product Shipped", seller);

        return success_;
    }

    function completeTrade(
        IERC20 _token,
        uint256 _tradeId
    ) external preventAddressZero nonReentrant returns (bool success_) {
        TradeInfo memory tradeInfo = trade[_tradeId];

        address buyer = tradeInfo.buyer;
        address seller = tradeInfo.seller;
        tradeInfo.tradeStatus = Trade.COMPLETED;

        require(msg.sender == buyer, "Unauthorized!");

        tradeInfo.deliveryStatus = Delivery.DELIVERED;

        uint256 productTotalPrice = tradeInfo.totalTradingCost -
            tradeInfo.escrowFee -
            tradeInfo.logisticFee;

        require(
            _token.balanceOf(escrowAcc) >= tradeInfo.totalTradingCost,
            "Insufficient balance"
        );

        require(
            tradeInfo.deliveryStatus == Delivery.SHIPPED,
            "This product has not being sent for delivery"
        );

        _token.safeTransfer(seller, productTotalPrice);
        _token.safeTransfer(owner, tradeInfo.escrowFee + tradeInfo.logisticFee); // transfer escrow fee and logistic fee to the owner

        emit TradeCompleted(buyer, seller);

        return success_;
    }

    //HELPER
    function calcEscrowFee(
        uint256 _productPrice
    ) private pure returns (uint256) {
        return (_productPrice * ESCROWFEE_PERCENTAGE) / SCALING_FACTOR;
    }
}

