-- function to replace a specific line in the buffer with the new line content
local function replace(line_nr, new_line_content) 
    vim.api.nvim_buf_set_lines(0, line_nr, line_nr + 1, false, { new_line_content })
end

-- vim.keymap.set("n", "<leader>dd", function()
--     local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
--     M.display_diff(cursor_line, "Hello world")
-- end, { noremap = true, silent = true, desc = "Ghostcursor: inline diff test" })

function Apply_Suggested_Change()
    print(vim.inspect(Previous_Query_Data))
    print(Current_Request_Id)
    if Current_Request_Id == Previous_Query_Data.request_id and Previous_Query_Data.valid_change then
        replace(Previous_Query_Data.line_number, Previous_Query_Data.suggested_line)
        Suggestion_Just_Accepted = true
    end
end
