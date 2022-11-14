// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../../interfaces/uniswap/IUniswapV2Router01.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IBase.sol";

struct HarvestSwapParms {
	address[] path; //path that the token takes
	uint256 min; // min price of in token * 1e18 (computed externally based on spot * slippage + fees)
	uint256 deadline;
}

abstract contract IFarmable is IBase {
	using SafeERC20 for IERC20;

	event HarvestedToken(address indexed token, uint256 amount);

	function _swap(
		IUniswapV2Router01 router,
		HarvestSwapParms calldata swapParams,
		address from,
		uint256 amount
	) internal {
		address out = swapParams.path[swapParams.path.length - 1];
		// ensure malicious harvester is not trading with wrong tokens
		// TODO should we add more validation to prevent malicious path?
		require(
			((swapParams.path[0] == address(from) && (out == address(short()))) ||
				out == address(underlying())),
			"IFarmable: WRONG_PATH"
		);
		router.swapExactTokensForTokens(
			amount,
			swapParams.min,
			swapParams.path, // optimal route determined externally
			address(this),
			swapParams.deadline
		);
	}
}
