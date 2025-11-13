require("query")
require("apply-change")

local api = vim.api
local timer = vim.loop.new_timer()
local mdebug = require("debug-util").debug

local function debounce(fn, ms)
    return function(...)
        local args = { ... }
        timer:stop()
        -- TODO schedule_wrap?
        timer:start(ms, 0, function()
            vim.schedule(function() fn(unpack(args)) end)
        end)
    end
end

Send_Query = debounce(function(bufnr)
    if Suggestion_Just_Accepted then
        Suggestion_Just_Accepted = false
        return
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    Current_Request_Id = Current_Request_Id + 1
    local job_id = Query_Groq(content)
    -- local job_id = Query_Phi3(content)
end, 1000) -- TODO set something better as the value. It used to be 300ms

-- TODO maybe this will already be created elsewhere
local group = api.nvim_create_augroup("GhostCursor", { clear = true })
local bufnr = api.nvim_get_current_buf()

-- TODO double check what TextChangedI is
api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function(args)
        -- Send_Query(vim.api.nvim_get_current_buf())
        -- You can now cancel pending API queries or debounce new ones here
        -- send current code to AI
        -- get suggestion back
        -- display the suggestion
        -- has to be async
        -- send_query(args.buf)
        Send_Query(args.buf)
    end,
})

-- TODO check what happens when a buffer is closed before the async request is finished
-- it hasn't caused any issues so far in my testing though
-- Handle buffer unload or wipeout (cleanup)
--[[ api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(args)
        mdebug("Buffer unloaded:", args.buf)
        -- Cancel running async requests, free resources, etc.
    end,
}) ]]

-- tab completion keybind
api.nvim_set_keymap("n", "<Tab>", ":lua Apply_Suggested_Change()<CR>",
    { noremap = true, silent = true })

-- create keybind to send query
api.nvim_set_keymap("n", "<leader>sq", ":lua Send_Query(vim.api.nvim_get_current_buf())<CR>",
    { noremap = true, silent = true })

-- api.nvim_set_keymap("n", "<leader>ac", ":lua Apply_Suggested_Change()<CR>",
--     { noremap = true, silent = true })