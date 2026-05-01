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
   
   up    = x >= 12
   down  = x <  24
   left  = x % 6 > 1
   right = x % 6 < 4
   
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
X = RandomPlayer('X')
O = Agent('O')
print(f"TIME TAKEN TO CREATE KBASE WAS {time.time() - t}")
t = time.time()

numWinX = 0
numWinO = 0
numTied = 0

for g in range(50):
   # Alternate who goes first AND which diagonal the opening pieces are on.
   # Even games: X moves first, normal opening.
   # Odd  games: O moves first, swapped opening — mirrors the game exactly.
   x_goes_first = (g % 2 == 0)
   gameboard = BOARD_NORMAL #if x_goes_first else BOARD_SWAPPED
   gameover  = False

   first_piece,  first_agent  = 'X', X
   second_piece, second_agent = 'O', O

   while( not gameover ):
      t_internal = time.time()
      # First player's turn
      if countPossibleMoves( gameboard, first_piece ) > 0:
         play = -1
         while not validMove( gameboard, play, first_piece ):
            play = first_agent.getMove( gameboard )
            if time.time() - t_internal > 3:
               print(gameboard)
               raise Exception
         t_internal = time.time()
         applyMove( play, first_piece )

      # Second player's turn
      if countPossibleMoves( gameboard, second_piece ) > 0:
         play = -1
         while not validMove( gameboard, play, second_piece ):
            play = second_agent.getMove( gameboard )
            if time.time() - t_internal > 3:
               print(gameboard)
               raise Exception
         t_internal = time.time()
         applyMove( play, second_piece )

      # Check for game over
      if countPossibleMoves( gameboard, 'X' ) + countPossibleMoves( gameboard, 'O' ) == 0:
         status = getEndgameStatus( gameboard )
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
print( "X   : " + str(numWinX)  + " games" )
print( "O   : " + str(numWinO) + " games ***" )
print( "Tie : " + str(numTied)  + " games" )