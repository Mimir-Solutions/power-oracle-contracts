// // SPDX-License-Identifier: GPL-3.0

// pragma solidity ^0.6.10;
// pragma experimental ABIEncoderV2;

// interface IPowerOracle {
//   enum ReportInterval { LESS_THAN_MIN, OK, GREATER_THAN_MAX }

//   function pokeFromReporter(uint256 reporterId_, string[] memory symbols_) external;

//   function pokeFromSlasher(uint256 slasherId_, string[] memory symbols_) external;

//   function poke(string[] memory symbols_) external;

//   function withdrawRewards(uint256 userId, address to) external;

//   function slasherUpdate(uint256 slasherId) external;

//   /*** Owner Interface ***/
//   function setCvpAPY(uint256 cvpReportAPY_, uint256 cvpSlasherUpdateAPY_) external;

//   function setTotalPerYear(uint256 totalReportsPerYear_, uint256 totalSlasherUpdatesPerYear_) external;

//   function setGasExpenses(
//     uint256 gasExpensesPerAssetReport_,
//     uint256 gasExpensesForSlasherStatusUpdate_,
//     uint256 gasExpensesForSlasherPokeStatusUpdate_
//   ) external;

//   function setGasPriceLimit(uint256 gasPriceLimit_) external;

//   function setPowerOracleStaking(address powerOracleStaking) external;

//   function setReportIntervals(uint256 minInterval, uint256 maxInterval) external;

//   function pause() external;

//   function unpause() external;

//   /*** Viewers ***/
//   function getPriceByAsset(address token) external view returns (uint256);

//   function getPriceBySymbol(string calldata symbol) external view returns (uint256);

//   function getPriceBySymbolHash(bytes32 symbolHash) external view returns (uint256);

//   function getUnderlyingPrice(address cToken) external view returns (uint256);

//   function assetPrices(address token) external view returns (uint256);
// }
