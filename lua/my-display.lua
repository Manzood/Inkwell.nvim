local mdebug = require("debug-util").debug
local diff_highlights = require("diff-highlights")

M = {}

M.ignore_whitespace = false
--- in my-display.lua or a setup/init file

if not bit32 and bit then
  bit32 = {
    band  = bit.band,
    bor   = bit.bor,
    bxor  = bit.bxor,
    bnot  = bit.bnot,
    lshift = bit.lshift,
    rshift = bit.rshift,
  }
end

local dmp = require("diff_match_patch")
-- TODO implement toggle to consider or ignore whitespace

local ns = vim.api.nvim_create_namespace("my_inkwell_display_diff") -- TODO rename this better later

-- TODO we're going to come up with a better theme later
-- TODO add tests for checking how the diff library handles whitespace
function M.test_diff()
    local string1 = "Hi, this is a test string\n"
    local string2 = "Hi, this here string has some text\n"
    local testdiff = dmp.diff_main(string1, string2)
    dmp.diff_cleanupSemantic(testdiff)
    mdebug(vim.inspect((testdiff)))
end

function M.get_diff(cursor_line, new_content)
    -- what format should this be in?
    -- some kind of edit distance perhaps
    -- maybe show diff in terms of tokens that are words?
    -- cursor doesn't suggest changes *before* your current cursor position
    mdebug("printing calculated diff:")

    -- hunk diffs
    -- local hunks = vim.diff(current_content, new_content, {
    --     result_type = "indices",
    --     algorithm = "myers",
    -- })

    local current_content = vim.api.nvim_buf_get_lines(0, cursor_line, cursor_line + 1, false)[1]
    local diff = dmp.diff_main(current_content, new_content)
    dmp:diff_cleanupSemantic(diff)

    return diff
end

local function resolve_bufnr(opts)
    if opts and opts.bufnr then
        return opts.bufnr
    end
    return vim.api.nvim_get_current_buf()
end

local preview_state = {}

local function ensure_preview_table(bufnr)
    preview_state[bufnr] = preview_state[bufnr] or {}
    return preview_state[bufnr]
end

-- TODO we always want to close ALL previews when we clear.
-- Most likely, we can just implement it to reset the store entirely
local function close_preview(bufnr, line)
    local store = preview_state[bufnr]
    if not store then return end
    local entry = store[line]
    if not entry then return end
    if entry.win and vim.api.nvim_win_is_valid(entry.win) then
        pcall(vim.api.nvim_win_close, entry.win, true)
    end
    if entry.buf and vim.api.nvim_buf_is_valid(entry.buf) then
        pcall(vim.api.nvim_buf_delete, entry.buf, { force = true })
    end
    store[line] = nil
end

local function get_target_window(bufnr, opts)
    if opts and opts.win then
        return opts.win
    end
    if opts and opts.win_id then
        return opts.win_id
    end
    local wins = vim.fn.win_findbuf(bufnr)
    if wins and wins[1] then
        return wins[1]
    end
    return vim.api.nvim_get_current_win()
end

local function compute_window_row(win, line)
    local row
    vim.api.nvim_win_call(win, function()
        local topline = vim.fn.line("w0")
        row = line + 1 - topline
    end)
    row = row or 0 -- TODO probably not necessary. For now if row doesn't exist, I might want to throw an error
    local height = vim.api.nvim_win_get_height(win)
    -- TODO in the future, this would need to be changed when we want to display suggestions that make you jump around the file
    if row < 0 then
        -- TODO possibly debug here
        return nil
    elseif row >= height then
        return nil
    end
    return row
end

local function show_preview(bufnr, line, updated_line, opts, additions)
    local store = ensure_preview_table(bufnr)
    close_preview(bufnr, line)

    if not updated_line or updated_line == "" then
        return
    end

    local win = get_target_window(bufnr, opts)
    -- TODO possibly useless check
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local preview_buf = vim.api.nvim_create_buf(false, true) -- throwaway buffer
    -- TODO this will be redundant after adding multiline
    if updated_line:find("\n") then
        mdebug("updated_line contains newlines: ", updated_line)
    end

    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { updated_line })
    vim.api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf }) -- TODO why?

    local width = vim.fn.strdisplaywidth(updated_line)
    -- TODO why is this necessary?
    if width == 0 then
        width = 1
    end

    local row = compute_window_row(win, line)
    if not row then return end

    local popup_col = 0
    vim.api.nvim_win_call(win, function()
        local virt = vim.fn.virtcol({ line + 1, "$" })
        local info = vim.fn.getwininfo(win)[1] or {}
        local textoff = info.textoff or 0
        popup_col = math.max(0, (virt > 0 and virt - 1 or 0) + textoff) -- TODO virtcol only returns 0 in case of an error. So maybe change accordingly
    end)

    local configured_border = diff_highlights.config.preview.border
    local border = opts and opts.preview_border or configured_border
    border = border or "rounded"
    local has_border = border and border ~= "none" and border ~= false -- TODO double-check these checks
    local border_padding = has_border and 1 or 0

    local padding = (opts and opts.preview_padding) or diff_highlights.config.preview.padding or 2
    local row_offset = (opts and opts.preview_row_offset) or diff_highlights.config.preview.row_offset or 0
    local target_col = popup_col + padding + border_padding

    -- TODO verify the math yourself
    local win_width = vim.api.nvim_win_get_width(win)
    local effective_width = width + (has_border and 2 or 0)
    local max_col = math.max(0, win_width - effective_width)
    if target_col > max_col then
        target_col = max_col
    end

    -- TODO why is this initialized here?
    local float_opts = {
        relative = "win",
        win = win,
        row = math.max(row + row_offset, 0),
        col = target_col,
        width = width,
        height = 1,
        focusable = false,
        style = "minimal",
        border = border,
        noautocmd = true,
    }

    local preview_win = vim.api.nvim_open_win(preview_buf, false, float_opts)

    --TODO verify this as well
    local winhl = (opts and opts.preview_winhl) or diff_highlights.config.preview.winhl
    if winhl then
        local winhl_str
        if type(winhl) == "table" then
            local parts = {}
            for from, to in pairs(winhl) do
                if type(from) == "string" and type(to) == "string" and to ~= "" then
                    table.insert(parts, string.format("%s:%s", from, to))
                end
            end
            table.sort(parts)
            if #parts > 0 then
                winhl_str = table.concat(parts, ",")
            end
        elseif type(winhl) == "string" then
            winhl_str = winhl
        end
        if winhl_str and winhl_str ~= "" then
            pcall(vim.api.nvim_set_option_value, "winhl", winhl_str, { win = preview_win })
        end
    end

    local preview_hl = (opts and opts.preview_hl) or diff_highlights.config.preview.hl_group or diff_highlights.default_highlights.preview

    -- TODO if preview_hl is not set by this point we have a problem
    if preview_hl then
        for _, seg in ipairs(additions) do
            vim.api.nvim_buf_add_highlight(preview_buf, ns, preview_hl, 0, seg[1] - 1, seg[2] - 1)
        end
    end

    store[line] = {
        win = preview_win,
        buf = preview_buf,
    }
