-- local ns = vim.api.nvim_create_namespace("ghostcursor")
-- vim.api.nvim_buf_set_extmark(0, ns, 87, 10, {
--     -- virt_text = { { "← suggested edit\n\n\n\nHello", "Comment" } },
--     -- virt_text_pos = "inline",
--     virt_lines = { { "→ suggestion: log result", "Comment" } ,
--      { "→ maybe handle errors", "Comment"  },
--      { "→ return value", "Comment" } },
-- })

-- TODO you probably want to use your virutal lines in combination with the inline virtual line. Also, they need to be aligned correctly, to be able to suit cursor.
-- OR, maybe we let chatgpt handle that? Or have some sort of algo figure it out?
-- There will need to be a decent amount of processing and normalization to get this to work, but I should be able to manage it
-- vim.api.nvim_buf_set_extmark(0, ns, 94, 6, {
--     virt_lines = {
--         { { "→ suggestion: log result", "Comment" } },
--         { { "→ maybe handle errors", "Comment" } },
--         { { "→ return value", "Comment" } },
--     },
-- });


-- vim.api.nvim_buf_clear_namespace(0, ns, 0, -1);
