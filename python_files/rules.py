class Rules:
    # decide if pieces are flippable in this direction
    def flips( self, board, index, piece, step ):
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
       
    # decide if this is a valid move
    def isValidMove( self, b, x, p ): # board, index, piece
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
       return (          left  and self.flips(b,x,p,-1)  # left
             or up   and left  and self.flips(b,x,p,-7)  # up/left
             or up             and self.flips(b,x,p,-6)  # up
             or up   and right and self.flips(b,x,p,-5)  # up/right
             or          right and self.flips(b,x,p, 1)  # right
             or down and right and self.flips(b,x,p, 7)  #down/right
             or down           and self.flips(b,x,p, 6)  # down
             or down and left  and self.flips(b,x,p, 5)) # down/left
