// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ICTokenInterfaces.sol";

interface ICompPriceOracle {
	function isPriceOracle() external view returns (bool);

	/**
	 * @notice Get the underlying price of a cToken asset
	 * @param cToken The cToken to get the underlying price of
	 * @return The underlying asset price mantissa (scaled by 1e18).
	 *  Zero means the price is unavailable.
	 */
	function getUnderlyingPrice(address cToken) external view returns (uint256);
}
