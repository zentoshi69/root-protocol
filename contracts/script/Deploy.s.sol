// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {BitcoinAttestorRegistry} from "../src/BitcoinAttestorRegistry.sol";
import {BitcoinOwnershipOracle} from "../src/BitcoinOwnershipOracle.sol";
import {BtcSolverSettlement} from "../src/BtcSolverSettlement.sol";
import {FeeRouter} from "../src/FeeRouter.sol";
import {HoodPupOfferEscrow} from "../src/HoodPupOfferEscrow.sol";
import {HoodPups} from "../src/HoodPups.sol";
import {PayoutVault} from "../src/PayoutVault.sol";
import {PuppetCollectionRegistry} from "../src/PuppetCollectionRegistry.sol";
import {RootOwnershipRegistry} from "../src/RootOwnershipRegistry.sol";
import {TourEngine} from "../src/TourEngine.sol";

import {IBitcoinAttestorRegistry} from "../src/interfaces/IBitcoinAttestorRegistry.sol";
import {IBitcoinOwnershipOracle} from "../src/interfaces/IBitcoinOwnershipOracle.sol";
import {IHoodPupOfferEscrow} from "../src/interfaces/IHoodPupOfferEscrow.sol";
import {IHoodPups} from "../src/interfaces/IHoodPups.sol";
import {IPayoutVault} from "../src/interfaces/IPayoutVault.sol";
import {IPuppetCollectionRegistry} from "../src/interfaces/IPuppetCollectionRegistry.sol";
import {IRootOwnershipRegistry} from "../src/interfaces/IRootOwnershipRegistry.sol";
import {PuppetTypes} from "../src/types/PuppetTypes.sol";

/// @title DeployConfig
/// @notice Per-chain deployment parameters, resolved by chain id.
/// @dev Deliberately fails closed on an unknown chain. A deploy that silently succeeded against the
///      wrong network would be the most expensive possible typo, and the type system cannot catch
///      it — only a runtime guard can.
library DeployConfig {
    uint256 internal constant ROBINHOOD_MAINNET = 4663;
    uint256 internal constant ROBINHOOD_TESTNET = 46_630;
    uint256 internal constant LOCAL_ANVIL = 31_337;

    error UnsupportedChain(uint256 chainId);
    error LocalOverrideRequired(uint256 chainId);
    error ManifestNotConfigured();

    struct Config {
        string name;
        bool isProduction;
        uint64 minimumOfferDuration;
        uint64 maximumOfferDuration;
        uint256 minimumBondWei;
        uint64 reservationDuration;
        uint16 buyerSlashBps;
        uint64 tourMinimumDuration;
        uint64 tourMaximumDuration;
        uint64 tourMinimumCheckInDelay;
    }

    /// @param allowLocal Set only by tests and local scripts. Never by a testnet or mainnet run.
    function forChain(uint256 chainId, bool allowLocal) internal pure returns (Config memory c) {
        if (chainId == ROBINHOOD_MAINNET) {
            c.name = "Robinhood Chain";
            c.isProduction = true;
        } else if (chainId == ROBINHOOD_TESTNET) {
            c.name = "Robinhood Chain Testnet";
        } else if (chainId == LOCAL_ANVIL) {
            if (!allowLocal) revert LocalOverrideRequired(chainId);
            c.name = "Local (Anvil)";
        } else {
            revert UnsupportedChain(chainId);
        }

        c.minimumOfferDuration = 1 hours;
        c.maximumOfferDuration = 30 days;
        c.minimumBondWei = 0.01 ether;
        // Must comfortably exceed the verifiers' payment confirmation policy. A reservation that
        // can expire before a payment confirms loses a solver both its bond AND its BTC — see
        // docs/SOLVER_OPERATIONS.md. Raising the confirmation policy without raising this converts
        // a reorg into a wave of wrongly slashed bonds.
        c.reservationDuration = 6 hours;
        c.buyerSlashBps = 5000;
        c.tourMinimumDuration = 1 days;
        c.tourMaximumDuration = 30 days;
        c.tourMinimumCheckInDelay = 1 hours;
    }
}

