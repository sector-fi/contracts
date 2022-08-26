// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { Bytes32AddressLib } from "../libraries/Bytes32AddressLib.sol";

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

// import "hardhat/console.sol";

/// @title Scion Vault Factory
/// @author 0x0scion (based on Rari Vault Factory)
/// @notice Upgradable beacon factory which enables deploying a deterministic Vault for ERC20 token.
contract ScionVaultFactoryV0 is Ownable {
	using Bytes32AddressLib for address;
	using Bytes32AddressLib for bytes32;

	// ======== Immutable storage ========
	UpgradeableBeacon immutable beacon;

	/*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/
	event Upgrade(address implementation);

	/// @notice Creates a Vault factory.
	constructor(address _implementation) Ownable() {
		beacon = new UpgradeableBeacon(_implementation);
		emit Upgrade(_implementation);
	}

	function upgradeTo(address newImplementation) external onlyOwner {
		beacon.upgradeTo(newImplementation);
		emit Upgrade(newImplementation);
	}

	function implementation() external view returns (address) {
		return beacon.implementation();
	}

	/*///////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Emitted when a new Vault is deployed.
	/// @param vault The newly deployed Vault contract.
	/// @param underlying The underlying token the new Vault accepts.
	event VaultDeployed(BeaconProxy vault, IERC20 underlying);

	/// @notice Deploys a new Vault which supports a specific underlying token.
	/// @dev This will revert if a Vault that accepts the same underlying token has already been deployed.
	/// @param underlying The ERC20 token that the Vault should accept.
	/// @param id We may have different vaults w different credit ratings for the same asset
	/// @return vault The newly deployed Vault contract which accepts the provided underlying token.
	function deployVault(
		IERC20 underlying,
		uint256 id,
		bytes memory _callData
	) external onlyOwner returns (BeaconProxy vault) {
		// Use the CREATE2 opcode to deploy a new Vault contract.
		// This will revert if a Vault which accepts this underlying token has already
		// been deployed, as the salt would be the same and we can't deploy with it twice.

		vault = new BeaconProxy{ salt: address(underlying).fillLast12Bytes() | bytes32(id) }(
			address(beacon),
			"" // call initialization method separately to ensure address is not impacted
		);
		Address.functionCall(address(vault), _callData);

		emit VaultDeployed(vault, underlying);
	}

	/*///////////////////////////////////////////////////////////////
                            VAULT LOOKUP LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Computes a Vault's address from its accepted underlying token.
	/// @param underlying The ERC20 token that the Vault should accept.
	/// @param id We may have different vaults w different credit ratings for the same asset
	/// @return The address of a Vault which accepts the provided underlying token.
	/// @dev The Vault returned may not be deployed yet. Use isVaultDeployed to check.
	function getVaultFromUnderlying(IERC20 underlying, uint256 id)
		external
		view
		returns (BeaconProxy)
	{
		return
			BeaconProxy(
				payable(
					keccak256(
						abi.encodePacked(
							// Prefix:
							bytes1(0xFF),
							// Creator:
							address(this),
							// Salt:
							address(underlying).fillLast12Bytes() | bytes32(id),
							// Bytecode hash:
							keccak256(
								abi.encodePacked(
									// Deployment bytecode:
									type(BeaconProxy).creationCode,
									// Constructor arguments:
									abi.encode(address(beacon), "")
								)
							)
						)
					).fromLast20Bytes() // Convert the CREATE2 hash into an address.
				)
			);
	}

	/// @notice Returns if a Vault at an address has already been deployed.
	/// @param vault The address of a Vault which may not have been deployed yet.
	/// @return A boolean indicating whether the Vault has been deployed already.
	/// @dev This function is useful to check the return values of getVaultFromUnderlying,
	/// as it does not check that the Vault addresses it computes have been deployed yet.
	function isVaultDeployed(address vault) external view returns (bool) {
		return vault.code.length > 0;
	}
}
