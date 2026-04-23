local string = require('string-helpers')

-------------------------------------------------------------------------------------
-- HELPERS --------------------------------------------------------------------------
-------------------------------------------------------------------------------------

--- Deserializes a line from the knowledge base file into a state and data table.
--- File format: "state|idx:prob,idx:prob,..."
--- @param line string: a single line from the knowledge base file
--- @return string state: the state string key
--- @return table datum: array of {Idx: number, Prob: number} entries
local function deserialize(line)
    -- remove carriage return from line
    line = line:gsub("\r" , "")
    -- Strip line of any spaces
    line = line:gsub(" ", "")

    local state, datumStr = table.unpack(string.split(line, "|"))
    local pairs = string.split(datumStr or error("error spliting state data"), ",")
    local datum = {}
    for _, pair in ipairs(pairs) do
        local parts = string.split(pair, ":")
        table.insert(datum, {
            ["Idx"] = tonumber(parts[1]),
            ["Prob"] = tonumber(parts[2]),
        })
    end

    return state, datum
end

--- Serializes a state and its data table into a file-writable string.
--- Output format: "state|idx:prob,idx:prob,..."
--- @param state string: the state string key
--- @param data table: array of {Idx: number, Prob: number} entries
--- @return string: the serialized line
local function serialize(state, data)
    local datum = {}
    for _, parts in ipairs(data) do
        table.insert(datum, parts.Idx .. ":" .. parts.Prob)
    end
    return state .. "|" .. table.concat(datum, ",")
end



-------------------------------------------------------------------------------------
-- STATIC ATTRIBUTES ----------------------------------------------------------------
-------------------------------------------------------------------------------------

--- Shared static knowledge base. Holds the global state-probability table
--- for all agents. Only one instance should be initialized via KnowledgeBase.new().
local KnowledgeBase   = {}
KnowledgeBase.__index = KnowledgeBase
--- @type table<string, table>: maps state strings to arrays of {Idx, Prob} entries
KnowledgeBase.data = {}
--- @type string: path to the knowledge base file, set during initialization
KnowledgeBase.filePath = nil
---@type boolean: flag to let us know if the kbase has already been initialized
KnowledgeBase.initialized = false

-------------------------------------------------------------------------------------
-- METHODS --------------------------------------------------------------------------
-------------------------------------------------------------------------------------

--- Initializes the shared knowledge base by loading state data from a file.
--- If the file does not exist, an empty file will be created at the given path.
--- Should only be called once before any agents are constructed.
--- @param filePath string|nil: path to the knowledge base file (default: "./default-kb.txt")
function KnowledgeBase.new(filePath)
    -- set file path, defaults to ./default-kb.txt
    if KnowledgeBase.initialized then
        assert(KnowledgeBase.filePath ~= filePath, "GIVEN FILE PATHS DO NOT MATCH")
        return
    end

    KnowledgeBase.filePath = filePath or "./default-kb.txt"
    -- opens file for read 
	local file, err = io.open(KnowledgeBase.filePath, "r")
    -- if file does not exist, one will be made
	if not file then
		file, err = io.open(KnowledgeBase.filePath, "a")
		assert(file, err)
		file:close()
		file, err = io.open(KnowledgeBase.filePath, "r")
		assert(file, err)
	end

    -- splits and places state data into in-memory kb
    for line in file:lines() do
        local state, data = deserialize(line)
        KnowledgeBase.data[state] = data
    end
    file:close()
end

function KnowledgeBase.DataToSerialForm()
    local str = ""
    for state, data in pairs(KnowledgeBase.data) do
        local line = serialize(state, data)
        str = str .. line .. "\n"
    end

    return str
end

--- Persists the current in-memory knowledge base to the save file.
--- Overwrites the existing file contents entirely.sts the knowledge base to the save file
function KnowledgeBase.save()
    local file, err = io.open(KnowledgeBase.filePath, "w")
    assert(file, err)

    for state, data in pairs(KnowledgeBase.data) do
        local line = serialize(state, data) .. "\n"
        file.write(file, line)
    end

    file:close()
end

--- Merges an agent's updated states into the shared knowledge base.
--- Overwrites any existing entries for states present in agentUpdates.
--- Call KnowledgeBase.save() afterward to persist changes to disk.
--- @param agentUpdates table<string, table>: maps state strings to updated {Idx, Prob} arrays
function KnowledgeBase.update(agentUpdates)
    for state, data in pairs(agentUpdates) do
        KnowledgeBase.data[state] = data
    end
end

--- Adds a new state entry to the in-memory knowledge base.
--- Does not persist to disk; call KnowledgeBase.save() to write changes.
--- should be called immediately after a new state is discovered
--- @param state string: the state string key
--- @param datum table: array of {Idx: number, Prob: number} entries
function KnowledgeBase.addNewState(state, datum)
    KnowledgeBase.data[state] = datum
end

--- Tests to see if a given state exists in our knowledge base
--- @param state string: the state string key
--- @return boolean
function KnowledgeBase.stateExists(state)
    return KnowledgeBase.data[state] ~= nil
end

return KnowledgeBase