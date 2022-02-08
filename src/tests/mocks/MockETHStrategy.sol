// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20Dec as ERC20 } from "../../tokens/ERC20Dec.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import "../../libraries/SafeETH.sol";

import { ETHStrategy } from "../../interfaces/Strategy.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockETHStrategy is ERC20("Mock cEther Strategy", "cEther", 18), ETHStrategy {
	using SafeETH for address;
	using SafeERC20 for address;
	using SafeERC20 for IERC20;

	using FixedPointMathLib for uint256;

	/*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

	function isCEther() external pure override returns (bool) {
		return true;
	}

	function getMaxTvl() external pure override returns (uint256) {
		return type(uint256).max;
	}

	function mint() external payable override {
		_mint(msg.sender, msg.value.fdiv(exchangeRate(), 1e18));
	}

	function redeemUnderlying(uint256 amount) external override returns (uint256) {
		_burn(msg.sender, amount.fdiv(exchangeRate(), 1e18));

		msg.sender.safeTransferETH(amount);

		return 0;
	}

	function balanceOfUnderlying(address user) external view override returns (uint256) {
		return balanceOf(user).fmul(exchangeRate(), 1e18);
	}

	// emergency only
	// closePosition should be attempted first, if after some tokens are stuck,
	// send them to a designated address
	function emergencyWithdraw(address recipient, IERC20[] calldata tokens) external override {
		for (uint256 i = 0; i < tokens.length; i++) {
			IERC20 token = tokens[i];
			uint256 balance = token.balanceOf(address(this));
			if (balance != 0) token.safeTransfer(recipient, balance);
		}
	}

	/*///////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

	function exchangeRate() internal view returns (uint256) {
		uint256 cTokenSupply = totalSupply();

		if (cTokenSupply == 0) return 1e18;

		return address(this).balance.fdiv(cTokenSupply, 1e18);
	}

	/*///////////////////////////////////////////////////////////////
                              MOCK LOGIC
    //////////////////////////////////////////////////////////////*/

	function simulateLoss(uint256 underlyingAmount) external {
		address(0xDEAD).safeTransferETH(underlyingAmount);
	}
}
