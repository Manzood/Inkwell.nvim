-- print "loaded ghostcursor.nvim"

-- require("query")

local M = {}

M.setup = function()
    -- nothing
end

-- USING THE ACTUAL API.

-- local response = query_groq(
--     "You are given the following context. Please change only a *single* line of the following context, to predict the next edit to this file. \
--     You may add, delete or simply modify certain parts of the file, as per your choosing. \
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
