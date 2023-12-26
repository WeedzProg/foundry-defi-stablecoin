// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// checks the heartbeat of the oracle
// timestamp is the last time the oracle was updated
// and if it is not updated in that timespan, it will return false and the contract will be in pause

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__OracleIsStale();

    // a global view of the oracle timeout
    uint256 public constant GENERAL_ORACLE_TIMEOUT = 3600; // in seconds, 1 hour

    // for a more precise heartbeat for each token, better to grab the heartbeat value by token address

    /**
     * @dev Checks the heartbeat of the oracle
     * @param priceFeed is the price feed of the oracle, same output as the latestRoundData() function in the AggregatorV3Interface
     * @return bool if the oracle is stale or not
     */

    function stalePriceFeedCheck(
        AggregatorV3Interface priceFeed
    ) internal view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        uint256 updatedAt = timeStamp;
        uint256 timeDiff = block.timestamp - updatedAt;
        if (timeDiff > GENERAL_ORACLE_TIMEOUT) revert OracleLib__OracleIsStale();
        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }
}
