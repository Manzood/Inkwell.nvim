---@class ghostCursor.Context -- TODO maybe this should be renamed to ghostcursor
---@fields context string[]: Relevant context found from the buffer

--- Parses buffer to figure out nearby context
---@param lines string[]: The lines in the current buffer
---@return ghostCursor.Context: The relevant context determined from the buffer position
local parse_buffer = function(lines)
    local currentContext = { context = {} }
    for first, line in ipairs(lines) do
        print(first, line)
    end

    currentContext.context = lines

    return currentContext
end

local get_buffer = function()
    local cursorPosition = vim.api.nvim_win_get_cursor(0)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    print(unpack(cursorPosition))

    return table.concat(lines, "\n")
end

-- local context = get_buffer()
-- print("Context: ", context)

-- WORK IN PROGRESS
local prepare_query = function()

end