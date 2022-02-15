// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../mixins/IBase.sol";
import "../mixins/ILending.sol";
import "../mixins/IFarmableLp.sol";
import "../mixins/IUniLp.sol";
import "./BaseStrategy.sol";
import "../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

// @custom: alphabetize dependencies to avoid linearization conflicts
abstract contract HedgedLP is IBase, BaseStrategy, ILending, IFarmableLp, IUniLp {
	using UniUtils for IUniswapV2Pair;
	using SafeERC20 for IERC20;

	event RebalanceLoan(address indexed sender, uint256 startLoanHealth, uint256 updatedLoanHealth);
	event setMinLoanHealth(uint256 loanHealth);
	event SetMaxPriceMismatch(uint256 loanHealth);
	event SetRebalanceThreshold(uint256 loanHealth);
	event SetMaxTvl(uint256 loanHealth);

	uint256 constant MINIMUM_LIQUIDITY = 1000;
	uint256 private _maxPriceMismatch = 70; // .7% based around uniswap .6% bid-ask spread
	uint256 public minLoanHealth = 1.05e18;

	IERC20 private _underlying;
	IERC20 private _short;

	uint16 public rebalanceThreshold = 400; // 4% of lp
	uint16 public version = 2;

	uint256 private _maxTvl;
	// for security we update this value only after oracle price checks in 'getAndUpdateTvl'
	uint256 private _cachedBalanceOfUnderlying;

	modifier checkPrice() {
		uint256 minPrice = _shortToUnderlying(1e18);
		// oraclePrice
		uint256 maxPrice = _oraclePriceOfShort(1e18);
		(minPrice, maxPrice) = maxPrice > minPrice ? (minPrice, maxPrice) : (maxPrice, minPrice);
		require(
			((maxPrice - minPrice) * BPS_ADJUST) / maxPrice < _maxPriceMismatch,
			"HLP: PRICE_MISMATCH"
		);
		_;
		// any method that uses checkPrice should updated the _cachedBalanceOfUnderlying
		_cachedBalanceOfUnderlying = getTotalTVL();
	}

	function __HedgedLP_init_(
		address underlying_,
		address short_,
		uint256 maxTvl_
	) internal initializer {
		_underlying = IERC20(underlying_);
		_short = IERC20(short_);

		_underlying.safeApprove(address(this), type(uint256).max);

		BASE_UNIT = 10**decimals();

		// init params
		setMaxTvl(maxTvl_);

		// emit default settings events
		emit setMinLoanHealth(minLoanHealth);
		emit SetMaxPriceMismatch(_maxPriceMismatch);
		emit SetRebalanceThreshold(rebalanceThreshold);

		// TODO should we add a revoke aprovals methods?
		_addLendingApprovals();
		_addFarmApprovals();

		isInitialized = true;
	}

	function decimals() public view returns (uint8) {
		return IERC20Metadata(address(_underlying)).decimals();
	}

	// OWNER CONFIG
	function setMinLoanHeath(uint256 minLoanHealth_) public onlyOwner {
		minLoanHealth = minLoanHealth_;
		emit setMinLoanHealth(minLoanHealth_);
	}

	function setMaxPriceMismatch(uint256 maxPriceMismatch_) public onlyOwner {
		_maxPriceMismatch = maxPriceMismatch_;
		emit SetMaxPriceMismatch(maxPriceMismatch_);
	}

	function setRebalanceThreshold(uint16 rebalanceThreshold_) public onlyOwner {
		rebalanceThreshold = rebalanceThreshold_;
		emit SetRebalanceThreshold(rebalanceThreshold_);
	}

	function setMaxTvl(uint256 maxTvl_) public onlyAuth {
		_maxTvl = maxTvl_;
		emit SetMaxTvl(maxTvl_);
	}

	// PUBLIC METHODS

	function short() public view override returns (IERC20) {
		return _short;
	}

	function underlying() public view override returns (IERC20) {
		return _underlying;
	}

	// public method that anyone can call to prevent an immenent loan liquidation
	// this is an emergency measure in case rebalance() is not called in time
	// price check is not necessary here because we are only removing LP and
	// if swap price differs it is to our benefit
	function rebalanceLoan() public nonReentrant {
		uint256 _loanHealth = loanHealth();
		require(_loanHealth <= minLoanHealth, "HLP: SAFE");
		(uint256 underlyingLp, ) = _getLPBalances();

		// remove 5% of LP to repay loan & add collateral
		uint256 newLP = (9500 * _loanHealth * underlyingLp) / 10000 / minLoanHealth;

		// remove lp
		(uint256 underlyingBalance, uint256 shortBalance) = _decreaseLpTo(newLP);

		_repay(shortBalance);
		_lend(underlyingBalance);
		emit RebalanceLoan(msg.sender, _loanHealth, loanHealth());
	}

	function _deposit(uint256 amount)
		internal
		override
		checkPrice
		nonReentrant
		returns (uint256 newShares)
	{
		if (amount <= 0) return 0; // cannot deposit 0
		uint256 tvl = _getAndUpdateTVL();
		require(amount + tvl <= getMaxTvl(), "HLP: OVER_MAX_TVL");
		newShares = totalSupply() == 0 ? amount : (totalSupply() * amount) / tvl;
		_underlying.transferFrom(vault(), address(this), amount);
		_increasePosition(amount);
		emit Deposit(msg.sender, amount);
	}

	// can pass type(uint256).max to withdraw full amount
	function _withdraw(uint256 amount)
		internal
		override
		checkPrice
		nonReentrant
		returns (uint256 burnShares)
	{
		if (amount == 0) return 0;
		uint256 tvl = _getAndUpdateTVL();
		if (tvl == 0) return 0;

		uint256 reserves = _underlying.balanceOf(address(this));

		// if we can not withdraw straight out of reserves
		if (reserves < amount) {
			// add .5% to withdraw amount for tx fees & slippage etc
			uint256 withdrawAmnt = amount == type(uint256).max
				? tvl
				: min(tvl, (amount * 1005) / 1000);

			// decrease current position
			withdrawAmnt = withdrawAmnt >= tvl
				? _closePosition()
				: _decreasePosition(withdrawAmnt - reserves) + reserves;

			// use the minimum of the two
			amount = min(withdrawAmnt, amount);
		}
		// grab current tvl to account for fees and slippage
		tvl = getTotalTVL();
		// round up to keep price precision and leave less dust
		burnShares = min(((amount + 1) * totalSupply()) / tvl, totalSupply());

		_underlying.safeTransferFrom(address(this), vault(), amount);
		// require(tvl > 0, "no funds in vault");
		emit Withdraw(msg.sender, amount);
	}

	// decreases position based on current desired balance
	// ** does not rebalance remaining portfolio
	// ** may return slighly less then desired amount
	// ** make sure to update lending positions before calling this
	function _decreasePosition(uint256 amount) internal returns (uint256) {
		uint256 removeLpAmnt = _totalToLp(amount);
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 shortPosition = _getBorrowBalance();
		uint256 removeShortLp = _underlyingToShort(removeLpAmnt);

		if (removeLpAmnt >= underlyingLp || removeShortLp >= shortPosition) return _closePosition();

		// remove lp
		(uint256 availableUnderlying, uint256 shortBalance) = _decreaseLpTo(
			underlyingLp - removeLpAmnt
		);

		_repay(shortBalance);

		// this might remove less collateral than desired if we hit the limit
		// this happens when position is close to empty
		availableUnderlying += _removeCollateral(amount - availableUnderlying);
		return availableUnderlying;
	}

	// increases the position based on current desired balance
	// ** does not rebalance remaining portfolio
	function _increasePosition(uint256 amount) internal {
		if (amount < MINIMUM_LIQUIDITY) return; // avoid imprecision
		uint256 amntUnderlying = _totalToLp(amount);
		uint256 amntShort = _underlyingToShort(amntUnderlying);
		_lend(amount - amntUnderlying);
		_borrow(amntShort);
		uint256 liquidity = _addLiquidity(amntUnderlying, amntShort);
		_depositIntoFarm(liquidity);
	}

	// use the return of the function to estimate pending harvest via staticCall
	function harvest(
		HarvestSwapParms[] calldata uniParams,
		HarvestSwapParms[] calldata lendingParams
	)
		external
		onlyAuth
		checkPrice
		nonReentrant
		returns (uint256[] memory farmHarvest, uint256[] memory lendHarvest)
	{
		uint256 startTvl = _getAndUpdateTVL();

		if (uniParams.length != 0) farmHarvest = _harvestFarm(uniParams);
		if (lendingParams.length != 0) lendHarvest = _harvestLending(lendingParams);

		// deposit funds back into farm
		uint256 underlyingBal = _underlying.balanceOf(address(this));
		if (underlyingBal > 0) _lend(underlyingBal);
		uint256 shortBal = _short.balanceOf(address(this));
		if (shortBal > 0) _repay(shortBal);
		uint256 endTvl = getTotalTVL();

		emit Harvest(endTvl > startTvl ? (endTvl - startTvl) : 0);
	}

	// MANAGER + OWNER METHODS

	function rebalance() external onlyAuth checkPrice nonReentrant {
		// call this first to ensure we use an updated borrowBalance when computing offset
		uint256 tvl = _getAndUpdateTVL();
		uint256 positionOffset = getPositionOffset();

		// don't rebalance unless we exceeded the threshold
		require(positionOffset > rebalanceThreshold, "HLP: REB-THRESH"); // maybe next time...

		if (tvl == 0) return;
		uint256 targetUnderlyingLP = _totalToLp(tvl);

		// pass targetUnderlyingLP, tragetCollateral to _rebalancePosition
		// add .15% for swap fees
		_rebalancePosition(targetUnderlyingLP, tvl - (10015 * targetUnderlyingLP) / 10000);
		emit Rebalance(_shortToUnderlying(1e18), positionOffset, tvl);
	}

	function closePosition() external onlyAuth checkPrice {
		_closePosition();
	}

	function _closePosition() internal returns (uint256) {
		_decreaseLpTo(0);
		uint256 shortPosition = _updateAndGetBorrowBalance();
		uint256 shortBalance = _short.balanceOf(address(this));
		if (shortPosition > shortBalance) {
			pair()._swapTokensForExactTokens(
				shortPosition - shortBalance,
				address(_underlying),
				address(_short)
			);
		} else if (shortBalance > shortPosition) {
			pair()._swapExactTokensForTokens(
				shortBalance - shortPosition,
				address(_short),
				address(_underlying)
			);
		}
		_repay(_short.balanceOf(address(this)));
		uint256 collateralBalance = _updateAndGetCollateralBalance();
		_redeem(collateralBalance);
		return _underlying.balanceOf(address(this));
	}

	function _decreaseLpTo(uint256 targetUnderlyingLP)
		internal
		returns (uint256 underlyingRemove, uint256 shortRemove)
	{
		(uint256 underlyingLp, ) = _getLPBalances();
		if (targetUnderlyingLP >= underlyingLp) return (0, 0); // nothing to withdraw
		uint256 liquidity = _getLiquidity();
		uint256 targetLiquidity = (liquidity * targetUnderlyingLP) / underlyingLp;
		uint256 removeLp = liquidity - targetLiquidity;
		uint256 liquidityBalance = pair().balanceOf(address(this));
		if (removeLp > liquidityBalance) _withdrawFromFarm(removeLp - liquidityBalance);
		return removeLp == 0 ? (0, 0) : _removeLiquidity(removeLp);
	}

	function _rebalancePosition(uint256 targetUnderlyingLP, uint256 targetCollateral) internal {
		uint256 targetBorrow = _oraclePriceOfUnderlying(targetUnderlyingLP);
		// we already updated tvl
		uint256 currentBorrow = _getBorrowBalance();

		// borrow funds or repay loan
		if (targetBorrow > currentBorrow) {
			// remove extra lp (we may need to remove more in order to add more collateral)
			_decreaseLpTo(
				_needUnderlying(targetUnderlyingLP, targetCollateral) > 0 ? 0 : targetUnderlyingLP
			);
			// add collateral
			_adjustCollateral(targetCollateral);
			_borrow(targetBorrow - currentBorrow);
		} else if (targetBorrow < currentBorrow) {
			// remove all of lp so we can repay loan
			_decreaseLpTo(0);
			uint256 repayAmnt = min(_short.balanceOf(address(this)), currentBorrow - targetBorrow);
			if (repayAmnt > 0) _repay(repayAmnt);
			// remove extra collateral
			_adjustCollateral(targetCollateral);
		}

		///////////////////////////
		//// INCREASE LP POSITION
		///////////////////////
		uint256 underlyingBalance = _underlying.balanceOf(address(this));
		uint256 shortBalance = _short.balanceOf(address(this));

		// here we make sure we don't add extra lp
		(, uint256 shortLP) = _getLPBalances();
		uint256 addShort = min(
			shortBalance + _underlyingToShort(underlyingBalance),
			targetBorrow - shortLP
		);
		uint256 addUnderlying = _shortToUnderlying(addShort);

		// buy or sell underlying
		if (addUnderlying < underlyingBalance) {
			shortBalance += pair()._swapExactTokensForTokens(
				underlyingBalance - addUnderlying,
				address(_underlying),
				address(_short)
			);
			underlyingBalance = addUnderlying;
		} else if (shortBalance > addShort) {
			underlyingBalance += pair()._swapExactTokensForTokens(
				shortBalance - addShort,
				address(_short),
				address(_underlying)
			);
			shortBalance = addShort;
		}

		// compute final lp amounts
		uint256 amntShort = shortBalance;
		uint256 amntUnderlying = _shortToUnderlying(amntShort);
		if (underlyingBalance < amntUnderlying) {
			amntUnderlying = underlyingBalance;
			amntShort = _underlyingToShort(amntUnderlying);
		}

		if (amntUnderlying == 0) return;

		// add liquidity
		// don't need to use min with underlying and short because we did oracle check
		// amounts are exact because we used swap price above
		uint256 liquidity = _addLiquidity(amntUnderlying, amntShort);
		_depositIntoFarm(liquidity);
	}

	function _needUnderlying(uint256 tragetUnderlying, uint256 targetCollateral)
		internal
		view
		returns (uint256)
	{
		uint256 collateralBalance = _getCollateralBalance();
		if (targetCollateral < collateralBalance) return 0;
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 uBalance = tragetUnderlying > underlyingLp ? tragetUnderlying - underlyingLp : 0;
		uint256 addCollateral = targetCollateral - collateralBalance;
		if (uBalance >= addCollateral) return 0;
		return addCollateral - uBalance;
	}

	// TVL

	function getMaxTvl() public view override returns (uint256) {
		return min(_maxTvl, _borrowToTotal(_oraclePriceOfShort(_maxBorrow())));
	}

	// TODO should we compute pending farm & lending rewards here?
	function _getAndUpdateTVL() internal returns (uint256 tvl) {
		uint256 collateralBalance = _updateAndGetCollateralBalance();
		uint256 shortPosition = _updateAndGetBorrowBalance();
		uint256 borrowBalance = _oraclePriceOfShort(shortPosition);
		uint256 shortP = _short.balanceOf(address(this));
		uint256 shortBalance = shortP == 0
			? 0
			: _shortToUnderlying(_short.balanceOf(address(this)));
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 underlyingBalance = _underlying.balanceOf(address(this));
		tvl =
			collateralBalance +
			underlyingLp *
			2 -
			borrowBalance +
			underlyingBalance +
			shortBalance;
	}

	// for security this method should return cached value only
	// this is used by vault to track balance,
	// so this value should only be updated after oracle price check
	function balanceOfUnderlying() public view override returns (uint256) {
		return _cachedBalanceOfUnderlying;
	}

	function getTotalTVL() public view returns (uint256 tvl) {
		(tvl, , , , , ) = getTVL();
	}

	function getTVL()
		public
		view
		returns (
			uint256 tvl,
			uint256 collateralBalance,
			uint256 shortPosition,
			uint256 borrowBalance,
			uint256 lpBalance,
			uint256 underlyingBalance
		)
	{
		collateralBalance = _getCollateralBalance();
		shortPosition = _getBorrowBalance();

		uint256 shortP = _short.balanceOf(address(this));
		uint256 shortBalance = shortP == 0 ? 0 : _oraclePriceOfShort(shortP);

		borrowBalance = _shortToUnderlying(shortPosition);
		(uint256 underlyingLp, uint256 shortLp) = _getLPBalances();
		lpBalance = underlyingLp + _shortToUnderlying(shortLp);
		underlyingBalance = _underlying.balanceOf(address(this));

		tvl = collateralBalance + lpBalance - borrowBalance + underlyingBalance + shortBalance;
	}

	function getPositionOffset() public view returns (uint256 positionOffset) {
		(, uint256 shortLp) = _getLPBalances();
		uint256 borrowBalance = _getBorrowBalance();
		// TODO
		// uint256 shortBalance = shortLp + _short.balanceOf(address(this));

		if (shortLp == borrowBalance) return 0;
		// if short lp > 0 and borrowBalance is 0 we are off by inf, returning 100% should be enough
		if (borrowBalance == 0) return 10000;

		// this is the % by which our position has moved from beeing balanced
		positionOffset = shortLp > borrowBalance
			? ((shortLp - borrowBalance) * BPS_ADJUST) / borrowBalance
			: ((borrowBalance - shortLp) * BPS_ADJUST) / borrowBalance;
	}

	// UTILS

	function _totalToLp(uint256 total) internal view returns (uint256) {
		uint256 cRatio = getCollateralRatio();
		return (total * cRatio) / (BPS_ADJUST + cRatio);
	}

	function _borrowToTotal(uint256 amount) internal view returns (uint256) {
		uint256 cRatio = getCollateralRatio();
		return (amount * (BPS_ADJUST + cRatio)) / cRatio;
	}

	// this is the current uniswap price
	function _shortToUnderlying(uint256 amount) internal view returns (uint256) {
		return amount == 0 ? 0 : _quote(amount, address(_short), address(_underlying));
	}

	// this is the current uniswap price
	function _underlyingToShort(uint256 amount) internal view returns (uint256) {
		return amount == 0 ? 0 : _quote(amount, address(_underlying), address(_short));
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
}