/// @title Deployment
/// @notice Every address a deployment produces, in one struct so tests and scripts share a shape.
struct Deployment {
    PuppetCollectionRegistry collectionRegistry;
    BitcoinAttestorRegistry attestorRegistry;
    BitcoinOwnershipOracle oracle;
    PayoutVault payoutVault;
    RootOwnershipRegistry rootRegistry;
    FeeRouter feeRouter;
    HoodPups hoodPups;
    HoodPupOfferEscrow escrow;
    BtcSolverSettlement solver;
    TourEngine tourEngine;
}

/// @notice Everything `deployAll` needs.
/// @dev A struct rather than a dozen positional parameters: twelve arguments plus locals exceeds
///      the EVM's 16-slot stack limit, and the alternative (enabling via-IR for the whole project)
///      would slow every compile to work around one function signature.
struct DeployParams {
    address admin;
    bytes32 merkleRoot;
    bytes32 manifestHash;
    string manifestVersion;
    uint256 manifestLeafCount;
    address[] attestors;
    uint8 threshold;
    address puppetTreasury;
    address protocolTreasury;
    string baseURI;
    string contractURI;
}

/// @title DeployLib
/// @notice The deployment and role-wiring logic, factored out so the integration suite exercises
///         **exactly** the same code path a real deployment takes.
/// @dev A deployment script that tests never run is a script that breaks silently. `FullFlow.t.sol`
///      calls `deployAll` and `grantRoles` directly, so the wiring below is covered by every
///      end-to-end test rather than only by a mainnet dry run.
library DeployLib {
    error DeployerRetainsPrivilege(address contractAddress, address deployer);
    error InvalidGovernanceHandover(address timelock, address guardian, address deployer);
    error RoleMissing(address contractAddress, bytes32 role, address holder);
    error PurposeMissing(address consumer, uint8 purpose);
    error UnexpectedPurposeGranted(address consumer, uint8 purpose);
    error BtcSettlementCoordinatorMismatch(address expected, address actual);

    /// @notice Deploy all ten contracts in dependency order.
    function deployAll(DeployParams memory p, DeployConfig.Config memory cfg) internal returns (Deployment memory d) {
        // The Merkle root is immutable once deployed, so a zero here would produce a registry no
        // legitimate root could ever verify against.
        if (p.merkleRoot == bytes32(0) || p.manifestHash == bytes32(0)) revert DeployConfig.ManifestNotConfigured();

        d.collectionRegistry =
            new PuppetCollectionRegistry(p.merkleRoot, p.manifestHash, p.manifestVersion, p.manifestLeafCount);
        d.attestorRegistry = new BitcoinAttestorRegistry(p.admin, p.attestors, p.threshold, 1);
        d.oracle = new BitcoinOwnershipOracle(
            p.admin,
            IPuppetCollectionRegistry(address(d.collectionRegistry)),
            IBitcoinAttestorRegistry(address(d.attestorRegistry))
        );
        d.payoutVault = new PayoutVault(p.admin);
        d.rootRegistry = new RootOwnershipRegistry(p.admin, address(d.oracle), address(d.payoutVault));
        d.feeRouter = new FeeRouter(
            p.admin,
            IPayoutVault(address(d.payoutVault)),
            IRootOwnershipRegistry(address(d.rootRegistry)),
            p.puppetTreasury,
            p.protocolTreasury
        );
        d.hoodPups = new HoodPups(p.admin, "HoodPups", "HOOD", p.baseURI, p.contractURI);
        d.escrow = new HoodPupOfferEscrow(
            p.admin,
            address(d.collectionRegistry),
            address(d.oracle),
            address(d.hoodPups),
            address(d.feeRouter),
            address(d.payoutVault),
            address(d.rootRegistry),
            cfg.minimumOfferDuration,
            cfg.maximumOfferDuration
        );
        d.solver = new BtcSolverSettlement(
            p.admin,
            IHoodPupOfferEscrow(address(d.escrow)),
            IBitcoinOwnershipOracle(address(d.oracle)),
            IPayoutVault(address(d.payoutVault)),
            cfg.minimumBondWei,
            cfg.reservationDuration,
            cfg.buyerSlashBps,
            p.protocolTreasury
        );
        d.tourEngine = new TourEngine(
            p.admin,
            IHoodPups(address(d.hoodPups)),
            address(d.feeRouter),
            cfg.tourMinimumDuration,
            cfg.tourMaximumDuration,
            cfg.tourMinimumCheckInDelay
        );
    }

    function deployAll(
        address admin,
        DeployConfig.Config memory cfg,
        bytes32 merkleRoot,
        bytes32 manifestHash,
        string memory manifestVersion,
        uint256 manifestLeafCount,
        address[] memory attestors,
        uint8 threshold,
        address puppetTreasury,
        address protocolTreasury,
        string memory baseURI,
        string memory contractURI
    ) internal returns (Deployment memory d) {
        // The Merkle root is immutable once deployed, so a zero here would produce a registry no
        // legitimate root could ever verify against.
        if (merkleRoot == bytes32(0) || manifestHash == bytes32(0)) revert DeployConfig.ManifestNotConfigured();

        d.collectionRegistry =
            new PuppetCollectionRegistry(merkleRoot, manifestHash, manifestVersion, manifestLeafCount);
        d.attestorRegistry = new BitcoinAttestorRegistry(admin, attestors, threshold, 1);
        d.oracle = new BitcoinOwnershipOracle(
            admin,
            IPuppetCollectionRegistry(address(d.collectionRegistry)),
            IBitcoinAttestorRegistry(address(d.attestorRegistry))
        );
        d.payoutVault = new PayoutVault(admin);
        d.rootRegistry = new RootOwnershipRegistry(admin, address(d.oracle), address(d.payoutVault));
        d.feeRouter = new FeeRouter(
            admin,
            IPayoutVault(address(d.payoutVault)),
            IRootOwnershipRegistry(address(d.rootRegistry)),
            puppetTreasury,
            protocolTreasury
        );
        d.hoodPups = new HoodPups(admin, "HoodPups", "HOOD", baseURI, contractURI);
        d.escrow = new HoodPupOfferEscrow(
            admin,
            address(d.collectionRegistry),
            address(d.oracle),
            address(d.hoodPups),
            address(d.feeRouter),
            address(d.payoutVault),
            address(d.rootRegistry),
            cfg.minimumOfferDuration,
            cfg.maximumOfferDuration
        );
        d.solver = new BtcSolverSettlement(
            admin,
            IHoodPupOfferEscrow(address(d.escrow)),
            IBitcoinOwnershipOracle(address(d.oracle)),
            IPayoutVault(address(d.payoutVault)),
            cfg.minimumBondWei,
            cfg.reservationDuration,
            cfg.buyerSlashBps,
            protocolTreasury
        );
        d.tourEngine = new TourEngine(
            admin,
            IHoodPups(address(d.hoodPups)),
            address(d.feeRouter),
            cfg.tourMinimumDuration,
            cfg.tourMaximumDuration,
            cfg.tourMinimumCheckInDelay
        );
    }

    /// @notice Grant exactly the roles the protocol needs, and nothing more.
    /// @dev Mirrors the table in `docs/DEPLOYMENT.md`. Every grant here is load-bearing; anything
    ///      beyond this list is an unexpected privilege and `verifyRoles` will not know about it.
    function grantRoles(Deployment memory d) internal {
        // Oracle consumers: only protocol contracts may burn an authorization. Public callers get
        // the verify/hash views, so nobody can front-run the escrow and grief a valid claim.
        //
        // The role alone is NOT sufficient. The oracle keeps a per-consumer PURPOSE allowlist that
        // fails closed, so a consumer with the role but an empty mask can consume nothing. That
        // separation is deliberate and worth preserving: it stops the escrow consuming a
        // ROOT_INVALIDATE (which would burn a Root's ownership epoch) and stops the root registry
        // consuming a PAID_EVM_MINT (which would burn a buyer's settlement). The role says "you may
        // consume"; the mask says "you may consume THESE".
        //
        // grantOwnershipConsumer sets both in one call, so the two can never drift apart.
        uint8[] memory escrowPurposes = new uint8[](3);
        escrowPurposes[0] = uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT);
        escrowPurposes[1] = uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT);
        escrowPurposes[2] = uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST);
        d.oracle.grantOwnershipConsumer(address(d.escrow), escrowPurposes);

        // The registry binds new owners and nothing else. Notably NOT any mint purpose.
        uint8[] memory registryPurposes = new uint8[](1);
        registryPurposes[0] = uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND);
        d.oracle.grantOwnershipConsumer(address(d.rootRegistry), registryPurposes);

        d.oracle.grantRole(d.oracle.PAYMENT_CONSUMER_ROLE(), address(d.solver));
        d.oracle.grantRole(d.oracle.ROOT_SPEND_CONSUMER_ROLE(), address(d.rootRegistry));

        // Vault creditors: the three contracts that create ETH obligations.
        d.payoutVault.grantRole(d.payoutVault.CREDITOR_ROLE(), address(d.feeRouter));
        d.payoutVault.grantRole(d.payoutVault.CREDITOR_ROLE(), address(d.escrow));
        d.payoutVault.grantRole(d.payoutVault.CREDITOR_ROLE(), address(d.solver));
        d.payoutVault.grantRole(d.payoutVault.ROOT_RELEASER_ROLE(), address(d.rootRegistry));

        d.rootRegistry.grantRole(d.rootRegistry.MINT_RECORDER_ROLE(), address(d.escrow));
        d.feeRouter.grantRole(d.feeRouter.ROUTER_CALLER_ROLE(), address(d.escrow));
        d.hoodPups.grantRole(d.hoodPups.MINTER_ROLE(), address(d.escrow));
        d.hoodPups.grantRole(d.hoodPups.TOUR_ENGINE_ROLE(), address(d.tourEngine));
        d.escrow.grantRole(d.escrow.BTC_SETTLEMENT_ROLE(), address(d.solver));
    }

    /// @notice Assert every intended grant is present.
    /// @dev Least privilege has to be *verified*, not merely intended.
    function verifyRoles(Deployment memory d) internal view {
        _require(
            address(d.oracle),
            d.oracle.OWNERSHIP_CONSUMER_ROLE(),
            address(d.escrow),
            d.oracle.hasRole(d.oracle.OWNERSHIP_CONSUMER_ROLE(), address(d.escrow))
        );
        _require(
            address(d.oracle),
            d.oracle.OWNERSHIP_CONSUMER_ROLE(),
            address(d.rootRegistry),
            d.oracle.hasRole(d.oracle.OWNERSHIP_CONSUMER_ROLE(), address(d.rootRegistry))
        );
        _require(
            address(d.oracle),
            d.oracle.PAYMENT_CONSUMER_ROLE(),
            address(d.solver),
            d.oracle.hasRole(d.oracle.PAYMENT_CONSUMER_ROLE(), address(d.solver))
        );
        _require(
            address(d.oracle),
            d.oracle.ROOT_SPEND_CONSUMER_ROLE(),
            address(d.rootRegistry),
            d.oracle.hasRole(d.oracle.ROOT_SPEND_CONSUMER_ROLE(), address(d.rootRegistry))
        );
        _require(
            address(d.payoutVault),
            d.payoutVault.CREDITOR_ROLE(),
            address(d.feeRouter),
            d.payoutVault.hasRole(d.payoutVault.CREDITOR_ROLE(), address(d.feeRouter))
        );
        _require(
            address(d.payoutVault),
            d.payoutVault.CREDITOR_ROLE(),
            address(d.escrow),
            d.payoutVault.hasRole(d.payoutVault.CREDITOR_ROLE(), address(d.escrow))
        );
        _require(
            address(d.payoutVault),
            d.payoutVault.CREDITOR_ROLE(),
            address(d.solver),
            d.payoutVault.hasRole(d.payoutVault.CREDITOR_ROLE(), address(d.solver))
        );
        _require(
            address(d.payoutVault),
            d.payoutVault.ROOT_RELEASER_ROLE(),
            address(d.rootRegistry),
            d.payoutVault.hasRole(d.payoutVault.ROOT_RELEASER_ROLE(), address(d.rootRegistry))
        );
        _require(
            address(d.rootRegistry),
            d.rootRegistry.MINT_RECORDER_ROLE(),
            address(d.escrow),
            d.rootRegistry.hasRole(d.rootRegistry.MINT_RECORDER_ROLE(), address(d.escrow))
        );
        _require(
            address(d.feeRouter),
            d.feeRouter.ROUTER_CALLER_ROLE(),
            address(d.escrow),
            d.feeRouter.hasRole(d.feeRouter.ROUTER_CALLER_ROLE(), address(d.escrow))
        );
        _require(
            address(d.hoodPups),
            d.hoodPups.MINTER_ROLE(),
            address(d.escrow),
            d.hoodPups.hasRole(d.hoodPups.MINTER_ROLE(), address(d.escrow))
        );
        _require(
            address(d.hoodPups),
            d.hoodPups.TOUR_ENGINE_ROLE(),
            address(d.tourEngine),
            d.hoodPups.hasRole(d.hoodPups.TOUR_ENGINE_ROLE(), address(d.tourEngine))
        );
        _require(
            address(d.escrow),
            d.escrow.BTC_SETTLEMENT_ROLE(),
            address(d.solver),
            d.escrow.hasRole(d.escrow.BTC_SETTLEMENT_ROLE(), address(d.solver))
        );
        address coordinator = d.escrow.btcSettlementCoordinator();
        if (coordinator != address(d.solver)) {
            revert BtcSettlementCoordinatorMismatch(address(d.solver), coordinator);
        }

        // Purpose masks, not just roles. A deployment with the roles but empty masks would pass a
        // role-only audit and then fail on the first real settlement — which is precisely the class
        // of bug that only shows up when all ten contracts are wired together.
        _requirePurpose(d, address(d.escrow), uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT));
        _requirePurpose(d, address(d.escrow), uint8(PuppetTypes.AuthorizationPurpose.PAID_BTC_MINT));
        _requirePurpose(d, address(d.escrow), uint8(PuppetTypes.AuthorizationPurpose.SELF_CAST));
        _requirePurpose(d, address(d.rootRegistry), uint8(PuppetTypes.AuthorizationPurpose.ROOT_BIND));

        // And the separations that make the mask worth having.
        if (d.oracle.isPurposeAllowed(address(d.escrow), uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE))) {
            revert UnexpectedPurposeGranted(address(d.escrow), uint8(PuppetTypes.AuthorizationPurpose.ROOT_INVALIDATE));
        }
        if (d.oracle.isPurposeAllowed(address(d.rootRegistry), uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT))) {
            revert UnexpectedPurposeGranted(
                address(d.rootRegistry), uint8(PuppetTypes.AuthorizationPurpose.PAID_EVM_MINT)
            );
        }
    }

    function _requirePurpose(Deployment memory d, address consumer, uint8 purpose) private view {
        if (!d.oracle.isPurposeAllowed(consumer, purpose)) revert PurposeMissing(consumer, purpose);
    }

    /// @notice Hand every admin role to the timelock, then revoke the deployer's.
    /// @dev Order is load-bearing. Revoking before granting bricks administration permanently,
    ///      because these contracts are non-upgradeable and there is no recovery path. That absence
    ///      is deliberate — a recovery path is a backdoor — which is exactly why the order matters.
    function transferAdminToTimelock(Deployment memory d, address timelock, address guardian, address deployer)
        internal
    {
        if (
            timelock == address(0) || guardian == address(0) || deployer == address(0) || timelock == guardian
                || timelock == deployer || guardian == deployer || timelock.code.length == 0
                || guardian.code.length == 0
        ) {
            revert InvalidGovernanceHandover(timelock, guardian, deployer);
        }

        bytes32 admin = 0x00;

        d.attestorRegistry.grantRole(admin, timelock);
        d.oracle.grantRole(admin, timelock);
        d.payoutVault.grantRole(admin, timelock);
        d.rootRegistry.grantRole(admin, timelock);
        d.feeRouter.grantRole(admin, timelock);
        d.hoodPups.grantRole(admin, timelock);
        d.escrow.grantRole(admin, timelock);
        d.solver.grantRole(admin, timelock);
        d.tourEngine.grantRole(admin, timelock);

        // Every parameter-changing and value-recovery role belongs to the timelock. Moving only
        // DEFAULT_ADMIN_ROLE would leave the deployment EOA able to replace attestors, redirect
        // treasuries, change solver economics, mutate metadata or sweep vault excess.
        d.attestorRegistry.grantRole(d.attestorRegistry.ATTESTOR_ADMIN_ROLE(), timelock);
        d.payoutVault.grantRole(d.payoutVault.EXCESS_SWEEPER_ROLE(), timelock);
        d.feeRouter.grantRole(d.feeRouter.TREASURY_ADMIN_ROLE(), timelock);
        d.hoodPups.grantRole(d.hoodPups.METADATA_ADMIN_ROLE(), timelock);
        d.solver.grantRole(d.solver.CONFIG_ADMIN_ROLE(), timelock);
        d.tourEngine.grantRole(d.tourEngine.TOUR_ADMIN_ROLE(), timelock);

        // The guardian may pause and nothing else. A compromised guardian should cost liveness,
        // never parameters — and it deliberately cannot unpause itself.
        d.oracle.grantRole(d.oracle.PAUSER_ROLE(), guardian);
        d.payoutVault.grantRole(d.payoutVault.PAUSER_ROLE(), guardian);
        d.rootRegistry.grantRole(d.rootRegistry.PAUSER_ROLE(), guardian);
        d.hoodPups.grantRole(d.hoodPups.PAUSER_ROLE(), guardian);
        d.escrow.grantRole(d.escrow.PAUSER_ROLE(), guardian);
        d.solver.grantRole(d.solver.PAUSER_ROLE(), guardian);
        d.tourEngine.grantRole(d.tourEngine.PAUSER_ROLE(), guardian);

        // Constructors grant the deployment caller every initial operational role. Renouncing only
        // DEFAULT_ADMIN_ROLE is not a complete handover: those roles remain usable after admin is
        // gone. Remove every constructor-granted capability before dropping the final admin role.
        d.attestorRegistry.renounceRole(d.attestorRegistry.ATTESTOR_ADMIN_ROLE(), deployer);
        d.oracle.renounceRole(d.oracle.PAUSER_ROLE(), deployer);
        d.payoutVault.renounceRole(d.payoutVault.EXCESS_SWEEPER_ROLE(), deployer);
        d.payoutVault.renounceRole(d.payoutVault.PAUSER_ROLE(), deployer);
        d.rootRegistry.renounceRole(d.rootRegistry.PAUSER_ROLE(), deployer);
        d.feeRouter.renounceRole(d.feeRouter.TREASURY_ADMIN_ROLE(), deployer);
        d.hoodPups.renounceRole(d.hoodPups.METADATA_ADMIN_ROLE(), deployer);
        d.hoodPups.renounceRole(d.hoodPups.PAUSER_ROLE(), deployer);
        d.escrow.renounceRole(d.escrow.PAUSER_ROLE(), deployer);
        d.solver.renounceRole(d.solver.CONFIG_ADMIN_ROLE(), deployer);
        d.solver.renounceRole(d.solver.PAUSER_ROLE(), deployer);
        d.tourEngine.renounceRole(d.tourEngine.TOUR_ADMIN_ROLE(), deployer);
        d.tourEngine.renounceRole(d.tourEngine.PAUSER_ROLE(), deployer);

        d.attestorRegistry.renounceRole(admin, deployer);
        d.oracle.renounceRole(admin, deployer);
        d.payoutVault.renounceRole(admin, deployer);
        d.rootRegistry.renounceRole(admin, deployer);
        d.feeRouter.renounceRole(admin, deployer);
        d.hoodPups.renounceRole(admin, deployer);
        d.escrow.renounceRole(admin, deployer);
        d.solver.renounceRole(admin, deployer);
        d.tourEngine.renounceRole(admin, deployer);
    }

    /// @notice Fail if the deployer kept any constructor-granted privilege anywhere.
    /// @dev Checking only `DEFAULT_ADMIN_ROLE` is insufficient because configuration, metadata,
    ///      pausing and excess-sweep roles are independently usable after admin is relinquished.
    function assertDeployerRevoked(Deployment memory d, address deployer) internal view {
        bytes32 admin = 0x00;
        _requireRevoked(address(d.attestorRegistry), d.attestorRegistry, admin, deployer);
        _requireRevoked(
            address(d.attestorRegistry), d.attestorRegistry, d.attestorRegistry.ATTESTOR_ADMIN_ROLE(), deployer
        );
        _requireRevoked(address(d.oracle), d.oracle, admin, deployer);
        _requireRevoked(address(d.oracle), d.oracle, d.oracle.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.payoutVault), d.payoutVault, admin, deployer);
        _requireRevoked(address(d.payoutVault), d.payoutVault, d.payoutVault.EXCESS_SWEEPER_ROLE(), deployer);
        _requireRevoked(address(d.payoutVault), d.payoutVault, d.payoutVault.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.rootRegistry), d.rootRegistry, admin, deployer);
        _requireRevoked(address(d.rootRegistry), d.rootRegistry, d.rootRegistry.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.feeRouter), d.feeRouter, admin, deployer);
        _requireRevoked(address(d.feeRouter), d.feeRouter, d.feeRouter.TREASURY_ADMIN_ROLE(), deployer);
        _requireRevoked(address(d.hoodPups), d.hoodPups, admin, deployer);
        _requireRevoked(address(d.hoodPups), d.hoodPups, d.hoodPups.METADATA_ADMIN_ROLE(), deployer);
        _requireRevoked(address(d.hoodPups), d.hoodPups, d.hoodPups.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.escrow), d.escrow, admin, deployer);
        _requireRevoked(address(d.escrow), d.escrow, d.escrow.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.solver), d.solver, admin, deployer);
        _requireRevoked(address(d.solver), d.solver, d.solver.CONFIG_ADMIN_ROLE(), deployer);
        _requireRevoked(address(d.solver), d.solver, d.solver.PAUSER_ROLE(), deployer);
        _requireRevoked(address(d.tourEngine), d.tourEngine, admin, deployer);
        _requireRevoked(address(d.tourEngine), d.tourEngine, d.tourEngine.TOUR_ADMIN_ROLE(), deployer);
        _requireRevoked(address(d.tourEngine), d.tourEngine, d.tourEngine.PAUSER_ROLE(), deployer);
    }

    function _requireRevoked(address target, IAccessControl access, bytes32 role, address deployer) private view {
        if (access.hasRole(role, deployer)) revert DeployerRetainsPrivilege(target, deployer);
    }

    function _require(address target, bytes32 role, address holder, bool ok) private pure {
        if (!ok) revert RoleMissing(target, role, holder);
    }
}

