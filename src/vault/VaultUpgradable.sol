// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {SafeCastLib} from "../libraries/SafeCastLib.sol";
import {FixedPointMathLib} from "../libraries/FixedPointMathLib.sol";

import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

import {Strategy, ERC20Strategy, ETHStrategy} from "../interfaces/Strategy.sol";

/// @title Rari Vault (rvToken)
/// @author Transmissions11 and JetJadeja
/// @notice Flexible, minimalist, and gas-optimized yield aggregator for
/// earning interest on any ERC20 token.
contract VaultUpgradable is
    Initializable,
    ERC20,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeCastLib for uint256;
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// security: marks implementation contract as initialized
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /// @notice The underlying token the Vault accepts.
    IERC20 public UNDERLYING;

    /// @notice The base unit of the underlying token and hence rvToken.
    /// @dev Equal to 10 ** decimals. Used for fixed point arithmetic.
    uint256 public BASE_UNIT;

    uint256 private _decimals;

    /// @notice Emitted when the Vault is initialized.
    /// @param user The authorized user who triggered the initialization.
    event Initialized(address indexed user);

    /// @notice Creates a new Vault that accepts a specific underlying token.
    /// @param _UNDERLYING The ERC20 compliant token the Vault should accept.
    function initialize(
        IERC20 _UNDERLYING,
        address _owner,
        address _manager,
        uint256 _feePercent,
        uint64 _harvestDelay,
        uint128 _harvestWindow
    ) external initializer {
        __ERC20_init(
            // ex: Scion USDC.e Vault
            string(
                abi.encodePacked(
                    "Scion ",
                    ERC20(address(_UNDERLYING)).name(),
                    " Vault"
                )
            ),
            // ex: sUSDC.e
            string(abi.encodePacked("sc", ERC20(address(_UNDERLYING)).symbol()))
        );

        __ReentrancyGuard_init();
        __Ownable_init();

        _decimals = ERC20(address(_UNDERLYING)).decimals();

        UNDERLYING = _UNDERLYING;

        BASE_UNIT = 10**_decimals;

        // configure
        setManager(_manager, true);
        setFeePercent(_feePercent);

        // delay must be set first
        setHarvestDelay(_harvestDelay);
        setHarvestWindow(_harvestWindow);

        emit Initialized(msg.sender);

        // must be call after all other inits
        _transferOwnership(_owner);

        // defaults to open vaults
        _maxTvl = type(uint256).max;
        _stratMaxTvl = type(uint256).max;

        version = 2;
    }

    function decimals() public view override returns (uint8) {
        return uint8(_decimals);
    }

    /*///////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The maximum number of elements allowed on the withdrawal stack.
    /// @dev Needed to prevent denial of service attacks by queue operators.
    uint256 internal constant MAX_WITHDRAWAL_STACK_SIZE = 32;

    /*///////////////////////////////////////////////////////////////
                                AUTH
    //////////////////////////////////////////////////////////////*/

    event ManagerUpdate(address indexed account, bool isManager);
    event AllowedUpdate(address indexed account, bool isManager);
    event SetPublic(bool setPublic);

    modifier requiresAuth() {
        require(
            msg.sender == owner() || isManager(msg.sender),
            "Vault: NO_AUTH"
        );
        _;
    }

    mapping(address => bool) private _allowed;

    // Allowed (allow list for deposits)

    function isAllowed(address user) public view returns (bool) {
        return user == owner() || isManager(user) || _allowed[user];
    }

    function setAllowed(address user, bool _isManager) external requiresAuth {
        _allowed[user] = _isManager;
        emit AllowedUpdate(user, _isManager);
    }

    function bulkAllow(address[] memory users) external requiresAuth {
        for (uint256 i; i < users.length; i++) {
            _allowed[users[i]] = true;
            emit AllowedUpdate(users[i], true);
        }
    }

    modifier requireAllow() {
        require(_isPublic || isAllowed(msg.sender), "Vault: NOT_ON_ALLOW_LIST");
        _;
    }

    mapping(address => bool) private _managers;

    // GOVERNANCE - MANAGER
    function isManager(address user) public view returns (bool) {
        return _managers[user];
    }

    function setManager(address user, bool _isManager) public onlyOwner {
        _managers[user] = _isManager;
        emit ManagerUpdate(user, _isManager);
    }

    function isPublic() external view returns (bool) {
        return _isPublic;
    }

    function setPublic(bool isPublic_) external requiresAuth {
        _isPublic = isPublic_;
        emit SetPublic(isPublic_);
    }

    /*///////////////////////////////////////////////////////////////
                           FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The percentage of profit recognized each harvest to reserve as fees.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public feePercent;

    /// @notice Emitted when the fee percentage is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newFeePercent The new fee percentage.
    event FeePercentUpdated(address indexed user, uint256 newFeePercent);

    /// @notice Sets a new fee percentage.
    /// @param newFeePercent The new fee percentage.
    function setFeePercent(uint256 newFeePercent) public onlyOwner {
        // A fee percentage over 100% doesn't make sense.
        require(newFeePercent <= 1e18, "FEE_TOO_HIGH");

        // Update the fee percentage.
        feePercent = newFeePercent;

        emit FeePercentUpdated(msg.sender, newFeePercent);
    }

    /*///////////////////////////////////////////////////////////////
                        HARVEST CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the harvest window is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newHarvestWindow The new harvest window.
    event HarvestWindowUpdated(address indexed user, uint128 newHarvestWindow);

    /// @notice Emitted when the harvest delay is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newHarvestDelay The new harvest delay.
    event HarvestDelayUpdated(address indexed user, uint64 newHarvestDelay);

    /// @notice Emitted when the harvest delay is scheduled to be updated next harvest.
    /// @param user The authorized user who triggered the update.
    /// @param newHarvestDelay The scheduled updated harvest delay.
    event HarvestDelayUpdateScheduled(
        address indexed user,
        uint64 newHarvestDelay
    );

    /// @notice The period in seconds during which multiple harvests can occur
    /// regardless if they are taking place before the harvest delay has elapsed.
    /// @dev Long harvest windows open the Vault up to profit distribution slowdown attacks.
    uint128 public harvestWindow;

    /// @notice The period in seconds over which locked profit is unlocked.
    /// @dev Cannot be 0 as it opens harvests up to sandwich attacks.
    uint64 public harvestDelay;

    /// @notice The value that will replace harvestDelay next harvest.
    /// @dev In the case that the next delay is 0, no update will be applied.
    uint64 public nextHarvestDelay;

    /// @notice Sets a new harvest window.
    /// @param newHarvestWindow The new harvest window.
    /// @dev The Vault's harvestDelay must already be set before calling.
    function setHarvestWindow(uint128 newHarvestWindow) public onlyOwner {
        // A harvest window longer than the harvest delay doesn't make sense.
        require(newHarvestWindow <= harvestDelay, "WINDOW_TOO_LONG");

        // Update the harvest window.
        harvestWindow = newHarvestWindow;

        emit HarvestWindowUpdated(msg.sender, newHarvestWindow);
    }

    /// @notice Sets a new harvest delay.
    /// @param newHarvestDelay The new harvest delay to set.
    /// @dev If the current harvest delay is 0, meaning it has not
    /// been set before, it will be updated immediately, otherwise
    /// it will be scheduled to take effect after the next harvest.
    function setHarvestDelay(uint64 newHarvestDelay) public onlyOwner {
        // A harvest delay of 0 makes harvests vulnerable to sandwich attacks.
        require(newHarvestDelay != 0, "DELAY_CANNOT_BE_ZERO");

        // A harvest delay longer than 1 year doesn't make sense.
        require(newHarvestDelay <= 365 days, "DELAY_TOO_LONG");

        // If the harvest delay is 0, meaning it has not been set before:
        if (harvestDelay == 0) {
            // We'll apply the update immediately.
            harvestDelay = newHarvestDelay;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        } else {
            // We'll apply the update next harvest.
            nextHarvestDelay = newHarvestDelay;

            emit HarvestDelayUpdateScheduled(msg.sender, newHarvestDelay);
        }
    }

    /*///////////////////////////////////////////////////////////////
                       TARGET FLOAT CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice The desired percentage of the Vault's holdings to keep as float.
    /// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
    uint256 public targetFloatPercent;

    /// @notice Emitted when the target float percentage is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newTargetFloatPercent The new target float percentage.
    event TargetFloatPercentUpdated(
        address indexed user,
        uint256 newTargetFloatPercent
    );

    /// @notice Set a new target float percentage.
    /// @param newTargetFloatPercent The new target float percentage.
    function setTargetFloatPercent(uint256 newTargetFloatPercent)
        external
        onlyOwner
    {
        // A target float percentage over 100% doesn't make sense.
        require(newTargetFloatPercent <= 1e18, "TARGET_TOO_HIGH");

        // Update the target float percentage.
        targetFloatPercent = newTargetFloatPercent;

        emit TargetFloatPercentUpdated(msg.sender, newTargetFloatPercent);
    }

    /*///////////////////////////////////////////////////////////////
                   UNDERLYING IS WETH CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Whether the Vault should treat the underlying token as WETH compatible.
    /// @dev If enabled the Vault will allow trusting strategies that accept Ether.
    bool public underlyingIsWETH;

    /// @notice Emitted when whether the Vault should treat the underlying as WETH is updated.
    /// @param user The authorized user who triggered the update.
    /// @param newUnderlyingIsWETH Whether the Vault nows treats the underlying as WETH.
    event UnderlyingIsWETHUpdated(
        address indexed user,
        bool newUnderlyingIsWETH
    );

    /// @notice Sets whether the Vault treats the underlying as WETH.
    /// @param newUnderlyingIsWETH Whether the Vault should treat the underlying as WETH.
    /// @dev The underlying token must have 18 decimals, to match Ether's decimal scheme.
    function setUnderlyingIsWETH(bool newUnderlyingIsWETH) external onlyOwner {
        // Ensure the underlying token's decimals match ETH.
        require(
            !newUnderlyingIsWETH || ERC20(address(UNDERLYING)).decimals() == 18,
            "WRONG_DECIMALS"
        );

        // Update whether the Vault treats the underlying as WETH.
        underlyingIsWETH = newUnderlyingIsWETH;

        emit UnderlyingIsWETHUpdated(msg.sender, newUnderlyingIsWETH);
    }

    /*///////////////////////////////////////////////////////////////
                          STRATEGY STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
    /// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
    uint256 public totalStrategyHoldings;

    /// @dev Packed struct of strategy data.
    /// @param trusted Whether the strategy is trusted.
    /// @param balance The amount of underlying tokens held in the strategy.
    struct StrategyData {
        // Used to determine if the Vault will operate on a strategy.
        bool trusted;
        // Used to determine profit and loss during harvests of the strategy.
        uint248 balance;
    }

    /// @notice Maps strategies to data the Vault holds on them.
    mapping(Strategy => StrategyData) public getStrategyData;

    /*///////////////////////////////////////////////////////////////
                             HARVEST STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
    /// @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
    uint64 public lastHarvestWindowStart;

    /// @notice A timestamp representing when the most recent harvest occurred.
    uint64 public lastHarvest;

    /// @notice The amount of locked profit at the end of the last harvest.
    uint128 public maxLockedProfit;

    /*///////////////////////////////////////////////////////////////
                        WITHDRAWAL QUEUE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice An ordered array of strategies representing the withdrawal queue.
    /// @dev The queue is processed in descending order, meaning the last index will be withdrawn from first.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are filtered out when encountered at
    /// withdrawal time, not validated upfront, meaning the queue may not reflect the "true" set used for withdrawals.
    Strategy[] public withdrawalQueue;

    /// @notice Gets the full withdrawal queue.
    /// @return An ordered array of strategies representing the withdrawal queue.
    /// @dev This is provided because Solidity converts public arrays into index getters,
    /// but we need a way to allow external contracts and users to access the whole array.
    function getWithdrawalQueue() external view returns (Strategy[] memory) {
        return withdrawalQueue;
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful deposit.
    /// @param user The address that deposited into the Vault.
    /// @param underlyingAmount The amount of underlying tokens that were deposited.
    event Deposit(address indexed user, uint256 underlyingAmount);

    /// @notice Emitted after a successful withdrawal.
    /// @param user The address that withdrew from the Vault.
    /// @param underlyingAmount The amount of underlying tokens that were withdrawn.
    event Withdraw(address indexed user, uint256 underlyingAmount);

    /// @notice Deposit a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of the underlying token to deposit.
    function deposit(uint256 underlyingAmount) external requireAllow {
        // you should not be able to deposit funds over the tvl limit
        require(
            underlyingAmount + totalHoldings() <= getMaxTvl(),
            "OVER_MAX_TVL"
        );

        // Determine the equivalent amount of rvTokens and mint them.
        // use deposit lock here (add locked loss to inflate share price)
        _mint(
            msg.sender,
            underlyingAmount.fdiv(exchangeRateLock(PnlLock.Deposit), BASE_UNIT)
        );

        emit Deposit(msg.sender, underlyingAmount);

        // Transfer in underlying tokens from the user.
        // This will revert if the user does not have the amount specified.
        UNDERLYING.safeTransferFrom(
            msg.sender,
            address(this),
            underlyingAmount
        );
    }

    /// @notice Withdraw a specific amount of underlying tokens.
    /// @param underlyingAmount The amount of underlying tokens to withdraw.
    function withdraw(uint256 underlyingAmount) external nonReentrant {
        // Determine the equivalent amount of rvTokens and burn them.
        // This will revert if the user does not have enough rvTokens.
        // use withdraw lock (subtrackt lockedProfits do deflate share price)
        _burn(
            msg.sender,
            underlyingAmount.fdiv(exchangeRateLock(PnlLock.Withdraw), BASE_UNIT)
        );

        emit Withdraw(msg.sender, underlyingAmount);

        // Withdraw from strategies if needed and transfer.
        transferUnderlyingTo(msg.sender, underlyingAmount);
    }

    /// @notice Redeem a specific amount of rvTokens for underlying tokens.
    /// @param rvTokenAmount The amount of rvTokens to redeem for underlying tokens.
    function redeem(uint256 rvTokenAmount) external nonReentrant {
        // Determine the equivalent amount of underlying tokens.
        uint256 underlyingAmount = rvTokenAmount.fmul(
            exchangeRateLock(PnlLock.Withdraw),
            BASE_UNIT
        );

        // Burn the provided amount of rvTokens.
        // This will revert if the user does not have enough rvTokens.
        _burn(msg.sender, rvTokenAmount);

        emit Withdraw(msg.sender, underlyingAmount);
        // Withdraw from strategies if needed and transfer.
        transferUnderlyingTo(msg.sender, underlyingAmount);
    }

    /// @dev Transfers a specific amount of underlying tokens held in strategies and/or float to a recipient.
    /// @dev Only withdraws from strategies if needed and maintains the target float percentage if possible.
    /// @param recipient The user to transfer the underlying tokens to.
    /// @param underlyingAmount The amount of underlying tokens to transfer.
    function transferUnderlyingTo(address recipient, uint256 underlyingAmount)
        internal
    {
        // Get the Vault's floating balance.
        uint256 float = totalFloat();

        // If the amount is greater than the float, withdraw from strategies.
        if (underlyingAmount > float) {
            // Compute the amount needed to reach our target float percentage.
            // use withdraw lock here because we're withdrawing
            uint256 floatMissingForTarget = (totalHoldingsLock(
                PnlLock.Withdraw
            ) - underlyingAmount).fmul(targetFloatPercent, 1e18);

            // Compute the bare minimum amount we need for this withdrawal.
            uint256 floatMissingForWithdrawal = underlyingAmount - float;

            // Pull enough to cover the withdrawal and reach our target float percentage.
            pullFromWithdrawalQueue(
                floatMissingForWithdrawal + floatMissingForTarget,
                float
            );
        }

        // Transfer the provided amount of underlying tokens.
        UNDERLYING.safeTransfer(recipient, underlyingAmount);
    }

    /*///////////////////////////////////////////////////////////////
                        VAULT ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a user's Vault balance in underlying tokens.
    /// @param user The user to get the underlying balance of.
    /// @return The user's Vault balance in underlying tokens.
    function balanceOfUnderlying(address user) external view returns (uint256) {
        return
            balanceOf(user).fmul(exchangeRateLock(PnlLock.Withdraw), BASE_UNIT);
    }

    /// @notice Returns the amount of underlying tokens an rvToken can be redeemed for.
    /// @return The amount of underlying tokens an rvToken can be redeemed for.
    function exchangeRate() public view returns (uint256) {
        return exchangeRateLock(PnlLock.None);
    }

    /// @notice Returns the amount of underlying tokens an rvToken can be redeemed for.
    /// @return The amount of underlying tokens an rvToken can be redeemed for.
    function exchangeRateLock(PnlLock lock) public view returns (uint256) {
        // Get the total supply of rvTokens.
        uint256 rvTokenSupply = totalSupply();

        // If there are no rvTokens in circulation, return an exchange rate of 1:1.
        if (rvTokenSupply == 0) return BASE_UNIT;

        // Calculate the exchange rate by dividing the total holdings by the rvToken supply.
        return totalHoldingsLock(lock).fdiv(rvTokenSupply, BASE_UNIT);
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    function totalHoldings() public view returns (uint256) {
        return totalHoldingsLock(PnlLock.None);
    }

    /// @notice Calculates the total amount of underlying tokens the Vault holds.
    /// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
    function totalHoldingsLock(PnlLock lock)
        public
        view
        returns (uint256 totalUnderlyingHeld)
    {
        unchecked {
            // this could overflow - in this case withdraw should not be possible anyway
            if (lock == PnlLock.None)
                return
                    totalStrategyHoldings - lossSinceHarvest() + totalFloat();
        }

        (uint256 lockedProfit_, uint256 lockedLoss_) = lockedProfit();
        // this could overflow - in this case withdraw should not be possible anyway
        if (lock == PnlLock.Withdraw)
            return
                totalStrategyHoldings -
                lockedProfit_ -
                lossSinceHarvest() +
                totalFloat();

        unchecked {
            // Cannot underflow as locked profit can't exceed total strategy holdings.
            // inflate the total holdings by lockedLoss as a saftey measure
            if (lock == PnlLock.Deposit)
                return totalStrategyHoldings + lockedLoss_ + totalFloat();
        }
    }

    /// @notice Calculates the current amount of locked profit.
    /// @return The current amount of locked profit.

    /// @notice Calculates the current amount of locked profit.
    /// @return The current amount of locked profit.
    function lockedProfit() public view returns (uint256, uint256) {
        // Get the last harvest and harvest delay.
        uint256 previousHarvest = lastHarvest;
        uint256 harvestInterval = harvestDelay;

        unchecked {
            // If the harvest delay has passed, there is no locked profit.
            // Cannot overflow on human timescales since harvestInterval is capped.
            if (block.timestamp >= previousHarvest + harvestInterval)
                return (0, 0);

            // Get the maximum amount we could return.
            uint256 maximumLockedProfit = maxLockedProfit;
            uint256 maximumLockedLoss = maxLockedLoss;

            // Compute how much profit remains locked based on the last harvest and harvest delay.
            // It's impossible for the previous harvest to be in the future, so this will never underflow.
            return (
                maximumLockedProfit -
                    (maximumLockedProfit *
                        (block.timestamp - previousHarvest)) /
                    harvestInterval,
                maximumLockedLoss -
                    (maximumLockedLoss * (block.timestamp - previousHarvest)) /
                    harvestInterval
            );
        }
    }

    /// @notice Returns the amount of underlying tokens that idly sit in the Vault.
    /// @return The amount of underlying tokens that sit idly in the Vault.
    function totalFloat() public view returns (uint256) {
        return UNDERLYING.balanceOf(address(this));
    }

    /*///////////////////////////////////////////////////////////////
                             HARVEST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a successful harvest.
    /// @param user The authorized user who triggered the harvest.
    /// @param strategies The trusted strategies that were harvested.
    event Harvest(address indexed user, Strategy[] strategies);

    /// @notice Harvest a set of trusted strategies.
    /// @param strategies The trusted strategies to harvest.
    /// @dev Will always revert if called outside of an active
    /// harvest window or before the harvest delay has passed.
    function harvest(Strategy[] calldata strategies) external requiresAuth {
        // If this is the first harvest after the last window:
        if (block.timestamp >= lastHarvest + harvestDelay) {
            // Set the harvest window's start timestamp.
            // Cannot overflow 64 bits on human timescales.
            lastHarvestWindowStart = uint64(block.timestamp);
        } else {
            // We know this harvest is not the first in the window so we need to ensure it's within it.
            require(
                block.timestamp <= lastHarvestWindowStart + harvestWindow,
                "BAD_HARVEST_TIME"
            );
        }

        // Get the Vault's current total strategy holdings.
        uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

        // Used to store the total profit accrued by the strategies.
        uint256 totalProfitAccrued;
        uint256 totalLoss;

        // Used to store the new total strategy holdings after harvesting.
        uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

        // Will revert if any of the specified strategies are untrusted.
        for (uint256 i = 0; i < strategies.length; i++) {
            // Get the strategy at the current index.
            Strategy strategy = strategies[i];

            // If an untrusted strategy could be harvested a malicious user could use
            // a fake strategy that over-reports holdings to manipulate the exchange rate.
            require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

            // Get the strategy's previous and current balance.
            uint256 balanceLastHarvest = getStrategyData[strategy].balance;
            uint256 balanceThisHarvest = strategy.balanceOfUnderlying(
                address(this)
            );

            // Update the strategy's stored balance. Cast overflow is unrealistic.
            getStrategyData[strategy].balance = balanceThisHarvest
                .safeCastTo248();

            // Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
            // We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
            newTotalStrategyHoldings =
                newTotalStrategyHoldings +
                balanceThisHarvest -
                balanceLastHarvest;

            unchecked {
                // Update the total profit accrued while counting losses as zero profit.
                // Cannot overflow as we already increased total holdings without reverting.
                if (balanceThisHarvest > balanceLastHarvest) {
                    totalProfitAccrued +=
                        balanceThisHarvest -
                        balanceLastHarvest; // Profits since last harvest.
                } else {
                    // If the strategy registered a net loss we add it to totalLoss.
                    totalLoss += balanceLastHarvest - balanceThisHarvest;
                }
            }
        }

        // Compute fees as the fee percent multiplied by the profit.
        uint256 feesAccrued = totalProfitAccrued.fmul(feePercent, 1e18);

        // If we accrued any fees, mint an equivalent amount of rvTokens.
        // Authorized users can claim the newly minted rvTokens via claimFees.
        _mint(address(this), feesAccrued.fdiv(exchangeRate(), BASE_UNIT));

        // Update max unlocked profit based on any remaining locked profit plus new profit.
        (uint256 lockedProfit_, uint256 lockedLoss_) = lockedProfit();
        maxLockedProfit = (lockedProfit_ + totalProfitAccrued - feesAccrued)
            .safeCastTo128();
        maxLockedLoss = (lockedLoss_ + totalLoss).safeCastTo128();

        // Set strategy holdings to our new total.
        totalStrategyHoldings = newTotalStrategyHoldings;

        // Update the last harvest timestamp.
        // Cannot overflow on human timescales.
        lastHarvest = uint64(block.timestamp);

        emit Harvest(msg.sender, strategies);

        // Get the next harvest delay.
        uint64 newHarvestDelay = nextHarvestDelay;

        // If the next harvest delay is not 0:
        if (newHarvestDelay != 0) {
            // Update the harvest delay.
            harvestDelay = newHarvestDelay;

            // Reset the next harvest delay.
            nextHarvestDelay = 0;

            emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
        }
    }

    /// @notice Compute total for the strategies since last harvest.
    /// @dev It is necessary to include this when computing the withdrawal exchange rate
    function lossSinceHarvest() internal view returns (uint256 loss) {
        uint256 totalCurrentHoldings;
        // use this instead of totalStrategyHoldings because some strategies with balances may not be in queue
        uint256 balanceInQueue;

        // this assumes all strategies with balance are in the withdrawal queue
        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            // Get the strategy at the current index.
            Strategy strategy = withdrawalQueue[i];

            // If an untrusted strategy could be harvested a malicious user could use
            if (
                !getStrategyData[strategy].trusted ||
                getStrategyData[strategy].balance == 0
            ) continue;

            balanceInQueue = balanceInQueue + getStrategyData[strategy].balance;

            totalCurrentHoldings =
                totalCurrentHoldings +
                strategy.balanceOfUnderlying(address(this));
        }

        // Update strategy holdings
        loss = balanceInQueue > totalCurrentHoldings
            ? balanceInQueue - totalCurrentHoldings
            : 0;
    }

    /*///////////////////////////////////////////////////////////////
                    MAX TVL LOGIC
    //////////////////////////////////////////////////////////////*/

    function getMaxTvl() public view returns (uint256 maxTvl) {
        return min(_maxTvl, _stratMaxTvl);
    }

    event MaxTvlUpdated(uint256 maxTvl);

    function setMaxTvl(uint256 maxTvl_) public requiresAuth {
        _maxTvl = maxTvl_;
        emit MaxTvlUpdated(min(_maxTvl, _stratMaxTvl));
    }

    // TODO should this just be a view computed on demand?
    function updateStratTvl() public requiresAuth returns (uint256 maxTvl) {
        for (uint256 i; i < withdrawalQueue.length; i++) {
            Strategy strategy = withdrawalQueue[i];
            uint256 stratTvl = strategy.getMaxTvl();
            // don't let new max overflow
            unchecked {
                maxTvl = maxTvl > maxTvl + stratTvl
                    ? maxTvl
                    : maxTvl + stratTvl;
            }
        }
        _stratMaxTvl = maxTvl;
        emit MaxTvlUpdated(min(_maxTvl, _stratMaxTvl));
    }

    /*///////////////////////////////////////////////////////////////
                    STRATEGY DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after the Vault deposits into a strategy contract.
    /// @param user The authorized user who triggered the deposit.
    /// @param strategy The strategy that was deposited into.
    /// @param underlyingAmount The amount of underlying tokens that were deposited.
    event StrategyDeposit(
        address indexed user,
        Strategy indexed strategy,
        uint256 underlyingAmount
    );

    /// @notice Emitted after the Vault withdraws funds from a strategy contract.
    /// @param user The authorized user who triggered the withdrawal.
    /// @param strategy The strategy that was withdrawn from.
    /// @param underlyingAmount The amount of underlying tokens that were withdrawn.
    event StrategyWithdrawal(
        address indexed user,
        Strategy indexed strategy,
        uint256 underlyingAmount
    );

    /// @notice Deposit a specific amount of float into a trusted strategy.
    /// @param strategy The trusted strategy to deposit into.
    /// @param underlyingAmount The amount of underlying tokens in float to deposit.
    function depositIntoStrategy(Strategy strategy, uint256 underlyingAmount)
        public
        requiresAuth
    {
        // A strategy must be trusted before it can be deposited into.
        require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

        // We don't allow depositing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "AMOUNT_CANNOT_BE_ZERO");

        emit StrategyDeposit(msg.sender, strategy, underlyingAmount);

        // Increase totalStrategyHoldings to account for the deposit.
        totalStrategyHoldings += underlyingAmount;
        unchecked {
            // Without this the next harvest would count the deposit as profit.
            // Cannot overflow as the balance of one strategy can't exceed the sum of all.
            getStrategyData[strategy].balance += underlyingAmount
                .safeCastTo248();
        }

        // We need to deposit differently if the strategy takes ETH.
        if (strategy.isCEther()) {
            // Unwrap the right amount of WETH.
            IWETH(payable(address(UNDERLYING))).withdraw(underlyingAmount);

            // Deposit into the strategy and assume it will revert on error.
            ETHStrategy(address(strategy)).mint{value: underlyingAmount}();
        } else {
            // Approve underlyingAmount to the strategy so we can deposit.
            UNDERLYING.safeApprove(address(strategy), underlyingAmount);

            // Deposit into the strategy and revert if it returns an error code.
            require(
                ERC20Strategy(address(strategy)).mint(underlyingAmount) == 0,
                "MINT_FAILED"
            );
        }
    }

    /// @notice Withdraw a specific amount of underlying tokens from a strategy.
    /// @param strategy The strategy to withdraw from.
    /// @param underlyingAmount  The amount of underlying tokens to withdraw.
    /// @dev Withdrawing from a strategy will not remove it from the withdrawal queue.
    function withdrawFromStrategy(Strategy strategy, uint256 underlyingAmount)
        public
        requiresAuth
        nonReentrant
    {
        // A strategy must be trusted before it can be withdrawn from.
        require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

        // We don't allow withdrawing 0 to prevent emitting a useless event.
        require(underlyingAmount != 0, "AMOUNT_CANNOT_BE_ZERO");

        // Without this the next harvest would count the withdrawal as a loss.
        getStrategyData[strategy].balance -= underlyingAmount.safeCastTo248();

        unchecked {
            // Decrease totalStrategyHoldings to account for the withdrawal.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= underlyingAmount;
        }

        emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

        // Withdraw from the strategy and revert if it returns an error code.
        require(
            strategy.redeemUnderlying(underlyingAmount) == 0,
            "REDEEM_FAILED"
        );

        // Wrap the withdrawn Ether into WETH if necessary.
        if (strategy.isCEther())
            IWETH(payable(address(UNDERLYING))).deposit{
                value: underlyingAmount
            }();
    }

    /*///////////////////////////////////////////////////////////////
                      STRATEGY TRUST/DISTRUST LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a strategy is set to trusted.
    /// @param user The authorized user who trusted the strategy.
    /// @param strategy The strategy that became trusted.
    event StrategyTrusted(address indexed user, Strategy indexed strategy);

    /// @notice Emitted when a strategy is set to untrusted.
    /// @param user The authorized user who untrusted the strategy.
    /// @param strategy The strategy that became untrusted.
    event StrategyDistrusted(address indexed user, Strategy indexed strategy);

    /// @notice Helper method to add strategy and push it to the que in one tx.
    /// @param strategy The strategy to add.
    function addStrategy(Strategy strategy) public onlyOwner {
        trustStrategy(strategy);
        pushToWithdrawalQueue(strategy);
        updateStratTvl();
    }

    /// @notice Helper method to migrate strategy to a new implementation.
    /// @param prevStrategy The strategy to remove.
    /// @param newStrategy The strategy to add.
    // slither-disable-next-line reentrancy-eth
    function migrateStrategy(
        Strategy prevStrategy,
        Strategy newStrategy,
        uint256 queueIndex
    ) public onlyOwner {
        trustStrategy(newStrategy);

        if (queueIndex < withdrawalQueue.length)
            replaceWithdrawalQueueIndex(queueIndex, newStrategy);
        else pushToWithdrawalQueue(newStrategy);

        // make sure to call harvest before migrate
        uint256 stratBalance = getStrategyData[prevStrategy].balance;
        if (stratBalance > 0) {
            withdrawFromStrategy(prevStrategy, stratBalance);
            depositIntoStrategy(
                newStrategy,
                // we may end up with slightly less balance because of tx costs
                min(UNDERLYING.balanceOf(address(this)), stratBalance)
            );
        }
        distrustStrategy(prevStrategy);
    }

    /// @notice Stores a strategy as trusted, enabling it to be harvested.
    /// @param strategy The strategy to make trusted.
    function trustStrategy(Strategy strategy) public onlyOwner {
        // Ensure the strategy accepts the correct underlying token.
        // If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
        require(
            strategy.isCEther()
                ? underlyingIsWETH
                : ERC20Strategy(address(strategy)).underlying() == UNDERLYING,
            "WRONG_UNDERLYING"
        );

        // Store the strategy as trusted.
        getStrategyData[strategy].trusted = true;

        emit StrategyTrusted(msg.sender, strategy);
    }

    /// @notice Stores a strategy as untrusted, disabling it from being harvested.
    /// @param strategy The strategy to make untrusted.
    function distrustStrategy(Strategy strategy) public onlyOwner {
        // Store the strategy as untrusted.
        getStrategyData[strategy].trusted = false;

        emit StrategyDistrusted(msg.sender, strategy);
    }

    /*///////////////////////////////////////////////////////////////
                         WITHDRAWAL QUEUE LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a strategy is pushed to the withdrawal queue.
    /// @param user The authorized user who triggered the push.
    /// @param pushedStrategy The strategy pushed to the withdrawal queue.
    event WithdrawalQueuePushed(
        address indexed user,
        Strategy indexed pushedStrategy
    );

    /// @notice Emitted when a strategy is popped from the withdrawal queue.
    /// @param user The authorized user who triggered the pop.
    /// @param poppedStrategy The strategy popped from the withdrawal queue.
    event WithdrawalQueuePopped(
        address indexed user,
        Strategy indexed poppedStrategy
    );

    /// @notice Emitted when the withdrawal queue is updated.
    /// @param user The authorized user who triggered the set.
    /// @param replacedWithdrawalQueue The new withdrawal queue.
    event WithdrawalQueueSet(
        address indexed user,
        Strategy[] replacedWithdrawalQueue
    );

    /// @notice Emitted when an index in the withdrawal queue is replaced.
    /// @param user The authorized user who triggered the replacement.
    /// @param index The index of the replaced strategy in the withdrawal queue.
    /// @param replacedStrategy The strategy in the withdrawal queue that was replaced.
    /// @param replacementStrategy The strategy that overrode the replaced strategy at the index.
    event WithdrawalQueueIndexReplaced(
        address indexed user,
        uint256 index,
        Strategy indexed replacedStrategy,
        Strategy indexed replacementStrategy
    );

    /// @notice Emitted when an index in the withdrawal queue is replaced with the tip.
    /// @param user The authorized user who triggered the replacement.
    /// @param index The index of the replaced strategy in the withdrawal queue.
    /// @param replacedStrategy The strategy in the withdrawal queue replaced by the tip.
    /// @param previousTipStrategy The previous tip of the queue that replaced the strategy.
    event WithdrawalQueueIndexReplacedWithTip(
        address indexed user,
        uint256 index,
        Strategy indexed replacedStrategy,
        Strategy indexed previousTipStrategy
    );

    /// @notice Emitted when the strategies at two indexes are swapped.
    /// @param user The authorized user who triggered the swap.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    /// @param newStrategy1 The strategy (previously at index2) that replaced index1.
    /// @param newStrategy2 The strategy (previously at index1) that replaced index2.
    event WithdrawalQueueIndexesSwapped(
        address indexed user,
        uint256 index1,
        uint256 index2,
        Strategy indexed newStrategy1,
        Strategy indexed newStrategy2
    );

    /// @dev Withdraw a specific amount of underlying tokens from strategies in the withdrawal queue.
    /// @param underlyingAmount The amount of underlying tokens to pull into float.
    /// @dev Automatically removes depleted strategies from the withdrawal queue.
    // slither-disable-next-line reentrancy-eth,arbitrary-send
    function pullFromWithdrawalQueue(uint256 underlyingAmount, uint256 float)
        internal
    {
        // We will update this variable as we pull from strategies.
        uint256 amountLeftToPull = underlyingAmount;

        // We'll start at the tip of the queue and traverse backwards.
        uint256 currentIndex = withdrawalQueue.length - 1;

        // Iterate in reverse so we pull from the queue in a "last in, first out" manner.
        // Will revert due to underflow if we empty the queue before pulling the desired amount.
        for (; ; currentIndex--) {
            // Get the strategy at the current queue index.
            Strategy strategy = withdrawalQueue[currentIndex];

            // Get the balance of the strategy before we withdraw from it.
            uint256 strategyBalance = getStrategyData[strategy].balance;

            // If the strategy is currently untrusted or was already depleted:
            if (!getStrategyData[strategy].trusted || strategyBalance == 0) {
                // Remove it from the queue.
                withdrawalQueue.pop();

                emit WithdrawalQueuePopped(msg.sender, strategy);

                // Move onto the next strategy.
                continue;
            }

            // We want to pull as much as we can from the strategy, but no more than we need.
            uint256 amountToPull = strategyBalance > amountLeftToPull
                ? amountLeftToPull
                : strategyBalance;

            unchecked {
                emit StrategyWithdrawal(msg.sender, strategy, amountToPull);

                // Withdraw from the strategy and revert if returns an error code.
                require(
                    strategy.redeemUnderlying(amountToPull) == 0,
                    "REDEEM_FAILED"
                );

                // Cache the Vault's balance of ETH.
                if (underlyingIsWETH) {
                    uint256 ethBalance = address(this).balance;
                    if (ethBalance != 0)
                        // If the Vault's underlying token is WETH compatible and we have some ETH, wrap it into WETH.
                        IWETH(payable(address(UNDERLYING))).deposit{
                            value: ethBalance
                        }();
                }
                // slither-disable-next-line reentrancy-events

                // the actual amount we withdraw may be less than what we tried (tx fees)
                uint256 underlyingBalance = totalFloat();
                uint256 withdrawn = underlyingBalance - float; // impossible for float to decrease
                float = underlyingBalance;

                // Compute the balance of the strategy that will remain after we withdraw.
                uint256 strategyBalanceAfterWithdrawal = strategyBalance >
                    withdrawn
                    ? strategyBalance - withdrawn
                    : 0;

                // Without this the next harvest would count the withdrawal as a loss.
                getStrategyData[strategy]
                    .balance = strategyBalanceAfterWithdrawal.safeCastTo248();

                // Adjust our goal based on how much we can pull from the strategy.
                amountLeftToPull = amountLeftToPull > withdrawn
                    ? amountLeftToPull - withdrawn
                    : 0;

                // If we fully depleted the strategy:
                if (strategyBalanceAfterWithdrawal == 0) {
                    // Remove it from the queue.
                    withdrawalQueue.pop();

                    emit WithdrawalQueuePopped(msg.sender, strategy);
                }
            }

            // If we've pulled all we need, exit the loop.
            if (amountLeftToPull == 0 || currentIndex == 0) break;
        }

        unchecked {
            // Account for the withdrawals done in the loop above.
            // Cannot underflow as the balances of some strategies cannot exceed the sum of all.
            // This assumes we revert if we haven't withdrawn enough funds
            totalStrategyHoldings -= underlyingAmount;
        }
    }

    /// @notice Pushes a single strategy to front of the withdrawal queue.
    /// @param strategy The strategy to be inserted at the front of the withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function pushToWithdrawalQueue(Strategy strategy) public requiresAuth {
        // Ensure pushing the strategy will not cause the queue to exceed its limit.
        require(
            withdrawalQueue.length < MAX_WITHDRAWAL_STACK_SIZE,
            "STACK_FULL"
        );

        // Push the strategy to the front of the queue.
        withdrawalQueue.push(strategy);

        emit WithdrawalQueuePushed(msg.sender, strategy);
    }

    /// @notice Pushes a single strategy to front of the withdrawal queue with validation.
    /// @param strategy The strategy to be inserted at the front of the withdrawal queue.
    /// @dev This is a public method to ensure admin cannot prevent withdrawals by emptying the queue
    function pushToWithdrawalQueueValidated(Strategy strategy) public {
        // Ensure pushing the strategy will not cause the queue to exceed its limit.
        require(
            withdrawalQueue.length < MAX_WITHDRAWAL_STACK_SIZE,
            "STACK_FULL"
        );
        require(getStrategyData[strategy].trusted, "NOT_TRUSTED");

        for (uint256 i = 0; i < withdrawalQueue.length; i++) {
            // strategy is already in the queue
            if (strategy == withdrawalQueue[i]) return;
        }

        // Push the strategy to the front of the queue.
        withdrawalQueue.push(strategy);

        emit WithdrawalQueuePushed(msg.sender, strategy);
    }

    /// @notice Removes duplicates or untrusted strategies.
    /// @dev This is a public method to ensure admin cannot fill the queue
    function cleanWithdrawalQueue() public {
        Strategy[] memory dirtyQueue = withdrawalQueue;
        delete withdrawalQueue;
        for (uint256 i = 0; i < dirtyQueue.length; i++) {
            Strategy strategy = dirtyQueue[i];
            if (!getStrategyData[strategy].trusted || isDuplicate(strategy))
                continue;
            withdrawalQueue.push(strategy);
        }
        emit WithdrawalQueueSet(msg.sender, withdrawalQueue);
    }

    function isDuplicate(Strategy strategy) internal view returns (bool) {
        for (uint256 j = 0; j < withdrawalQueue.length; j++)
            if (address(strategy) == address(withdrawalQueue[j])) return true;
        return false;
    }

    /// @notice Removes the strategy at the tip of the withdrawal queue.
    /// @dev Be careful, another authorized user could push a different strategy
    /// than expected to the queue while a popFromWithdrawalQueue transaction is pending.
    function popFromWithdrawalQueue() external requiresAuth {
        // Get the (soon to be) popped strategy.
        Strategy poppedStrategy = withdrawalQueue[withdrawalQueue.length - 1];

        // Pop the first strategy in the queue.
        withdrawalQueue.pop();

        emit WithdrawalQueuePopped(msg.sender, poppedStrategy);
    }

    /// @notice Sets a new withdrawal queue.
    /// @param newQueue The new withdrawal queue.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function setWithdrawalQueue(Strategy[] calldata newQueue)
        external
        requiresAuth
    {
        // Ensure the new queue is not larger than the maximum stack size.
        require(newQueue.length <= MAX_WITHDRAWAL_STACK_SIZE, "STACK_TOO_BIG");

        // Replace the withdrawal queue.
        withdrawalQueue = newQueue;

        emit WithdrawalQueueSet(msg.sender, newQueue);
    }

    /// @notice Replaces an index in the withdrawal queue with another strategy.
    /// @param index The index in the queue to replace.
    /// @param replacementStrategy The strategy to override the index with.
    /// @dev Strategies that are untrusted, duplicated, or have no balance are
    /// filtered out when encountered at withdrawal time, not validated upfront.
    function replaceWithdrawalQueueIndex(
        uint256 index,
        Strategy replacementStrategy
    ) public requiresAuth {
        // Get the (soon to be) replaced strategy.
        Strategy replacedStrategy = withdrawalQueue[index];

        // Update the index with the replacement strategy.
        withdrawalQueue[index] = replacementStrategy;

        emit WithdrawalQueueIndexReplaced(
            msg.sender,
            index,
            replacedStrategy,
            replacementStrategy
        );
    }

    /// @notice Moves the strategy at the tip of the queue to the specified index and pop the tip off the queue.
    /// @param index The index of the strategy in the withdrawal queue to replace with the tip.
    function replaceWithdrawalQueueIndexWithTip(uint256 index)
        external
        requiresAuth
    {
        // Get the (soon to be) previous tip and strategy we will replace at the index.
        Strategy previousTipStrategy = withdrawalQueue[
            withdrawalQueue.length - 1
        ];
        Strategy replacedStrategy = withdrawalQueue[index];

        // Replace the index specified with the tip of the queue.
        withdrawalQueue[index] = previousTipStrategy;

        // Remove the now duplicated tip from the array.
        withdrawalQueue.pop();

        emit WithdrawalQueueIndexReplacedWithTip(
            msg.sender,
            index,
            replacedStrategy,
            previousTipStrategy
        );
    }

    /// @notice Swaps two indexes in the withdrawal queue.
    /// @param index1 One index involved in the swap
    /// @param index2 The other index involved in the swap.
    function swapWithdrawalQueueIndexes(uint256 index1, uint256 index2)
        external
        requiresAuth
    {
        // Get the (soon to be) new strategies at each index.
        Strategy newStrategy2 = withdrawalQueue[index1];
        Strategy newStrategy1 = withdrawalQueue[index2];

        // Swap the strategies at both indexes.
        withdrawalQueue[index1] = newStrategy1;
        withdrawalQueue[index2] = newStrategy2;

        emit WithdrawalQueueIndexesSwapped(
            msg.sender,
            index1,
            index2,
            newStrategy1,
            newStrategy2
        );
    }

    /*///////////////////////////////////////////////////////////////
                         SEIZE STRATEGY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after a strategy is seized.
    /// @param user The authorized user who triggered the seize.
    /// @param strategy The strategy that was seized.
    event StrategySeized(address indexed user, Strategy indexed strategy);

    /// @notice Seizes a strategy.
    /// @param strategy The strategy to seize.
    /// @dev Intended for use in emergencies or other extraneous situations where the
    /// strategy requires interaction outside of the Vault's standard operating procedures.
    function seizeStrategy(Strategy strategy, IERC20[] calldata tokens)
        external
        nonReentrant
        requiresAuth
    {
        // Get the strategy's last reported balance of underlying tokens.
        uint256 strategyBalance = getStrategyData[strategy].balance;

        // if there are any tokens left, transfer them to owner
        Strategy(strategy).emergencyWithdraw(owner(), tokens);

        // Set the strategy's balance to 0.
        getStrategyData[strategy].balance = 0;

        // If the strategy's balance exceeds the Vault's current
        // holdings, instantly unlock any remaining locked profit.
        // use Withdraw holdings because we want to subtract lockedProfits in check
        if (strategyBalance > totalHoldingsLock(PnlLock.Withdraw))
            maxLockedProfit = 0;

        unchecked {
            // Decrease totalStrategyHoldings to account for the seize.
            // Cannot underflow as the balance of one strategy will never exceed the sum of all.
            totalStrategyHoldings -= strategyBalance;
        }

        emit StrategySeized(msg.sender, strategy);
    }

    /*///////////////////////////////////////////////////////////////
                             FEE CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted after fees are claimed.
    /// @param user The authorized user who claimed the fees.
    /// @param rvTokenAmount The amount of rvTokens that were claimed.
    event FeesClaimed(address indexed user, uint256 rvTokenAmount);

    /// @notice Claims fees accrued from harvests.
    /// @param rvTokenAmount The amount of rvTokens to claim.
    /// @dev Accrued fees are measured as rvTokens held by the Vault.
    function claimFees(uint256 rvTokenAmount) external requiresAuth {
        emit FeesClaimed(msg.sender, rvTokenAmount);

        // Transfer the provided amount of rvTokens to the caller.
        IERC20(address(this)).safeTransfer(msg.sender, rvTokenAmount);
    }

    /*///////////////////////////////////////////////////////////////
                          RECIEVE ETHER LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Required for the Vault to receive unwrapped ETH.
    receive() external payable {}

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /*///////////////////////////////////////////////////////////////
                          UPGRADE VARS
    //////////////////////////////////////////////////////////////*/

    uint256 private _maxTvl;
    uint256 private _stratMaxTvl;
    bool private _isPublic;

    /// @notice The amount of locked profit at the end of the last harvest.
    uint128 public maxLockedLoss;

    enum PnlLock {
        None,
        Deposit,
        Withdraw
    }

    uint256 public version;
}
