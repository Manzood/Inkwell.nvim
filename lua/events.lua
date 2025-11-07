require("query")

local api = vim.api
local timer = vim.loop.new_timer()

local current_request = nil

local function cancel_current_request()
    if current_request and not current_request:is_closing() then
        current_request:kill("sigterm") -- TODO or ignore it
        current_request = nil
    end
end

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


local cnt = 0
Send_query = debounce(function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")
    -- send to API here
    cnt = cnt + 1
    Last_Request_Id = Last_Request_Id + 1
    cancel_current_request()
    -- Query_via_cmd_line(GROQ_URL, content)
    local job_id = Query_Groq(content)
    -- local job_id = Query_Phi3(content)
    -- Parse_response(Sample_response)
    -- print("Query sent for buffer", bufnr, "with count", cnt)
end, 300)

-- TODO maybe this will already be created elsewhere
local group = api.nvim_create_augroup("GhostCursor", { clear = true })

-- TODO double check what TextChangedI is
api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args)
        -- You can now cancel pending API queries or debounce new ones here
        -- send current code to AI
        -- get suggestion back
        -- display the suggestion
        -- has to be async
        -- send_query(args.buf)
    end,
})

-- Have an event for insert enter
-- api.nvim_create_autocmd("InsertEnter", {
--     group = group,
--     callback = function(args)
--         print("InsertEnter in buffer:", args.buf)
--     end,
-- })

-- Trigger when leaving insert mode
api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function(args)
        print("InsertLeave in buffer:", args.buf)
        -- flush all autocomplete results (but keep suggestions elsewhere maybe?)
    end,
})

-- Handle buffer unload or wipeout (cleanup)
--[[ api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group = group,
    callback = function(args)
        print("Buffer unloaded:", args.buf)
        -- Cancel running async requests, free resources, etc.
    end,
}) ]]

-- create keybind to send query
api.nvim_set_keymap("n", "<leader>sq", ":lua Send_query(vim.api.nvim_get_current_buf())<CR>",
    { noremap = true, silent = true })
