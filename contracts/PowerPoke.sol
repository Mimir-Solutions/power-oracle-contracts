// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/upgrades-core/contracts/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IPowerOracle.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IEACAggregatorProxy.sol";
import "./utils/Ownable.sol";
import "./utils/Pausable.sol";
import "./PowerPokeStaking.sol";

contract PowerPoke is Ownable, Initializable, ReentrancyGuard {
  using SafeMath for uint256;

  uint256 public constant HUNDRED_PCT = 100 ether;
  uint256 public constant HUNDRED_K = 100_000;

  struct Client {
    bool active;
    bool canSlash;
    address owner;
    uint256 credit;
    uint256 minReportInterval;
    uint256 maxReportInterval;
    uint256 slasherHeartbeat;
    uint256 gasPriceLimit;
    uint256 pokeBonus;
    uint256 slasherHeartbeatBonus;
    uint256 minPokerDeposit;
    uint256 minSlasherDeposit;
  }

  event RewardUser(
    address indexed client,
    uint256 indexed userId,
    bool indexed rewardInETH,
    uint256 amount,
    uint256 bonus,
    uint256 compensatedInETH,
    uint256 deposit,
    uint256 ethPrice,
    uint256 cvpPrice,
    uint256 calculatedReward
  );

  struct PokeRewardOptions {
    address to;
    bool rewardInEth;
    // bool useChiToken;
  }

  event SetReportIntervals(address indexed client, uint256 minReportInterval, uint256 maxReportInterval);

  event SetGasPriceLimit(address indexed client, uint256 gasPriceLimit);

  event SetSlasherHeartbeat(address indexed client, uint256 slasherHeartbeat);

  event SetBonuses(address indexed client, uint256 pokeBonus, uint256 slasherHeartbeatBonus);

  event SetMinimalDeposits(address indexed client, uint256 minPokerDeposit, uint256 minSlasherDeposit);

  event WithdrawRewards(uint256 indexed userId, address indexed to, uint256 amount);

  event AddCredit(address indexed client, uint256 amount);

  event WithdrawCredit(address indexed client, address indexed to, uint256 amount);

  address public immutable WETH_TOKEN;

  IERC20 public immutable CVP_TOKEN;

  IEACAggregatorProxy public immutable FAST_GAS_ORACLE;

  PowerPokeStaking public immutable POWER_POKE_STAKING;

  IUniswapV2Router02 public immutable UNISWAP_ROUTER;

  IPowerOracle public oracle;

  uint256 public totalCredits;

  mapping(uint256 => uint256) public rewards;

  mapping(address => Client) public clients;

  modifier onlyClientOwner(address client_) {
    require(clients[client_].owner == msg.sender, "ONLY_CLIENT_OWNER");
    _;
  }

  constructor(
    address cvpToken_,
    address wethToken_,
    address fastGasOracle_,
    address uniswapRouter_,
    address powerPokeStaking_
  ) public {
    CVP_TOKEN = IERC20(cvpToken_);
    WETH_TOKEN = wethToken_;
    FAST_GAS_ORACLE = IEACAggregatorProxy(fastGasOracle_);
    POWER_POKE_STAKING = PowerPokeStaking(powerPokeStaking_);
    UNISWAP_ROUTER = IUniswapV2Router02(uniswapRouter_);
  }

  function initialize(address owner_, address oracle_) external initializer {
    _transferOwnership(owner_);
    oracle = IPowerOracle(oracle_);
  }

  function authorizeReporter(uint256 userId_, address pokerKey_) external view {
    POWER_POKE_STAKING.authorizeHDH(userId_, pokerKey_);
  }

  function authorizeNonReporter(uint256 userId_, address pokerKey_) external view {
    POWER_POKE_STAKING.authorizeNonHDH(userId_, pokerKey_, clients[msg.sender].minSlasherDeposit);
  }

  function authorizeNonReporter(
    uint256 userId_,
    address pokerKey_,
    uint256 overrideMinDeposit_
  ) external view {
    POWER_POKE_STAKING.authorizeNonHDH(userId_, pokerKey_, overrideMinDeposit_);
  }

  function authorizePoker(uint256 userId_, address pokerKey_) external view {
    POWER_POKE_STAKING.authorizeMember(userId_, pokerKey_, clients[msg.sender].minPokerDeposit);
  }

  function authorizePoker(
    uint256 userId_,
    address pokerKey_,
    uint256 overrideMinStake_
  ) external view {
    POWER_POKE_STAKING.authorizeMember(userId_, pokerKey_, overrideMinStake_);
  }

  function slashReporter(uint256 userId_, uint256 amount_) external {
    require(clients[msg.sender].active, "INVALID_CLIENT");
    require(clients[msg.sender].canSlash, "CANT_SLASH");
    if (amount_ == 0) {
      return;
    }

    POWER_POKE_STAKING.slashHDH(userId_, amount_);
  }

  function reward(
    uint256 userId_,
    uint256 gasUsed_,
    bytes calldata pokeOptions_
  ) external nonReentrant {
    require(clients[msg.sender].active, "INVALID_CLIENT");
    if (gasUsed_ == 0) {
      return;
    }
    uint256 ethPrice = oracle.getPriceByAsset(WETH_TOKEN);
    uint256 cvpPrice = oracle.getPriceByAsset(address(CVP_TOKEN));

    uint256 compensation = getGasPriceFor(msg.sender)
      .mul(gasUsed_)
      .mul(ethPrice)
      / cvpPrice;
    uint256 userDeposit = POWER_POKE_STAKING.getDepositOf(userId_);

    if (userDeposit == 0) {
      return;
    }

    uint256 bonus = userDeposit.mul(clients[msg.sender].pokeBonus).mul(gasUsed_).div(HUNDRED_PCT).div(HUNDRED_K);

    uint256 totalCVPReward = compensation.add(bonus);
    clients[msg.sender].credit = clients[msg.sender].credit.sub(totalCVPReward);
    uint256 compensatedInETH = 0;

    PokeRewardOptions memory opts = abi.decode(pokeOptions_, (PokeRewardOptions));

    if (opts.rewardInEth) {
      compensatedInETH = _payoutCompensationInETH(opts.to, compensation);
      rewards[userId_] = rewards[userId_].add(bonus);
    } else {
      rewards[userId_] = rewards[userId_].add(totalCVPReward);
    }

    emit RewardUser(
      msg.sender,
      userId_,
      opts.rewardInEth,
      compensation,
      bonus,
      compensatedInETH,
      userDeposit,
      ethPrice,
      cvpPrice,
      totalCVPReward
    );
  }

  function addCredit(address client_, uint256 amount_) external onlyClientOwner(client_) {
    Client storage client = clients[client_];

    CVP_TOKEN.transferFrom(msg.sender, address(this), amount_);
    client.credit = client.credit.add(amount_);

    emit AddCredit(client_, amount_);
  }

  function withdrawCredit(
    address client_,
    address to_,
    uint256 amount_
  ) external onlyClientOwner(client_) {
    Client storage client = clients[client_];

    client.credit = client.credit.sub(amount_);

    CVP_TOKEN.transfer(to_, amount_);

    emit WithdrawCredit(client_, to_, amount_);
  }

  function setReportIntervals(
    address client_,
    uint256 minReportInterval_,
    uint256 maxReportInterval_
  ) external onlyClientOwner(client_) {
    clients[client_].minReportInterval = minReportInterval_;
    clients[client_].maxReportInterval = maxReportInterval_;
    emit SetReportIntervals(client_, minReportInterval_, maxReportInterval_);
  }

  function setSlasherHearbeat(address client_, uint256 slasherHeartbeat_) external onlyClientOwner(client_) {
    clients[client_].slasherHeartbeat = slasherHeartbeat_;
    emit SetSlasherHeartbeat(client_, slasherHeartbeat_);
  }

  function setGasPriceLimit(address client_, uint256 gasPriceLimit_) external onlyClientOwner(client_) {
    clients[client_].gasPriceLimit = gasPriceLimit_;
    emit SetGasPriceLimit(client_, gasPriceLimit_);
  }

  function setBonuses(
    address client_,
    uint256 pokeBonus_,
    uint256 slasherHeartbeatBonus_
  ) external onlyClientOwner(client_) {
    clients[client_].pokeBonus = pokeBonus_;
    clients[client_].slasherHeartbeatBonus = slasherHeartbeatBonus_;
    emit SetBonuses(client_, pokeBonus_, slasherHeartbeatBonus_);
  }

  function setMinimalDeposits(
    address client_,
    uint256 minPokerDeposit_,
    uint256 minSlasherDeposit_
  ) external onlyClientOwner(client_) {
    clients[client_].minPokerDeposit = minPokerDeposit_;
    clients[client_].minSlasherDeposit = minSlasherDeposit_;
    emit SetMinimalDeposits(client_, minPokerDeposit_, minSlasherDeposit_);
  }

  function withdrawRewards(uint256 userId_, address to_) external {
    POWER_POKE_STAKING.requireValidAdminKey(userId_, msg.sender);
    require(to_ != address(0), "0_ADDRESS");
    uint256 rewardAmount = rewards[userId_];
    require(rewardAmount > 0, "NOTHING_TO_WITHDRAW");
    rewards[userId_] = 0;

    CVP_TOKEN.transfer(to_, rewardAmount);

    emit WithdrawRewards(userId_, to_, rewardAmount);
  }

  function getMinMaxReportIntervals(address client_) external view returns (uint256 min, uint256 max) {
    return (clients[client_].minReportInterval, clients[client_].maxReportInterval);
  }

  function getSlasherHeartbeat(address client_) external view returns (uint256) {
    return clients[client_].slasherHeartbeat;
  }

  function _payoutCompensationInETH(address _to, uint256 _cvpAmount) internal returns (uint256) {
    CVP_TOKEN.approve(address(UNISWAP_ROUTER), _cvpAmount);

    address[] memory path = new address[](2);
    path[0] = address(CVP_TOKEN);
    path[1] = address(WETH_TOKEN);

    uint256[] memory amounts = UNISWAP_ROUTER.swapExactTokensForETH(_cvpAmount, uint256(0), path, _to, now.add(1800));
    return amounts[1];
  }

  function _latestFastGas() internal view returns (uint256) {
    return uint256(FAST_GAS_ORACLE.latestAnswer());
  }

  function getGasPriceFor(address client_) public view returns (uint256) {
    return Math.min(tx.gasprice, Math.min(_latestFastGas(), clients[client_].gasPriceLimit));
  }
}
