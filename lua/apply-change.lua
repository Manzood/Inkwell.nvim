local display_diff = require("display-diff")
local my_display = require("my-display")
local mdebug = require("debug-util").debug

-- function to replace a specific line in the buffer with the new line content
local function replace(line_nr, new_line_content) 
    -- nvim_buf_set_lines takes a 0-indexed line number
    vim.api.nvim_buf_set_lines(0, line_nr - 1, line_nr, false, { new_line_content })
end

-- vim.keymap.set("n", "<leader>dd", function()
--     local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
--     M.display_diff(cursor_line, "Hello world")
-- end, { noremap = true, silent = true, desc = "InkWell: inline diff test" })

function Apply_Suggested_Change()
    local deleted_line_count = 0
    table.sort(Previous_Query_Data.suggested_changes.patches, function(a, b) return a.line_start < b.line_start end)
    -- TODO add validation check to see that none of the queries are overlapping
    mdebug("Previous_Query_Data.suggested_changes: ", vim.inspect(Previous_Query_Data.suggested_changes))
    if not Suggestion_Just_Accepted and Current_Request_Id == Previous_Query_Data.request_id and Previous_Query_Data.valid_change then
        for _, patch in ipairs(Previous_Query_Data.suggested_changes.patches) do
            -- TODO possibly clean up the delete line logic
            if patch.line_start > patch.line_end or (patch.line_start == patch.line_end and patch.delete_line and patch.delete_line == true) then
                mdebug("Deleting line")
                deleted_line_count = deleted_line_count + 1
                vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), patch.line_start - deleted_line_count, patch.line_start - deleted_line_count + 1, false, {})
            else
                mdebug("Replacing lines")
                mdebug("patch.line_start: ", patch.line_start, "patch.line_end: ", patch.line_end, "patch.new_lines: ", vim.inspect(patch.new_lines))
                for i = patch.line_start, patch.line_end do
                    mdebug("Replacing line: ", i - deleted_line_count, "with: ", patch.new_lines[i - patch.line_start + 1])
                    replace(i - deleted_line_count, patch.new_lines[i - patch.line_start + 1])
                end
            end
        end
        my_display.clear({ bufnr = vim.api.nvim_get_current_buf() })
        Suggestion_Just_Accepted = true
    end
end
