import lupa
lua = lupa.LuaRuntime()
lua.execute("""
    package.path = package.path .. ';./?.lua;./lua_port/?.lua'
""")

class Agent:
    symbol = 'X'
    def __init__( self, xORo ):
        self.symbol = xORo
        self.agent = lua.eval("require('lua_port.agent').new")(xORo, "lua_port/agent-kbase.txt")
   
    def getMove(self, gameboard):
        board_list = list(gameboard)
        lua_board = lua.table_from(board_list)
        move = self.agent.GetMove(self.agent, lua_board)
        return move - 1
         
    def endGame(self, status, gameboard):
        return self.agent.EndGame(self.agent, status)

    def stopPlaying( self ):
        self.agent.StopPlaying(self.agent)
