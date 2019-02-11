pragma solidity ^0.4.24;

contract RockPaperScissors {
    State state = State.Playing;
    uint wager = 10;

    mapping(address => Player) players;
    address[] player_addrs;


    uint256 timeout_duration = 10;
    uint256 abandoned_duration = 2;
    uint256 timeout = 0;

    // ----------------------------- Structs -------------------------------

    struct Player {
        bool isPlaying;      // If the player is in the game
        bool awaiting;       // If the player is next to make a move
        bytes32 hashed_move; // The player's hashed move: (password:move)
        Move move;            // The player's move
    }

    enum Move {
        Rock,
        Paper,
        Scissors,
        Unknown
    }
    
    enum State {
        Playing,
        Revealing
    }

    // ---------------------------- Modifiers ------------------------------
  
    modifier inState(State _state) {
        require(state == _state);
        _;
    }

    modifier hasPaidWager() {
        require(msg.value == wager);
        _;
    }

    modifier isPlaying() {
        require(players[msg.sender].isPlaying);
        _;
    }

    modifier isNotPlaying() {
        require(!players[msg.sender].isPlaying);
        _;
    }

    modifier hashIsConsistent(string password, Move move) {
        require(
            players[msg.sender].hashed_move ==
            keccak256(abi.encodePacked(password, move)));
        _;
    }

    /** The game depends on this player to proceed */
    modifier isNotAwaiting() {
        require(!players[msg.sender].awaiting);
        _;
    }

    /** This player has not already revealed */
    modifier hasNotRevealed() {
        require(players[msg.sender].move == Move.Unknown);
        _;
    }

    /** Timeout - The game has taken too long and can be finished early. */
    modifier isTimedOut() {
        require(now > timeout);
        _;
    }

    /** Abandonment - A game has exceeded the timeout without claim. */
    modifier isAbandoned() {
        require(now > timeout + abandoned_duration);
        _;
    }

    // ------------------------- State Transitions -----------------------

    /** A player makes a move by hashing a password and the move. */
    function play(bytes32 hashed_move) public payable
      hasPaidWager() inState(State.Playing) isNotPlaying() {
        players[msg.sender] = Player({
            isPlaying: true,
            awaiting: false,
            hashed_move: hashed_move,
            move: Move.Unknown
        });
        player_addrs.push(msg.sender);
        
        timeout = now + timeout_duration;

        // Both players have made their move
        if(player_addrs.length == 2) {
            state = State.Revealing;
            players[1].awaiting = true;
            players[2].awaiting = true;
        }
    }

    /** A player reveals by giving the password and move for the hash */
    function reveal(string password, Move move) public
      inState(State.Revealing) isPlaying() hashIsConsistent(password, move)
      hasNotRevealed() {
        players[msg.sender].awaiting = false;
        players[msg.sender].move = move;

        Move move1 = players[player_addrs[0]].move;
        Move move2 = players[player_addrs[1]].move;
      
        // Awaiting the other players' move
        if(move1 == Move.Unknown || move2 == Move.Unknown) {
            timeout = now + timeout_duration;
            return;
        } else {
            // Pay winnings
            (uint p1w, uint p2w) = decideWinnings(move1, move2);
            player_addrs[0].transfer(p1w);
            player_addrs[1].transfer(p2w);

            // Reset the contract
            selfdestruct(0);
        }
    }

    // -------------------------- Early Termination ------------------------

    /** The victim of the timeout can claim the pot */
    function claimTimeout() public 
      isTimedOut() isPlaying() isNotAwaiting() {
        selfdestruct(msg.sender);
    }

    /** Anyone can claim the wager of an abandoned game */
    function claimAbandonment() public 
      isAbandoned() {
        selfdestruct(msg.sender);
    }

    // ------------------------- Auxiliary Functions -----------------------

    function decideWinnings(Move m1, Move m2) private view
      returns (uint, uint) {
        if(m1 == m2) {
            return (wager/2, wager/2);
        }
        
        if((m1 == Move.Rock && m2 == Move.Scissors) ||
           (m1 == Move.Paper && m2 == Move.Rock) ||
           (m1 == Move.Scissors && m2 == Move.Paper)) {
            return (wager, 0);
        }

        return (0, wager);
    }

    function otherPlayerAddress() view private returns (address) {
        if(player_addrs[0] == msg.sender) {
            return player_addrs[1];
        } else if(player_addrs[1] == msg.sender) {
            return player_addrs[0];
        }
        revert();
    }
}