local FileHelpers = {}
FileHelpers.__index = FileHelpers

function FileHelpers.split(str, sep)
    if not sep then
        sep = "%S"
    end

    local t = {} do
        for str in string.gmatch(str, "([^"..sep.."]+)") do
            table.insert(t, str)
        end
    end

    return t
end

return FileHelpers