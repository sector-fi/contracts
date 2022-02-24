// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import "../../interfaces/uniswap/IWETH.sol";

import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

import { AllowedPermit } from "../../interfaces/AllowedPermit.sol";

import { VaultUpgradable as Vault } from "../VaultUpgradable.sol";

// import "hardhat/console.sol";

/// @title Rari Vault Router Module
/// @author Transmissions11 and JetJadeja
/// @notice Module that enables depositing ETH into WETH compatible Vaults
/// and approval-free deposits into Vaults with permit compatible underlying.
contract VaultRouterModule {
	using SafeERC20 for IERC20;
	using SafeERC20 for address;
	using FixedPointMathLib for uint256;

	/*///////////////////////////////////////////////////////////////
                              DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Deposit ETH into a WETH compatible Vault.
	/// @param vault The WETH compatible Vault to deposit into.
	function depositETHIntoVault(Vault vault) external payable {
		// Ensure the Vault's underlying is stored as WETH compatible.
		require(vault.underlyingIsWETH(), "UNDERLYING_NOT_WETH");

		// Get the Vault's underlying as WETH.
		IWETH weth = IWETH(payable(address(vault.UNDERLYING())));

		// Wrap the ETH into WETH.
		weth.deposit{ value: msg.value }();

		// Deposit and transfer the minted rvTokens back to the caller.
		depositIntoVaultForCaller(vault, IERC20(address(weth)), msg.value);
	}

	/// @notice Deposits into a Vault, transferring in its underlying token from the caller via permit.
	/// @param vault The Vault to deposit into.
	/// @param underlyingAmount The amount of underlying tokens to deposit into the Vault.
	/// @param deadline A timestamp, the block's timestamp must be less than or equal to this timestamp.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	/// @dev Use depositIntoVaultWithAllowedPermit for tokens using DAI's non-standard permit interface.
	function depositIntoVaultWithPermit(
		Vault vault,
		uint256 underlyingAmount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {
		// Get the Vault's underlying token.
		IERC20 underlying = vault.UNDERLYING();
		// Transfer in the provided amount of underlying tokens from the caller via permit.
		permitAndTransferFromCaller(underlying, underlyingAmount, deadline, v, r, s);

		// Deposit and transfer the minted rvTokens back to the caller.
		depositIntoVaultForCaller(vault, underlying, underlyingAmount);
	}

	/// @notice Deposits into a Vault, transferring in its underlying token from the caller via allowed permit.
	/// @param vault The Vault to deposit into.
	/// @param underlyingAmount The amount of underlying tokens to deposit into the Vault.
	/// @param nonce The callers's nonce, increases at each call to permit.
	/// @param expiry The timestamp at which the permit is no longer valid.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	/// @dev Alternative to depositIntoVaultWithPermit for tokens using DAI's non-standard permit interface.
	function depositIntoVaultWithAllowedPermit(
		Vault vault,
		uint256 underlyingAmount,
		uint256 nonce,
		uint256 expiry,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {
		// Get the Vault's underlying token.
		IERC20 underlying = vault.UNDERLYING();

		// Transfer in the provided amount of underlying tokens from the caller via allowed permit.
		allowedPermitAndTransferFromCaller(underlying, underlyingAmount, nonce, expiry, v, r, s);

		// Deposit and transfer the minted rvTokens back to the caller.
		depositIntoVaultForCaller(vault, underlying, underlyingAmount);
	}

	/*///////////////////////////////////////////////////////////////
                            WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Withdraw ETH from a WETH compatible Vault.
	/// @param vault The WETH compatible Vault to withdraw from.
	/// @param underlyingAmount The amount of ETH to withdraw from the Vault.
	function withdrawETHFromVault(Vault vault, uint256 underlyingAmount) external {
		// Ensure the Vault's underlying is stored as WETH compatible.
		require(vault.underlyingIsWETH(), "UNDERLYING_NOT_WETH");

		// Compute the amount of rvTokens equivalent to the underlying amount.
		// We know the Vault's base unit is 1e18 as it's required if underlyingIsWETH returns true.
		uint256 rvTokenAmount = underlyingAmount.fdiv(vault.exchangeRate(), 1e18);

		// Transfer in the equivalent amount of rvTokens from the caller.
		IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), rvTokenAmount);

		// Withdraw from the Vault.
		vault.withdraw(underlyingAmount);

		// Unwrap the withdrawn amount of WETH and transfer it to the caller.
		unwrapAndTransfer(IWETH(payable(address(vault.UNDERLYING()))), underlyingAmount);
	}

	/// @notice Withdraw ETH from a WETH compatible Vault.
	/// @param vault The WETH compatible Vault to withdraw from.
	/// @param underlyingAmount The amount of ETH to withdraw from the Vault.
	/// @param deadline A timestamp, the block's timestamp must be less than or equal to this timestamp.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	function withdrawETHFromVaultWithPermit(
		Vault vault,
		uint256 underlyingAmount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {
		// Ensure the Vault's underlying is stored as WETH compatible.
		require(vault.underlyingIsWETH(), "UNDERLYING_NOT_WETH");

		// Compute the amount of rvTokens equivalent to the underlying amount.
		// We know the Vault's base unit is 1e18 as it's required if underlyingIsWETH returns true.
		uint256 rvTokenAmount = underlyingAmount.fdiv(vault.exchangeRate(), 1e18);

		// Transfer in the equivalent amount of rvTokens from the caller via permit.
		permitAndTransferFromCaller(IERC20(address(vault)), rvTokenAmount, deadline, v, r, s);

		// Withdraw from the Vault.
		vault.withdraw(underlyingAmount);

		// Unwrap the withdrawn amount of WETH and transfer it to the caller.
		unwrapAndTransfer(IWETH(payable(address(vault.UNDERLYING()))), underlyingAmount);
	}

	/*///////////////////////////////////////////////////////////////
                              REDEEM LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Redeem ETH from a WETH compatible Vault.
	/// @param vault The WETH compatible Vault to redeem from.
	/// @param rvTokenAmount The amount of rvTokens to withdraw from the Vault.
	function redeemETHFromVault(Vault vault, uint256 rvTokenAmount) external {
		// Ensure the Vault's underlying is stored as WETH compatible.
		require(vault.underlyingIsWETH(), "UNDERLYING_NOT_WETH");

		// Transfer in the provided amount of rvTokens from the caller.
		IERC20(address(vault)).safeTransferFrom(msg.sender, address(this), rvTokenAmount);

		// Redeem the rvTokens.
		vault.redeem(rvTokenAmount);

		// Get the Vault's underlying as WETH.
		IWETH weth = IWETH(payable(address(vault.UNDERLYING())));

		// Unwrap all our WETH and transfer it to the caller.
		unwrapAndTransfer(weth, weth.balanceOf(address(this)));
	}

	/// @notice Redeem ETH from a WETH compatible Vault.
	/// @param vault The WETH compatible Vault to redeem from.
	/// @param rvTokenAmount The amount of rvTokens to withdraw from the Vault.
	/// @param deadline A timestamp, the block's timestamp must be less than or equal to this timestamp.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	function redeemETHFromVaultWithPermit(
		Vault vault,
		uint256 rvTokenAmount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external {
		// Ensure the Vault's underlying is stored as WETH compatible.
		require(vault.underlyingIsWETH(), "UNDERLYING_NOT_WETH");

		// Transfer in the provided amount of rvTokens from the caller via permit.
		permitAndTransferFromCaller(IERC20(address(vault)), rvTokenAmount, deadline, v, r, s);

		// Redeem the rvTokens.
		vault.redeem(rvTokenAmount);

		// Get the Vault's underlying as WETH.
		IWETH weth = IWETH(payable(address(vault.UNDERLYING())));

		// Unwrap all our WETH and transfer it to the caller.
		unwrapAndTransfer(weth, weth.balanceOf(address(this)));
	}

	/*///////////////////////////////////////////////////////////////
                          WETH UNWRAPPING LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @dev Unwraps the provided amount of WETH and transfers it to the caller.
	/// @param weth The WETH contract to withdraw the amount from.
	/// @param amount The amount of WETH to unwrap into ETH and transfer.
	function unwrapAndTransfer(IWETH weth, uint256 amount) internal {
		// Convert the WETH into ETH.
		weth.withdraw(amount);

		// Transfer the unwrapped ETH to the caller.
		safeTransferETH(msg.sender, amount);
	}

	/*///////////////////////////////////////////////////////////////
                          VAULT DEPOSIT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @dev Approves tokens, deposits them into a Vault
	/// and transfers the minted rvTokens back to the caller.
	/// @param vault The Vault to deposit into.
	/// @param underlying The underlying token the Vault accepts.
	/// @param amount The minimum amount that must be approved.
	function depositIntoVaultForCaller(
		Vault vault,
		IERC20 underlying,
		uint256 amount
	) internal {
		// If we don't have enough of the underlying token approved already:
		if (amount > underlying.allowance(address(this), address(vault))) {
			// Approve an unlimited amount of the underlying token to the Vault.
			underlying.safeApprove(address(vault), type(uint256).max);
		}

		// Deposit the underlying tokens into the Vault.
		vault.deposit(amount);

		// Transfer the newly minted rvTokens back to the caller.
		IERC20(address(vault)).safeTransfer(msg.sender, vault.balanceOf(address(this)));
	}

	/*///////////////////////////////////////////////////////////////
                              PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @dev Permits tokens from the caller and transfers them into the module.
	/// @param token The token to permit and transfer in.
	/// @param amount The amount of tokens to permit and transfer in.
	/// @param deadline A timestamp, the block's timestamp must be less than or equal to this timestamp.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	function permitAndTransferFromCaller(
		IERC20 token,
		uint256 amount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal {
		// Approve the tokens from the caller to the module via permit.
		IERC20Permit(address(token)).permit(msg.sender, address(this), amount, deadline, v, r, s);

		// Transfer the tokens from the caller to the module.
		token.safeTransferFrom(msg.sender, address(this), amount);
	}

	/// @dev Max permits tokens from the caller and transfers them into the module.
	/// @param token The token to permit and transfer in.
	/// @param amount The amount of tokens to permit and transfer in.
	/// @param nonce The callers's nonce, increases at each call to permit.
	/// @param expiry The timestamp at which the permit is no longer valid.
	/// @param v Must produce valid secp256k1 signature from the caller along with r and s.
	/// @param r Must produce valid secp256k1 signature from the caller along with v and s.
	/// @param s Must produce valid secp256k1 signature from the caller along with r and v.
	/// @dev Alternative to permitAndTransferFromCaller for tokens using DAI's non-standard permit interface.
	function allowedPermitAndTransferFromCaller(
		IERC20 token,
		uint256 amount,
		uint256 nonce,
		uint256 expiry,
		uint8 v,
		bytes32 r,
		bytes32 s
	) internal {
		// Approve the tokens from the caller to the module via DAI's non-standard permit.
		AllowedPermit(address(token)).permit(
			msg.sender,
			address(this),
			nonce,
			expiry,
			true,
			v,
			r,
			s
		);

		// Transfer the tokens from the caller to the module.
		token.safeTransferFrom(msg.sender, address(this), amount);
	}

	function safeTransferETH(address to, uint256 amount) internal {
		bool callStatus;

		assembly {
			// Transfer the ETH and store if it succeeded or not.
			callStatus := call(gas(), to, amount, 0, 0, 0, 0)
		}

		require(callStatus, "ETH_TRANSFER_FAILED");
	}

	/*///////////////////////////////////////////////////////////////
                          RECIEVE ETHER LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @dev Required for the module to receive unwrapped ETH.
	receive() external payable {}
}
