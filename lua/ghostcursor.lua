-- print "loaded ghostcursor.nvim"

-- require("query")

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
    "c++",
    "c#"
}

local function is_allowed_filetype(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    return vim.tbl_contains(allowed_filetypes, filetype)
end

if is_allowed_filetype(vim.api.nvim_get_current_buf()) then
    require("events")
end

local M = {}

-- USING THE ACTUAL API.
--     If you cannot think of a reasonable change to make, please output nothing. Your context begins here:\n\n" .. context)

-- print("\n\n\n\n" .. response)

-- vim.print(parse_buffer {
--     "int main() {",
--     "    int t;",
--     "    cin >> t;",
--     "    cout << t << endl;",
--     "    return 0;",
--     "}",
-- })

return M
