#from agent import Agent
import time
from agent import Agent
import sys
import csv
import os

def write_milestone_to_csv(total, numWinO, numWinX, numTied, filename="results.csv"):
    o_pct   = 100 * numWinO / total
    x_pct   = 100 * numWinX / total
    tie_pct = 100 * numTied / total
    print(f"{total:<16,} {o_pct:<10.2f} {x_pct:<10.2f} {tie_pct:<10.2f}")

    file_exists = os.path.isfile(filename)

    with open(filename, "a", newline="") as f:
        writer = csv.writer(f)
        if not file_exists:
            writer.writerow(["games_played", "o_wins", "x_wins", "ties", "o_pct", "x_pct", "tie_pct"])
        writer.writerow([total, numWinO, numWinX, numTied, f"{o_pct:.2f}", f"{x_pct:.2f}", f"{tie_pct:.2f}"])
   
def print_milestone(total, numWinO, numWinX, numTied):
    o_pct   = 100 * numWinO / total
    x_pct   = 100 * numWinX / total
    tie_pct = 100 * numTied / total
    # Clear the live counter line, then print the milestone block
    sys.stdout.write("\r" + " " * 60 + "\r")
    print( "┌─────────────────────────────────────────────┐")
    print(f"│    Milestone: {total:>12,} games played       │")
    print( "│─────────────────────────────────────────────│")
    print(f"│  O wins : {numWinO:>10,}  ({o_pct:>6.2f}%)              │")
    print(f"│  X wins : {numWinX:>10,}  ({x_pct:>6.2f}%)              │")
    print(f"│  Ties   : {numTied:>10,}  ({tie_pct:>6.2f}%)              │")
    print( "└─────────────────────────────────────────────┘")

def live_counter(g, total_games, milestones):
    # Find the previous and next milestone relative to current game
    sorted_ms  = sorted(milestones)
    prev_ms    = 0
    next_ms    = total_games
    for ms in sorted_ms:
        if g <= ms:
            next_ms = ms
            break
        prev_ms = ms

    bar_width  = 30
    span       = next_ms - prev_ms
    progress   = g - prev_ms
    pct        = progress / span
    filled     = int(bar_width * pct)
    bar        = "█" * filled + "░" * (bar_width - filled)

    sys.stdout.write(f"\r   [{bar}] {g:>10,} → {next_ms:,}  ({pct*100:.1f}%)")
    sys.stdout.flush()


