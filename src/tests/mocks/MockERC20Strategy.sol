// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20Dec as ERC20 } from "../../tokens/ERC20Dec.sol";

import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { ERC20Strategy } from "../../interfaces/Strategy.sol";

contract MockERC20Strategy is ERC20("Mock cERC20 Strategy", "cERC20", 18), ERC20Strategy {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	uint256 private _maxTvl;

	constructor(IERC20 _UNDERLYING) {
		UNDERLYING = _UNDERLYING;

		BASE_UNIT = 10**ERC20(address(_UNDERLYING)).decimals();

		_maxTvl = type(uint256).max;
	}

	/*///////////////////////////////////////////////////////////////
                             STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

	function isCEther() external pure override returns (bool) {
		return false;
	}

	function setMaxTvl(uint256 maxTvl_) external {
		_maxTvl = maxTvl_;
	}

	function getMaxTvl() external view override returns (uint256) {
		return _maxTvl;
	}

	function underlying() external view override returns (IERC20) {
		return UNDERLYING;
	}

	function mint(uint256 amount) external override returns (uint256) {
		_mint(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

		UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);

		return 0;
	}

	function redeemUnderlying(uint256 amount) external virtual override returns (uint256) {
		_burn(msg.sender, amount.fdiv(exchangeRate(), BASE_UNIT));

		UNDERLYING.safeTransfer(msg.sender, amount);

		return 0;
	}

	function balanceOfUnderlying(address user) external view override returns (uint256) {
		return balanceOf(user).fmul(exchangeRate(), BASE_UNIT);
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

	IERC20 internal immutable UNDERLYING;

	uint256 internal immutable BASE_UNIT;

	function exchangeRate() internal view returns (uint256) {
		uint256 cTokenSupply = totalSupply();

		if (cTokenSupply == 0) return BASE_UNIT;

		return UNDERLYING.balanceOf(address(this)).fdiv(cTokenSupply, BASE_UNIT);
	}

	/*///////////////////////////////////////////////////////////////
                              MOCK LOGIC
    //////////////////////////////////////////////////////////////*/

	function simulateLoss(uint256 underlyingAmount) external {
		UNDERLYING.safeTransfer(address(0xDEAD), underlyingAmount);
	}
}

contract MockERC20StrategyBroken is MockERC20Strategy {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	constructor(IERC20 _UNDERLYING) MockERC20Strategy(_UNDERLYING) {}

	function redeemUnderlying(uint256) external pure override returns (uint256) {
		require(false, "BROKEN");
		return 0;
	}
}

contract MockERC20StrategyPriceMismatch is MockERC20Strategy {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	constructor(IERC20 _UNDERLYING) MockERC20Strategy(_UNDERLYING) {}

	function redeemUnderlying(uint256) external pure override returns (uint256) {
		require(false, "HLP: PRICE_MISMATCH");
		return 0;
	}
}
