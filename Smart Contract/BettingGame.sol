pragma solidity 0.6.6;

import "https://raw.githubusercontent.com/smartcontractkit/chainlink/master/evm-contracts/src/v0.6/VRFConsumerBase.sol";
import "https://github.com/smartcontractkit/chainlink/blob/master/evm-contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract BettingGame is VRFConsumerBase {
    // assign an aggregator contract to the variable.
    AggregatorV3Interface internal ethUsd;

    uint256 internal fee;
    uint256 public randomResult;

    //Test Network: Rinkeby

    // VRF Coordinator
    address constant VFRC_address = 0xb3dCcb4Cf7a26f6cf6B120Cf5A73875B7BBc655B;
    // LINK token
    address constant LINK_address = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;

    //For setting 50% chance, (0.5*(uint256+1))
    uint256 constant half_chances =
        57896044618658097711785492504343953926634992332820282019728792003956564819968;

    //Component from which final random value by Chainlink VFRC.
    bytes32 internal constant keyHash =
        0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311;

    //State Variables
    uint256 public gameId;
    uint256 public lastGameId;
    address payable public admin;

    mapping(uint256 => Game) public games;

    struct Game {
        uint256 id;
        uint256 bet;
        uint256 seed;
        uint256 amount;
        address payable player;
    }

    // Ensures caller is admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "caller is not the admin");
        _;
    }

    // Ensures caller is VRFC
    modifier onlyVFRC() {
        require(msg.sender == VFRC_address, "only VFRC can call this function");
        _;
    }

    event Withdraw(address admin, uint256 amount);
    event Received(address indexed sender, uint256 amount);
    event Result(
        uint256 id,
        uint256 bet,
        uint256 randomSeed,
        uint256 amount,
        address player,
        uint256 winAmount,
        uint256 randomResult,
        uint256 time
    );

    // Constructor inherits VRFConsumerBase.
    constructor() public VRFConsumerBase(VFRC_address, LINK_address) {
        fee = 0.1 * 10**18; // 0.1 LINK
        admin = msg.sender;

        // assign ETH/USD Rinkeby contract address to the aggregator variable
        ethUsd = AggregatorV3Interface(
            0x8A753747A1Fa494EC906cE90E9f37563A8AF630e
        );
    }

    //allows this contract to receive payments
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // returns latest ETH/USD price from Chainlink oracles
    function ethInUsd() public view returns (int256) {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = ethUsd.latestRoundData();

        return price;
    }

    function weiInUsd() public view returns (uint256) {
        //ethUsd - latest price from Chainlink oracles
        int256 ethUsd = ethInUsd();
        int256 weiUsd = 10**26 / ethUsd;
        return uint256(weiUsd);
    }

    // If Wins, user gets 2x of his betAmount
    function game(uint256 bet, uint256 seed) public payable returns (bool) {
        // checks if msg.value is higher or equal to $1
        uint256 weiUsd = weiInUsd();
        require(msg.value >= weiUsd, "Error, msg.value must be >= $1");

        //bet=0 refers to Tails and bet=1 refers to Heads
        require(bet <= 1, "Error, accept only 0 and 1");

        //vault balance must be at least equal to msg.value
        require(
            address(this).balance >= msg.value,
            "Error, insufficent vault balance"
        );

        //gameId is unique identifier
        games[gameId] = Game(gameId, bet, seed, msg.value, msg.sender);

        //increment gameId for next game
        gameId = gameId + 1;

        //auto-generated seed
        getRandomNumber(seed);

        return true;
    }

    // Request for randomness
    function getRandomNumber(uint256 userProvidedSeed)
        internal
        returns (bytes32 requestId)
    {
        require(
            LINK.balanceOf(address(this)) > fee,
            "Error, not enough LINK - fill contract with faucet"
        );
        return requestRandomness(keyHash, fee, userProvidedSeed);
    }

    // Callback function used by VRF Coordinator
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;

        //send final random value to the result();
        result(randomResult);
    }

    // Send reward to the winner
    function result(uint256 random) public payable onlyVFRC {
        //check bets from latest betting round, one by one
        for (uint256 i = lastGameId; i < gameId; i++) {
            //reset winAmount for current user
            uint256 winAmount = 0;

            //if user wins, then receives 2x of their betting amount
            if (
                (random >= half_chances && games[i].bet == 1) ||
                (random < half_chances && games[i].bet == 0)
            ) {
                winAmount = games[i].amount * 2;
                games[i].player.transfer(winAmount);
            }
            emit Result(
                games[i].id,
                games[i].bet,
                games[i].seed,
                games[i].amount,
                games[i].player,
                winAmount,
                random,
                block.timestamp
            );
        }
        //save current gameId to lastGameId for the next betting round
        lastGameId = gameId;
    }
}
