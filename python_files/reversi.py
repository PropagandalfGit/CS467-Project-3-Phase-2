#from agent import Agent
from randomplayer import RandomPlayer
from agent import Agent
import time
import random
import sys

# decide if pieces are flippable in this direction
def flips( board, index, piece, step ):
   other = ('X' if piece == 'O' else 'O')
   here = index + step
   if here < 0 or here >= 36 or board[here] != other:
      return False
      
   if( abs(step) == 1 ):
      while( here // 6 == index // 6 and board[here] == other ):
         here = here + step
      return( here // 6 == index // 6 and board[here] == piece )
   
   else:
      while( here >= 0 and here < 36 and board[here] == other ):
         here = here + step
      return( here >= 0 and here < 36 and board[here] == piece )

def validMove( b, x, p ):
   if x < 0 or x >= 36:
      return False
   if b[x] != '-':
      return False 
   up    = x >= 6
   down  = x <  30
   left  = x % 6 > 0
   right = x % 6 < 5
   return (          left  and flips(b,x,p,-1)
         or up   and left  and flips(b,x,p,-7)
         or up             and flips(b,x,p,-6)
         or up   and right and flips(b,x,p,-5)
         or          right and flips(b,x,p, 1)
         or down and right and flips(b,x,p, 7)
         or down           and flips(b,x,p, 6)
         or down and left  and flips(b,x,p, 5))

def applyFlip( board, index, piece, step ):
   other = ('X' if piece == 'O' else 'O')
   here = index + step
   while board[here] == other:
      board = board[:here] + piece + board[here+1:]
      here = here + step
   return board

def applyMove( x, p ):
   global gameboard
   b = gameboard

   if not validMove(b,x,p):
      return False

   up    = x >= 6
   down  = x <  30
   left  = x % 6 > 0
   right = x % 6 < 5
   
   if          left  and flips(b,x,p,-1): b = applyFlip(b,x,p,-1)
   if up   and left  and flips(b,x,p,-7): b = applyFlip(b,x,p,-7)
   if up             and flips(b,x,p,-6): b = applyFlip(b,x,p,-6)
   if up   and right and flips(b,x,p,-5): b = applyFlip(b,x,p,-5)
   if          right and flips(b,x,p, 1): b = applyFlip(b,x,p, 1)
   if down and right and flips(b,x,p, 7): b = applyFlip(b,x,p, 7)
   if down           and flips(b,x,p, 6): b = applyFlip(b,x,p, 6)
   if down and left  and flips(b,x,p, 5): b = applyFlip(b,x,p, 5)
   b = b[:x] + p + b[x+1:]
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

def countPossibleMoves( board, piece ):
   movesLeft = 0
   for i in range(36):
      movesLeft = movesLeft + validMove(board,i,piece)
   return movesLeft

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

gameboard = BOARD_NORMAL
gameover  = False

t = time.time()
X = Agent('X')
O = Agent('O')
print(f"TIME TAKEN TO CREATE KBASE WAS {time.time() - t}")
t = time.time()

numWinX = 0
numWinO = 0
numTied = 0

NUM_GAMES = 500
CORNERS = (0, 5, 30, 35)

margins = []                 # signed: positive = X won by, negative = O won by
corner_splits = []           # list of (X_corners, O_corners)
forced_passes_X = 0
forced_passes_O = 0
total_moves_X   = 0
total_moves_O   = 0

for g in range(NUM_GAMES):
   # Alternate who goes first AND which diagonal the opening pieces are on.
   # Even games: X moves first, normal opening.
   # Odd  games: O moves first, swapped opening — mirrors the game exactly.
   x_goes_first = (g % 2 == 0)
   gameboard = BOARD_NORMAL # if x_goes_first else BOARD_SWAPPED
   gameover  = False

   #if x_goes_first:
   first_piece,  first_agent  = 'X', X
   second_piece, second_agent = 'O', O
   # else:
   #     first_piece,  first_agent  = 'O', O
   #     second_piece, second_agent = 'X', X

   while( not gameover ):
      t_internal = time.time()
      # First player's turn
      first_can_move = countPossibleMoves( gameboard, first_piece ) > 0
      if first_can_move:
         play = -1
         while not validMove( gameboard, play, first_piece ):
            play = first_agent.getMove( gameboard )
            if time.time() - t_internal > 3:
               print(gameboard)
               raise Exception
         t_internal = time.time()
         applyMove( play, first_piece )
         if first_piece == 'X': total_moves_X += 1
         else:                  total_moves_O += 1
      elif countPossibleMoves( gameboard, second_piece ) > 0:
         # forced pass: opponent still has moves so game isn't over yet
         if first_piece == 'X': forced_passes_X += 1
         else:                  forced_passes_O += 1

      # Second player's turn
      second_can_move = countPossibleMoves( gameboard, second_piece ) > 0
      if second_can_move:
         play = -1
         while not validMove( gameboard, play, second_piece ):
            play = second_agent.getMove( gameboard )
            if time.time() - t_internal > 3:
               print(gameboard)
               raise Exception
         t_internal = time.time()
         applyMove( play, second_piece )
         if second_piece == 'X': total_moves_X += 1
         else:                   total_moves_O += 1
      elif countPossibleMoves( gameboard, first_piece ) > 0:
         if second_piece == 'X': forced_passes_X += 1
         else:                   forced_passes_O += 1

      # Check for game over
      if countPossibleMoves( gameboard, 'X' ) + countPossibleMoves( gameboard, 'O' ) == 0:
         status = getEndgameStatus( gameboard )
         margins.append( status )
         x_corners = sum(1 for c in CORNERS if gameboard[c] == 'X')
         o_corners = sum(1 for c in CORNERS if gameboard[c] == 'O')
         corner_splits.append( (x_corners, o_corners) )
         if status > 0:
            X.endGame(  1, gameboard )
            O.endGame( -1, gameboard )
            numWinX += 1
         elif status < 0:
            X.endGame( -1, gameboard )
            O.endGame(  1, gameboard )
            numWinO += 1
         else:
            X.endGame( 0, gameboard )
            O.endGame( 0, gameboard )
            numTied += 1
         gameover = True

X.stopPlaying()
O.stopPlaying()

print(f"TIME TAKEN WAS {time.time() - t}")
print()
print(f"Games:        {NUM_GAMES}")
print(f"X wins:       {numWinX}  ({100*numWinX/NUM_GAMES:.1f}%)")
print(f"O wins:       {numWinO}  ({100*numWinO/NUM_GAMES:.1f}%)")
print(f"Ties:         {numTied}  ({100*numTied/NUM_GAMES:.1f}%)")
print()

abs_margins = [abs(m) for m in margins]
decisive    = [m for m in margins if m != 0]
print(f"Avg |margin| (all):      {sum(abs_margins)/len(abs_margins):.2f}")
if decisive:
   print(f"Avg |margin| (decisive): {sum(abs(m) for m in decisive)/len(decisive):.2f}")
print(f"Margin distribution:")
buckets = {"0 (tie)": 0, "1-3": 0, "4-7": 0, "8-15": 0, "16+": 0}
for m in abs_margins:
   if   m == 0:  buckets["0 (tie)"] += 1
   elif m <= 3:  buckets["1-3"]     += 1
   elif m <= 7:  buckets["4-7"]     += 1
   elif m <= 15: buckets["8-15"]    += 1
   else:         buckets["16+"]     += 1
for k, v in buckets.items():
   print(f"  {k:8}: {v:4}  ({100*v/NUM_GAMES:.1f}%)")
print()

print("Corner-split distribution (X-O):")
split_counts = {}
for s in corner_splits:
   split_counts[s] = split_counts.get(s, 0) + 1
for s in sorted(split_counts.keys(), key=lambda p: (-p[0], p[1])):
   print(f"  {s[0]}-{s[1]}: {split_counts[s]:4}  ({100*split_counts[s]/NUM_GAMES:.1f}%)")
print()

print(f"Forced passes:")
print(f"  X total: {forced_passes_X}  (avg {forced_passes_X/NUM_GAMES:.2f}/game)")
print(f"  O total: {forced_passes_O}  (avg {forced_passes_O/NUM_GAMES:.2f}/game)")
print(f"Total moves placed:")
print(f"  X: {total_moves_X}  (avg {total_moves_X/NUM_GAMES:.2f}/game)")
print(f"  O: {total_moves_O}  (avg {total_moves_O/NUM_GAMES:.2f}/game)")