# decide if pieces are flippable in this direction
def flips( board, index, piece, step ):
   other = ('X' if piece == 'O' else 'O')
   # is an opponent's piece in first spot that way?
   here = index + step
   if here < 0 or here >= 36 or board[here] != other:
      return False
      
   if( abs(step) == 1 ): # moving left or right along row
      while( here // 6 == index // 6 and board[here] == other ):
         here = here + step
      # are we still on the same row and did we find a matching endpiece?
      return( here // 6 == index // 6 and board[here] == piece )
   
   else: # moving up or down (possibly with left/right tilt)
      while( here >= 0 and here < 36 and board[here] == other ):
         here = here + step
      # are we still on the board and did we find a matching endpiece?
      return( here >= 0 and here < 36 and board[here] == piece )

# decide if given move (index x) is valid for player p
def validMove( b, x, p ): # board, index, piece
   # invalid index
   if x < 0 or x >= 36:
      return False
   # space already occupied
   if b[x] != '-':
      return False 
   # otherwise, check for flipping pieces
   up    = x >= 12   # at least third row down
   down  = x <  24   # at least third row up
   left  = x % 6 > 1 # at least third column
   right = x % 6 < 4 # not past fourth column
   return (          left  and flips(b,x,p,-1)  # left
         or up   and left  and flips(b,x,p,-7)  # up/left
         or up             and flips(b,x,p,-6)  # up
         or up   and right and flips(b,x,p,-5)  # up/right
         or          right and flips(b,x,p, 1)  # right
         or down and right and flips(b,x,p, 7)  #down/right
         or down           and flips(b,x,p, 6)  # down
         or down and left  and flips(b,x,p, 5)) # down/left

# actually flip pieces in this direction
# assume validity has already been checked
def applyFlip( board, index, piece, step ):
   other = ('X' if piece == 'O' else 'O')
   # starting point
   here = index + step
   while board[here] == other:
      board = board[:here] + piece + board[here+1:]
      here = here + step
   return board

# actually flip pieces in this direction
def applyMove( x, p ): # index, piece
   global gameboard
   b = gameboard
   
   # if not valid move, stop here
   if not validMove(b,x,p):
      return False
   
   up    = x >= 12   # at least third row down
   down  = x <  24   # at least third row up
   left  = x % 6 > 1 # at least third column
   right = x % 6 < 4 # not past fourth column
   
   # flip everything that should be flipped
   if          left  and flips(b,x,p,-1): # left
      b = applyFlip(b,x,p,-1)
   if up   and left  and flips(b,x,p,-7): # up/left
      b = applyFlip(b,x,p,-7)
   if up             and flips(b,x,p,-6): # up
      b = applyFlip(b,x,p,-6)
   if up   and right and flips(b,x,p,-5): # up/right
      b = applyFlip(b,x,p,-5)
   if          right and flips(b,x,p, 1): # right
      b = applyFlip(b,x,p, 1)
   if down and right and flips(b,x,p, 7): # down/right
      b = applyFlip(b,x,p, 7)
   if down           and flips(b,x,p, 6): # down
      b = applyFlip(b,x,p, 6)
   if down and left  and flips(b,x,p, 5): # down/left
      b = applyFlip(b,x,p, 5)
   # and put a new piece here too
   b = b[:x] + p + b[x+1:]
   # save modified gameboard
   gameboard = b
   
def printBoard( board ):
   print()
   print( "##########" )
   print( "# " + board[ 0: 6] + " #" )
   print( "# " + board[ 6:12] + " #" )
   print( "# " + board[12:18] + " #" )
   print( "# " + board[18:24] + " #" )
   print( "# " + board[24:30] + " #" )
   print( "# " + board[30:36] + " #" )
   print( "##########" )
   print()

# how many moves does this player have currently available?
def countPossibleMoves( board, piece ):
   movesLeft = 0
   for i in range(36):
      movesLeft = movesLeft + validMove(board,i,piece)
   return movesLeft
   
# game score given board layout
# X wins if positive, O wins if negative, tie if zero
def getEndgameStatus( board ):
   
   countX = 0
   countO = 0
   for i in range(36):
      countX = countX + ( board[i] == 'X' )
      countO = countO + ( board[i] == 'O' )
   
   return countX - countO

# Standard starting positions.
# NORMAL:  X pieces at 14,21 / O pieces at 15,20  (0-indexed)
# SWAPPED: X pieces at 15,20 / O pieces at 14,21
# Alternating ensures neither player has a structural first-move advantage
# over a full training run, and both players see mirrored opening states.
BOARD_NORMAL  = "--------------XO----OX--------------"
BOARD_SWAPPED = "--------------OX----XO--------------"

# global variables
gameboard = "--------------XO----OX--------------"
gameover = False

TOTAL_GAMES = 20_000_000
milestones = set([100, 200, 300, 400, 500, 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000, 20_000_000])

print()
print("  ╔══════════════════════════════════════════════╗")
print("  ║           Reversi Agent Training             ║")
print("  ╚══════════════════════════════════════════════╝")
print(f"  Total games planned : {TOTAL_GAMES:,}")
print(f"  Milestones          : {sorted(milestones)}")
print()

print("  Loading agents and knowledge base...")
X = Agent('X')
O = Agent('O')
t = time.time()
print("  Agents ready — KB loaded\n")
#O = Agent('O') # use this when agent is implemented

# counters for tracking wins over multiple trials
numWinX = 0
numWinO = 0
numTied = 0

print(f"{'Games Played':<16} {'O Win %':<10} {'X Win %':<10} {'Tie %':<10}")
print("-" * 46)

# how many games do you want to play?
for g in range(1, TOTAL_GAMES + 1):
   # reset global variables for new game
   x_goes_first = (g % 3 == 0)
   gameboard = BOARD_NORMAL if x_goes_first else BOARD_SWAPPED
   gameover  = False


   if x_goes_first:
        first_piece,  first_agent  = 'X', X
        second_piece, second_agent = 'O', O
   else:
        first_piece,  first_agent  = 'O', O
        second_piece, second_agent = 'X', X

   # play game until done
   move = 1
   while( not gameover ):
      if countPossibleMoves( gameboard, first_piece ) > 0:
         play = -1
         while not validMove( gameboard, play, first_piece ):
            play = first_agent.getMove( gameboard )
         applyMove( play, first_piece )

      # player O
      if countPossibleMoves( gameboard, second_piece ) > 0:
         play = -1
         while not validMove( gameboard, play, second_piece ):
            play = second_agent.getMove( gameboard )
         applyMove( play, second_piece )

      # if game over
      if countPossibleMoves( gameboard, first_piece ) + countPossibleMoves( gameboard, second_piece ) == 0:
         status = getEndgameStatus( gameboard )
         if status > 0: # X wins
            first_agent.endGame(  1, gameboard )
            second_agent.endGame( -1, gameboard )
            numWinX = numWinX + 1
            #print( "X wins by " + str(status) + " pieces" )
         elif status < 0: # O wins
            first_agent.endGame( -1, gameboard )
            second_agent.endGame(  1, gameboard )
            numWinO = numWinO + 1
            #print( "O wins by " + str(-status) + " pieces" )
         else: # status == 0, tie game
            first_agent.endGame(  0, gameboard )
            second_agent.endGame(  0, gameboard )
            numTied = numTied + 1
            #print( "Tie game" )
         gameover = True
         #printBoard(gameboard)

      move = move + 1

   if g % 100 == 0 or g in milestones:
      live_counter(g, TOTAL_GAMES, milestones)

   if g in milestones:
      total = numWinX + numWinO + numTied
      write_milestone_to_csv(total, numWinO, numWinX, numTied)
      sys.stdout.write("  Syncing knowledge base to disk...")
      sys.stdout.flush()
      X.stopPlaying()
      O.stopPlaying()
      print(" done.\n")
      sys.stdout.flush()


   # when running thousands of learning trials,
   #   periodic updates are nice confirmation
   #   that everything's still running
#   if (numWinX + numWinO + numTied) % 1000 == 0:
#      print( "Completed " + str(numWinX + numWinO + numTied) )
sys.stdout.write("\r" + " " * 60 + "\r")
print("  Final KB save...")
X.stopPlaying()
O.stopPlaying()
print("  Done!\n")

print("  ╔══════════════════════════════════════════════╗")
print("  ║                 Final Results                ║")
print("  ╚══════════════════════════════════════════════╝")
print(f"  X wins : {numWinX:>10,}")
print(f"  O wins : {numWinO:>10,}  ◄")
print(f"  Ties   : {numTied:>10,}")
print()
