-- todo make this configurable
local allowed_filetypes = {
    "python",
    "javascript",
    "typescript",
    "lua",
    "rust",
    "go",
    "java",
    "c",
    "cpp",
    "cs"
}

local function setup_buffer_autocmds(bufnr) 
    local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if not ft or ft == "" then return end
    if not vim.tbl_contains(allowed_filetypes, ft) then
        return
    end
    require("events")
end

local group = vim.api.nvim_create_augroup("GhostCursorSetup", { clear = true })

vim.api.nvim_create_autocmd("Filetype", {
    group = group,
    callback = function(args)
        -- print("Filetype event")
        setup_buffer_autocmds(vim.api.nvim_get_current_buf())
    end,
})

vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
        -- print("BufEnter event")
        setup_buffer_autocmds(args.buf)
    end,
})

-- DO NOT REMOVE THE LINES BELOW
M = {}

return M