end

M.clear = function(opts)
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    opts = opts or {}
    local bufnr = resolve_bufnr(opts)
    local line = opts.line
    if line == nil then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
        local store = preview_state[bufnr]
        if store then
            for l, _ in pairs(store) do
                close_preview(bufnr, l)
            end
            preview_state[bufnr] = nil
        end
    else
        vim.api.nvim_buf_clear_namespace(bufnr, ns, line, line + 1)
        close_preview(bufnr, line)
    end
end

-- three cases
-- 1) only additive changes: Simple ghost text should do
-- 2) only deletions: just make whatever needs to go red
-- 3) both. Make deletions read, and have a floating box to the side that shows what will replace it (with additions marked in green)
-- TODO we're not using the options just yet. Although we probably should if the user switches to another buffer by the time the code completion shows up
M.display_diff = function (cursor_line, new_content, opts)
    opts = opts or {}
    local bufnr = resolve_bufnr(opts)

    diff_highlights.ensure_highlights()
    M.clear({ bufnr = bufnr })

    local diff = M.get_diff(cursor_line, new_content)
    local iter1 = 1
    local iter2 = 1
    local red_positions = {}
    local green_positions = {}

    for _, diff in ipairs(diff) do
        if diff[1] == 0 then
            iter1 = iter1 + #diff[2]
            iter2 = iter2 + #diff[2]
        elseif diff[1] == 1 then
            -- display as green in pop up box
            table.insert(green_positions, {iter2, iter2 + #diff[2]})
            iter2 = iter2 + #diff[2]
        elseif diff[1] == -1 then
            -- display as red on current line
            table.insert(red_positions, {iter1, iter1 + #diff[2]})
            iter1 = iter1 + #diff[2]
        end
    end

    local current_line = vim.api.nvim_buf_get_lines(0, cursor_line, cursor_line + 1, false)[1]

    if #green_positions == 0 then 
        for _, pos in ipairs(red_positions) do
            vim.api.nvim_buf_set_extmark(0, ns, cursor_line, pos[1] - 1, {
                end_row = cursor_line,
                end_col = math.min(#current_line, pos[2] - 1), 
                hl_group = "InkWellDiffDelete",
                hl_eol = false,
                priority = 1000,
            })
        end
    elseif #red_positions == 0 then
        -- write the additive stuff as ghost text
        for _, pos in ipairs(green_positions) do
            vim.api.nvim_buf_set_extmark(0, ns, cursor_line, math.min(#current_line, pos[1]), {
                virt_text = {{new_content:sub(pos[1], pos[2]), "InkWellDiffAdd"}}, -- TODO need a better floating text highlight group
                virt_text_pos = "inline",
                priority = 1000,
                right_gravity = false,
                virt_text_hide = false -- TODO what is this and why is it necessary
            })
        end
    else
        -- both
        for _, pos in ipairs(red_positions) do
            vim.api.nvim_buf_set_extmark(0, ns, cursor_line, pos[1] - 1, {
                end_row = cursor_line,
                end_col = math.min(#current_line, pos[2] - 1), 
                hl_group = "InkWellDiffDelete",
                hl_eol = false,
                priority = 1000,
            })
        end
        show_preview(bufnr, cursor_line, new_content, opts, green_positions)
    end

    -- need a pop up box first
    -- for start_pos, end_pos in ipairs(green_positions) do
    --     vim.api.nvim_buf_set_extmark(0, ns, cursor_line, start_pos, {
    --         end_row = cursor_line,
    --         end_col = end_pos,
    --         hl_group = "InkWellDiffAdd",
    --         hl_eol = false,
    --         priority = 1000,
    --     })
    -- end
end

return M