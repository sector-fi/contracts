// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "../../interfaces/compound/ICTokenInterfaces.sol";
import "../../interfaces/compound/IComptroller.sol";
import "../../interfaces/compound/ICompPriceOracle.sol";
import "../../interfaces/compound/IComptroller.sol";

import "../../mixins/ICompound.sol";

// import "hardhat/console.sol";

abstract contract Compound is ICompound {
	using SafeERC20 for IERC20;

	ICTokenErc20 private _cTokenLend;
	ICTokenErc20 private _cTokenBorrow;

	IComptroller private _comptroller;
	ICompPriceOracle private _oracle;

	uint256 private _safeCollateralRatio; // percentage of max ratio

	function __Compound_init_(
		address comptroller_,
		address cTokenLend_,
		address cTokenBorrow_,
		uint256 safeCollateralRatio_
	) internal {
		_cTokenLend = ICTokenErc20(cTokenLend_);
		_cTokenBorrow = ICTokenErc20(cTokenBorrow_);
		_comptroller = IComptroller(comptroller_);
		_oracle = ICompPriceOracle(ComptrollerV1Storage(comptroller_).oracle());

		_safeCollateralRatio = safeCollateralRatio_;
		_enterMarket();
	}

	function _addLendingApprovals() internal override {
		// ensure USDC approval - assume we trust USDC
		underlying().safeApprove(address(_cTokenLend), type(uint256).max);
		short().safeApprove(address(_cTokenBorrow), type(uint256).max);
	}

	function safeCollateralRatio() public view override(ILending) returns (uint256) {
		return _safeCollateralRatio;
	}

	function cTokenLend() public view override returns (ICTokenErc20) {
		return _cTokenLend;
	}

	function cTokenBorrow() public view override returns (ICTokenErc20) {
		return _cTokenBorrow;
	}

	function oracle() public view override returns (ICompPriceOracle) {
		return _oracle;
	}

	function comptroller() public view override returns (IComptroller) {
		return _comptroller;
	}
}