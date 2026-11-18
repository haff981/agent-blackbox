// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal soulbound ERC-721 milestone badge for Agent BlackBox.
/// @dev Deployed by the AgentBlackBox game contract in its constructor;
///      `game` is set to the deploying contract automatically. No owner,
///      no admin functions, badges are non-transferable.
contract BlackBoxBadge {
    string public constant name = "Agent BlackBox Badge";
    string public constant symbol = "ABBOX";

    address public immutable game;
    uint256 public nextId = 1;

    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => uint8) public badgeTypeOf;
    /// @notice player => badgeType => tokenId (0 = not earned)
    mapping(address => mapping(uint8 => uint256)) public badgeTokenOf;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    constructor() {
        game = msg.sender;
    }

    function mintBadge(address to, uint8 badgeType) external returns (uint256) {
        require(msg.sender == game, "Only game");
        require(badgeTokenOf[to][badgeType] == 0, "Badge already earned");
        uint256 id = nextId++;
        ownerOf[id] = to;
        balanceOf[to] += 1;
        badgeTypeOf[id] = badgeType;
        badgeTokenOf[to][badgeType] = id;
        emit Transfer(address(0), to, id);
        return id;
    }

    function tokenURI(uint256 id) public view returns (string memory) {
        require(ownerOf[id] != address(0), "Nonexistent token");
        uint8 t = badgeTypeOf[id];
        string memory tStr = t == 0 ? "0" : (t == 1 ? "1" : "2");
        return string(
            abi.encodePacked(
                "https://haff981.github.io/agent-blackbox/badges/", tStr, ".json"
            )
        );
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f // ERC721Metadata
            || interfaceId == 0x01ffc9a7; // ERC165
    }
}

interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title Agent BlackBox — a daily on-chain black box for Agent ID holders.
/// @notice Seal a box today, reveal it a few blocks later. Your rarity is
///         decided by a FUTURE block hash mixed with your address and the
///         day epoch: unknowable in advance, impossible to rig, and fully
///         verifiable on-chain by anyone.
/// @dev No admin functions, no custody, no payable, no upgrades. The
///      contract never touches user assets; playing costs only gas.
contract AgentBlackBox {
    IAgentIdRegistry public immutable agentIdRegistry;
    BlackBoxBadge public immutable badge;

    uint8 public constant RARITY_COMMON = 0;
    uint8 public constant RARITY_RARE = 1;
    uint8 public constant RARITY_EPIC = 2;
    uint8 public constant RARITY_LEGENDARY = 3;
    uint8 public constant RARITY_MYTHIC = 4;

    uint8 public constant BADGE_FIRST_MYTHIC = 0;
    uint8 public constant BADGE_STREAK_7 = 1;
    uint8 public constant BADGE_FULL_SET = 2;

    struct Box {
        uint64 epoch;
        uint64 targetBlock;
        bool isSealed;
        bool revealed;
    }

    struct Player {
        uint256 totalPoints;
        uint32 totalBoxes;
        uint32 currentStreak;
        uint64 lastPlayedEpoch;
        uint32[5] rarityCounts;
        bool[3] badges;
    }

    mapping(address => Box) public boxes;
    mapping(address => Player) internal _players;

    address[10] public leaderboard;
    uint256[10] public leaderboardScores;
    uint256 public totalPlayers;
    uint256 public totalBoxesOpened;

    event BoxSealed(address indexed player, uint256 epoch, uint256 targetBlock);
    event BoxRetargeted(address indexed player, uint256 newTargetBlock);
    event BoxRevealed(
        address indexed player, uint256 epoch, uint8 rarity, uint256 points, uint256 totalPoints
    );
    event BadgeEarned(address indexed player, uint8 badgeType);

    constructor(address registry) {
        agentIdRegistry = IAgentIdRegistry(registry);
        badge = new BlackBoxBadge();
    }

    // ---------- views ----------

    function currentEpoch() public view returns (uint256) {
        return block.timestamp / 86400;
    }

    function hasAgentId(address player) public view returns (bool) {
        return agentIdRegistry.balanceOf(player) > 0;
    }

    function getPlayer(address player)
        external
        view
        returns (
            uint256 totalPoints,
            uint32 totalBoxes,
            uint32 currentStreak,
            uint64 lastPlayedEpoch,
            uint32[5] memory rarityCounts,
            bool[3] memory badges
        )
    {
        Player storage p = _players[player];
        return (
            p.totalPoints,
            p.totalBoxes,
            p.currentStreak,
            p.lastPlayedEpoch,
            p.rarityCounts,
            p.badges
        );
    }

    function getLeaderboard()
        external
        view
        returns (address[10] memory addrs, uint256[10] memory scores)
    {
        return (leaderboard, leaderboardScores);
    }

    /// @notice Points awarded for a rarity tier.
    function pointsOf(uint8 rarity) public pure returns (uint256) {
        if (rarity == RARITY_MYTHIC) return 2000;
        if (rarity == RARITY_LEGENDARY) return 400;
        if (rarity == RARITY_EPIC) return 100;
        if (rarity == RARITY_RARE) return 30;
        return 10;
    }

    // ---------- gameplay ----------

    /// @notice Step 1: seal today's box. Locks in a future target block.
    function sealBox() external {
        require(hasAgentId(msg.sender), "Agent ID required");
        uint256 epoch = currentEpoch();
        Box storage b = boxes[msg.sender];
        if (b.epoch == epoch) {
            require(!b.revealed, "Already played today");
            require(!b.isSealed, "Box already sealed");
        }
        if (_players[msg.sender].totalBoxes == 0 && b.epoch == 0) {
            totalPlayers += 1;
        }
        b.epoch = uint64(epoch);
        b.targetBlock = uint64(block.number + 2);
        b.isSealed = true;
        b.revealed = false;
        emit BoxSealed(msg.sender, epoch, b.targetBlock);
    }

    /// @notice Step 2: reveal the sealed box once the target block has passed.
    /// @dev If the target block hash has expired (>256 blocks), the box is
    ///      re-targeted to a new future block instead of being lost.
    function revealBox() external {
        Box storage b = boxes[msg.sender];
        require(b.isSealed && !b.revealed, "No sealed box");
        require(block.number > b.targetBlock, "Too early");
        bytes32 h = blockhash(b.targetBlock);
        if (h == bytes32(0)) {
            b.targetBlock = uint64(block.number + 2);
            emit BoxRetargeted(msg.sender, b.targetBlock);
            return;
        }

        uint256 epoch = b.epoch;
        uint256 roll =
            uint256(keccak256(abi.encodePacked(h, msg.sender, epoch))) % 10000;
        uint8 rarity;
        if (roll < 100) rarity = RARITY_MYTHIC; // 1%
        else if (roll < 500) rarity = RARITY_LEGENDARY; // 4%
        else if (roll < 2000) rarity = RARITY_EPIC; // 15%
        else if (roll < 5000) rarity = RARITY_RARE; // 30%
        else rarity = RARITY_COMMON; // 50%
        uint256 pts = pointsOf(rarity);

        Player storage p = _players[msg.sender];
        p.totalPoints += pts;
        p.totalBoxes += 1;
        p.rarityCounts[rarity] += 1;
        if (p.lastPlayedEpoch == uint64(epoch - 1)) {
            p.currentStreak += 1;
        } else {
            p.currentStreak = 1;
        }
        p.lastPlayedEpoch = uint64(epoch);
        totalBoxesOpened += 1;

        b.revealed = true;
        b.isSealed = false;

        emit BoxRevealed(msg.sender, epoch, rarity, pts, p.totalPoints);

        _updateLeaderboard(msg.sender, p.totalPoints);
        _awardBadges(msg.sender, p, rarity);
    }

    // ---------- internals ----------

    function _awardBadges(address player, Player storage p, uint8 rarity) internal {
        if (rarity == RARITY_MYTHIC && !p.badges[BADGE_FIRST_MYTHIC]) {
            p.badges[BADGE_FIRST_MYTHIC] = true;
            badge.mintBadge(player, BADGE_FIRST_MYTHIC);
            emit BadgeEarned(player, BADGE_FIRST_MYTHIC);
        }
        if (p.currentStreak >= 7 && !p.badges[BADGE_STREAK_7]) {
            p.badges[BADGE_STREAK_7] = true;
            badge.mintBadge(player, BADGE_STREAK_7);
            emit BadgeEarned(player, BADGE_STREAK_7);
        }
        if (
            !p.badges[BADGE_FULL_SET] && p.rarityCounts[0] > 0 && p.rarityCounts[1] > 0
                && p.rarityCounts[2] > 0 && p.rarityCounts[3] > 0 && p.rarityCounts[4] > 0
        ) {
            p.badges[BADGE_FULL_SET] = true;
            badge.mintBadge(player, BADGE_FULL_SET);
            emit BadgeEarned(player, BADGE_FULL_SET);
        }
    }

    function _updateLeaderboard(address player, uint256 score) internal {
        address[10] memory addrs;
        uint256[10] memory scores;
        uint256 n = 0;
        for (uint256 i = 0; i < 10; i++) {
            address a = leaderboard[i];
            if (a != address(0) && a != player) {
                addrs[n] = a;
                scores[n] = leaderboardScores[i];
                n++;
            }
        }
        uint256 pos = n;
        for (uint256 i = 0; i < n; i++) {
            if (score > scores[i]) {
                pos = i;
                break;
            }
        }
        if (pos < 10) {
            uint256 upper = n < 9 ? n : 9;
            for (uint256 i = upper; i > pos; i--) {
                addrs[i] = addrs[i - 1];
                scores[i] = scores[i - 1];
            }
            addrs[pos] = player;
            scores[pos] = score;
        }
        for (uint256 i = 0; i < 10; i++) {
            leaderboard[i] = addrs[i];
            leaderboardScores[i] = scores[i];
        }
    }
}
