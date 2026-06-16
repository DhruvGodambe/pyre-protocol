// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IBurnTracker} from "../interfaces/IBurnTracker.sol";
import {IPyreWeightFactors} from "../interfaces/IPyreWeightFactors.sol";
import {IPyreStaking} from "../interfaces/IPyreStaking.sol";
import {IPyreStakingHooks} from "../interfaces/IPyreStakingHooks.sol";

/// @title FireSpirit
/// @notice Soulbound progression NFT earned through cumulative $PYRE burns.
contract FireSpirit is ERC721, AccessControl, IBurnTracker, IPyreWeightFactors {
    bytes32 public constant LP_RECORDER_ROLE = keccak256("LP_RECORDER_ROLE");

    uint256 public constant WAD = 1e18;
    uint256 public constant EMBER_THRESHOLD = 10_000 ether;
    uint256 public constant FLAME_THRESHOLD = 75_000 ether;
    uint256 public constant FORGE_THRESHOLD = 150_000 ether;
    uint256 public constant PYRE_THRESHOLD = 300_000 ether;
    uint256 public constant FLAME_MULTIPLIER = 15e17;
    uint256 public constant FORGE_MULTIPLIER = 2e18;
    uint256 public constant PYRE_MULTIPLIER = 3e18;
    uint256 public constant LP_BURN_BONUS = 12e17;

    enum Stage {
        EMBER,
        FLAME,
        FORGE,
        PYRE
    }

    address public immutable pyreToken;
    IPyreStakingHooks public immutable pyreStaking;

    uint256 private _nextTokenId = 1;

    mapping(address => uint256) public pendingBurn;
    mapping(address => uint256) public walletToTokenId;
    mapping(address => bool) public lpBurners;
    mapping(uint256 => uint256) public spiritCumulativeBurn;
    mapping(uint256 => Stage) public spiritStage;

    event SpiritMinted(address indexed wallet, uint256 indexed tokenId, Stage stage, uint256 cumulativeBurn);
    event SpiritUpgraded(uint256 indexed tokenId, Stage stage, uint256 cumulativeBurn);
    event LpBurnerFlagged(address indexed wallet);

    error OnlyPyreToken();
    error InvalidRecipient();
    error NoSpirit(address account);

    constructor(address admin, address pyreToken_, address pyreStaking_) ERC721("Fire Spirit", "SPIRIT") {
        pyreToken = pyreToken_;
        pyreStaking = IPyreStakingHooks(pyreStaking_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LP_RECORDER_ROLE, admin);
    }

    function onPyreBurn(address account, uint256 amount) external {
        if (msg.sender != pyreToken) revert OnlyPyreToken();
        if (amount == 0) return;

        uint256 tokenId = walletToTokenId[account];
        if (tokenId == 0) {
            uint256 pending = pendingBurn[account] + amount;
            pendingBurn[account] = pending;
            if (pending >= EMBER_THRESHOLD) {
                _mintSpirit(account, pending);
            }
            return;
        }

        _applyBurnToSpirit(tokenId, amount);
        pyreStaking.onWeightFactorsChanged(account);
    }

    function flagLpBurner(address wallet) external onlyRole(LP_RECORDER_ROLE) {
        lpBurners[wallet] = true;
        emit LpBurnerFlagged(wallet);
        pyreStaking.onWeightFactorsChanged(wallet);
    }

    function nftStageMultiplier(address account) external view returns (uint256) {
        uint256 tokenId = walletToTokenId[account];
        if (tokenId == 0 || _ownerOf(tokenId) != account) return WAD;
        return _stageMultiplier(spiritStage[tokenId]);
    }

    function lpBurnBonus(address account) external view returns (uint256) {
        return lpBurners[account] ? LP_BURN_BONUS : WAD;
    }

    function stageOf(address account) external view returns (Stage) {
        uint256 tokenId = walletToTokenId[account];
        if (tokenId == 0 || _ownerOf(tokenId) != account) revert NoSpirit(account);
        return spiritStage[tokenId];
    }

    function _mintSpirit(address wallet, uint256 cumulativeBurn) internal {
        uint256 tokenId = _nextTokenId++;
        pendingBurn[wallet] = 0;
        spiritCumulativeBurn[tokenId] = cumulativeBurn;

        Stage stage = _stageForBurn(cumulativeBurn);
        spiritStage[tokenId] = stage;

        _safeMint(wallet, tokenId);
        emit SpiritMinted(wallet, tokenId, stage, cumulativeBurn);
        pyreStaking.onWeightFactorsChanged(wallet);
    }

    function _applyBurnToSpirit(uint256 tokenId, uint256 amount) internal {
        uint256 cumulative = spiritCumulativeBurn[tokenId] + amount;
        spiritCumulativeBurn[tokenId] = cumulative;

        Stage stage = _stageForBurn(cumulative);
        if (uint8(stage) > uint8(spiritStage[tokenId])) {
            spiritStage[tokenId] = stage;
            emit SpiritUpgraded(tokenId, stage, cumulative);
        }
    }

    function _stageForBurn(uint256 cumulativeBurn) internal pure returns (Stage) {
        if (cumulativeBurn >= PYRE_THRESHOLD) return Stage.PYRE;
        if (cumulativeBurn >= FORGE_THRESHOLD) return Stage.FORGE;
        if (cumulativeBurn >= FLAME_THRESHOLD) return Stage.FLAME;
        return Stage.EMBER;
    }

    function _stageMultiplier(Stage stage) internal pure returns (uint256) {
        if (stage == Stage.PYRE) return PYRE_MULTIPLIER;
        if (stage == Stage.FORGE) return FORGE_MULTIPLIER;
        if (stage == Stage.FLAME) return FLAME_MULTIPLIER;
        return WAD;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        address previousOwner = super._update(to, tokenId, auth);

        if (from != address(0)) {
            if (walletToTokenId[from] == tokenId) {
                walletToTokenId[from] = 0;
            }
            pyreStaking.onWeightFactorsChanged(from);
        }

        if (to != address(0)) {
            if (from == address(0)) {
                walletToTokenId[to] = tokenId;
                pyreStaking.onWeightFactorsChanged(to);
            } else {
                if (walletToTokenId[to] != 0) revert InvalidRecipient();
                walletToTokenId[to] = tokenId;
                if (IPyreStaking(address(pyreStaking)).stakedBalanceOf(to) > 0) {
                    pyreStaking.onWeightFactorsChanged(to);
                }
            }
        }

        return previousOwner;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
