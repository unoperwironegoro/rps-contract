pragma solidity ^0.5.0;

contract RockPaperScissors {
    uint wager = 10 ether;        // The cost of playing the game
    
    State state = State.Playing;

    mapping(address => Player) players;
    address payable[] player_addrs;


    uint256 timeout_duration = 10;
    uint256 abandoned_duration = 2;
    uint256 timeout = 0;

    // ----------------------------- Structs -------------------------------

    struct Player {
        bool isPlaying;      // If the player is in the game
        bool awaiting;       // If the player is next to make a move
        bytes32 hashed_move; // The player's hashed move: (password + move)
        Move move;           // The player's move
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

    modifier hashIsConsistent(string memory password, string memory sMove) {
        require(players[msg.sender].hashed_move == hash(password, sMove));
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

    // --------------------------- View State ------------------------------
    function viewState() public view returns (State) {
        return state;
    }
    
    function viewPlayerCount() public view returns (uint) {
        return player_addrs.length;
    }

    // ------------------------- State Transitions -------------------------

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
            players[player_addrs[0]].awaiting = true;
            players[player_addrs[1]].awaiting = true;
        }
    }

    /** A player reveals by giving the password and move for the hash */
    function reveal(string memory password, string memory sMove) public
      inState(State.Revealing) isPlaying() hashIsConsistent(password, sMove)
      hasNotRevealed() {
        
        Move move = stringToMove(sMove);
        
        // Invalid move was committed
        require(move != Move.Unknown);
          
        players[msg.sender].awaiting = false;
        players[msg.sender].move = move;

        Move m1 = players[player_addrs[0]].move;
        Move m2 = players[player_addrs[1]].move;
      
        // Awaiting the other players' move
        if(m1 == Move.Unknown || m2 == Move.Unknown) {
            timeout = now + timeout_duration;
            return;
        } else {
            // Pay winnings
            (uint p1w, uint p2w) = decideWinnings(m1, m2);
            player_addrs[0].transfer(p1w);
            player_addrs[1].transfer(p2w);

            // Reset the contract
            reset();
        }
    }

    // -------------------------- Early Termination ------------------------

    /** The victim of the timeout can claim the pot */
    function claimTimeout() public 
      isTimedOut() isPlaying() isNotAwaiting() {
        if(address(this).balance > 0) {
            msg.sender.transfer(address(this).balance);
        }
        reset();
    }

    /** Anyone can claim the wager of an abandoned game */
    function claimAbandonment() public 
      isAbandoned() {
        if(address(this).balance > 0) {
            msg.sender.transfer(address(this).balance);
        }
        reset();
    }

    // ------------------------- Auxiliary Functions -----------------------

    /** Reset the contract to its initial state */
    function reset() private {
        for(uint i = 0; i < player_addrs.length; i++) {
            delete players[player_addrs[i]];
        }
        player_addrs.length = 0;
        
        state = State.Playing;
    }

    function decideWinnings(Move m1, Move m2) private view
      returns (uint, uint) {
        if(m1 == m2) {
            return (wager, wager);
        }
        
        if((m1 == Move.Rock && m2 == Move.Scissors) ||
           (m1 == Move.Paper && m2 == Move.Rock) ||
           (m1 == Move.Scissors && m2 == Move.Paper)) {
            return (2 * wager, 0);
        }

        return (0, 2 * wager);
    }

    function stringEquals(string memory s1, string memory s2) private pure
      returns (bool) {
        return keccak256(bytes(s1)) == keccak256(bytes(s2));
    }

    // -------------------- Public Auxiliary Functions ---------------------
    
    /** Allow for clients to verify their hash implementations */
    function hash(string memory password, string memory sMove) public pure
      returns (bytes32) {
        return keccak256(abi.encodePacked(bytes(password), sMove));
    }
    
    /** Aid in reading logs */
    function stringToMove(string memory sMove) public pure returns (Move) {
        if(stringEquals(sMove, 'rock')) {
            return Move.Rock;
        } else if(stringEquals(sMove, 'paper')) {
            return Move.Paper;
        } else if(stringEquals(sMove, 'scissors')) {
            return Move.Scissors;
        }
        return Move.Unknown;
    }
}