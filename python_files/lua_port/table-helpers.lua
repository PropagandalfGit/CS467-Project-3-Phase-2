local TableHelpers = {}
TableHelpers.__index = TableHelpers

---@param tbl table
---@return table
function TableHelpers.freeze(tbl)
    return setmetatable({}, {
        __index = tbl,
        __newindex = function(_, k, v)
            error("Indexing into frozen table forbidden", 2)
        end,
        __metatable = false
    })
end

function TableHelpers.updateTable(oldT, newT)
    for key, value in pairs(newT) do
        if not oldT[key] or oldT[key] ~= value then
            oldT[key] = value
        end
    end

    for key, _ in pairs(oldT) do
        if not newT[key] then
            oldT[key] = nil
        end
    end
end

---This is a shallow copy
---@param orig table
---@return table
function TableHelpers.copy(orig)
    local copy = {} do
        for k, v in pairs(orig) do
            copy[k] = v
        end
    end
    
    return copy
end

return TableHelpers