/// @title Deploy
/// @notice Deploys the HoodPups protocol. Local and testnet only.
/// @dev Mainnet (4663) is refused outright rather than gated behind a flag. `docs/DEPLOYMENT.md`
///      lists thirteen launch gates — an external audit, five independent operators, an
///      independently reproduced manifest — none of which a script can check. A script that could
///      deploy mainnet would eventually deploy mainnet.
///
///      Usage:
///        forge script script/Deploy.s.sol --rpc-url $RPC --broadcast
contract Deploy is Script {
    error MainnetDeploymentRefused();
    error AttestorSetIncomplete(uint256 provided);

    function run() external {
        uint256 chainId = block.chainid;
        if (chainId == DeployConfig.ROBINHOOD_MAINNET) revert MainnetDeploymentRefused();

        DeployConfig.Config memory cfg = DeployConfig.forChain(chainId, vm.envOr("ALLOW_LOCAL_OVERRIDE", false));

        // Env reads live in helpers rather than as locals here. Fifteen live stack slots in one
        // function exceeds the EVM's limit, and splitting the reads is a smaller price than turning
        // on via-IR for the whole project to accommodate one script.
        DeployParams memory p = _readParams();
        address timelock = vm.envAddress("TIMELOCK_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        uint256 deploymentBlock = block.number;

        vm.startBroadcast();
        Deployment memory d = DeployLib.deployAll(p, cfg);
        DeployLib.grantRoles(d);
        DeployLib.transferAdminToTimelock(d, timelock, guardian, p.admin);
        vm.stopBroadcast();

        // Verified after the broadcast, so a misconfigured role matrix fails the run rather than
        // being discovered later by someone reading a block explorer.
        DeployLib.verifyRoles(d);
        DeployLib.assertDeployerRevoked(d, p.admin);

        _writeDeployment(d, chainId, deploymentBlock, timelock, guardian, p.admin);
        _report(d, cfg, chainId);
    }

    /// @notice Read every deployment parameter from the environment, failing closed on a missing one.
    /// @dev The manifest values are read rather than hard-coded so a deployment cannot commit to a
    ///      fabricated inscription set. `vm.envBytes32` reverts when unset, which is the behaviour
    ///      we want: no manifest, no deployment.
    function _readParams() private view returns (DeployParams memory p) {
        p.admin = msg.sender;
        p.merkleRoot = vm.envBytes32("MANIFEST_MERKLE_ROOT");
        p.manifestHash = vm.envBytes32("MANIFEST_HASH");
        p.manifestVersion = vm.envString("MANIFEST_VERSION");
        p.manifestLeafCount = vm.envUint("MANIFEST_LEAF_COUNT");
        p.attestors = vm.envAddress("ATTESTORS", ",");
        if (p.attestors.length < 5) revert AttestorSetIncomplete(p.attestors.length);
        p.threshold = 3;
        p.puppetTreasury = vm.envAddress("PUPPET_TREASURY");
        p.protocolTreasury = vm.envAddress("PROTOCOL_TREASURY");
        p.baseURI = vm.envOr("BASE_URI", string(""));
        p.contractURI = vm.envOr("CONTRACT_URI", string(""));
    }

    /// @notice Persist the minimum independently-verifiable deployment record consumed by
    ///         `scripts/verify-roles.mjs`. DEPLOY_COMMIT is mandatory so bytecode can be rebuilt
    ///         from the exact source revision rather than whichever checkout happens to be local.
    function _writeDeployment(
        Deployment memory d,
        uint256 chainId,
        uint256 deploymentBlock,
        address timelock,
        address guardian,
        address deployer
    ) private {
        string memory contractsJson = "contracts";
        vm.serializeAddress(contractsJson, "PuppetCollectionRegistry", address(d.collectionRegistry));
        vm.serializeAddress(contractsJson, "BitcoinAttestorRegistry", address(d.attestorRegistry));
        vm.serializeAddress(contractsJson, "BitcoinOwnershipOracle", address(d.oracle));
        vm.serializeAddress(contractsJson, "PayoutVault", address(d.payoutVault));
        vm.serializeAddress(contractsJson, "RootOwnershipRegistry", address(d.rootRegistry));
        vm.serializeAddress(contractsJson, "FeeRouter", address(d.feeRouter));
        vm.serializeAddress(contractsJson, "HoodPups", address(d.hoodPups));
        vm.serializeAddress(contractsJson, "HoodPupOfferEscrow", address(d.escrow));
        vm.serializeAddress(contractsJson, "BtcSolverSettlement", address(d.solver));
        string memory serializedContracts = vm.serializeAddress(contractsJson, "TourEngine", address(d.tourEngine));

        string memory deploymentJson = "deployment";
        vm.serializeUint(deploymentJson, "chainId", chainId);
        vm.serializeUint(deploymentJson, "deploymentBlock", deploymentBlock);
        vm.serializeString(deploymentJson, "commit", vm.envString("DEPLOY_COMMIT"));
        vm.serializeAddress(deploymentJson, "timelock", timelock);
        vm.serializeAddress(deploymentJson, "guardian", guardian);
        vm.serializeAddress(deploymentJson, "deployer", deployer);
        string memory serialized = vm.serializeString(deploymentJson, "contracts", serializedContracts);

        string memory deploymentDirectory = string.concat(vm.projectRoot(), "/../deployments");
        vm.createDir(deploymentDirectory, true);
        string memory path = string.concat(deploymentDirectory, "/", vm.toString(chainId), ".json");
        vm.writeJson(serialized, path);
        console2.log("deployment record        ", path);
    }

    function _report(Deployment memory d, DeployConfig.Config memory cfg, uint256 chainId) private pure {
        console2.log("=== HoodPups deployed ===");
        console2.log("network                  ", cfg.name);
        console2.log("chainId                  ", chainId);
        console2.log("PuppetCollectionRegistry ", address(d.collectionRegistry));
        console2.log("BitcoinAttestorRegistry  ", address(d.attestorRegistry));
        console2.log("BitcoinOwnershipOracle   ", address(d.oracle));
        console2.log("PayoutVault              ", address(d.payoutVault));
        console2.log("RootOwnershipRegistry    ", address(d.rootRegistry));
        console2.log("FeeRouter                ", address(d.feeRouter));
        console2.log("HoodPups                 ", address(d.hoodPups));
        console2.log("HoodPupOfferEscrow       ", address(d.escrow));
        console2.log("BtcSolverSettlement      ", address(d.solver));
        console2.log("TourEngine               ", address(d.tourEngine));
        console2.log("roles verified, deployer revoked");
    }
}
