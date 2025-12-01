local mdebug = require("debug-util").debug
local diff_highlights = require("diff-highlights")

M = {}

M.ignore_whitespace = false
--- in my-display.lua or a setup/init file

if not bit32 and bit then
    bit32 = {
        band   = bit.band,
        bor    = bit.bor,
        bxor   = bit.bxor,
        bnot   = bit.bnot,
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

function M.get_diff_single_line(cursor_line, new_content)
    -- what format should this be in?
    -- some kind of edit distance perhaps
    -- maybe show diff in terms of tokens that are words?
    -- cursor doesn't suggest changes *before* your current cursor position

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

function M.get_diff(line_start, line_end, new_lines)
    -- what format should this be in?
    -- some kind of edit distance perhaps
    -- maybe show diff in terms of tokens that are words?
    -- cursor doesn't suggest changes *before* your current cursor position

    -- hunk diffs
    -- local hunks = vim.diff(current_content, new_content, {
    --     result_type = "indices",
    --     algorithm = "myers",
    -- })

    local current_content = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
    current_content = table.concat(current_content, "\n")
    if current_content == nil then
        current_content = ""
    end
    local diff = dmp.diff_main(current_content, table.concat(new_lines, "\n"))
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

local function show_single_line_preview(bufnr, line, updated_line, opts, additions)
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

    local preview_hl = (opts and opts.preview_hl) or diff_highlights.config.preview.hl_group or
    diff_highlights.default_highlights.preview

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

local function show_preview(bufnr, patch, opts, additions)
    opts = opts or {}
    local api = vim.api
    local ns = ns

    -- Prepare patch lines
    local lines = patch and patch.new_lines or {}
    if type(lines) == "string" then
        lines = vim.split(lines, "\n")
    end
    if not lines or #lines == 0 then
        return
    end

    -- Create preview buffer
    local preview_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(preview_buf, "buftype", "nofile")
    api.nvim_buf_set_option(preview_buf, "bufhidden", "wipe")
    api.nvim_buf_set_option(preview_buf, "modifiable", true)
    api.nvim_buf_set_option(preview_buf, "filetype", api.nvim_buf_get_option(0, "filetype"))

    api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
    api.nvim_buf_set_option(preview_buf, "modifiable", false)

    -- Calculate floating window dimensions
    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(l or ""))
    end
    local height = #lines
    width = math.max(width, 10)
    height = math.max(height, 1)

    -- Try to position to the right of main buffer, middle of the displayed area
    local row = math.max(2, math.floor(vim.o.lines / 2 - height / 2))
    local col = math.max(5, math.floor(vim.o.columns / 2 - width / 2))

    local preview_win = api.nvim_open_win(preview_buf, false, {
        relative = "editor",
        anchor = "NW",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        noautocmd = true,
        focusable = false,
    })

    -- Optionally highlight window
    if opts.preview_winhl or diff_highlights and diff_highlights.config and diff_highlights.config.preview and diff_highlights.config.preview.winhl then
        local winhl_str = opts.preview_winhl or diff_highlights.config.preview.winhl
        if winhl_str and winhl_str ~= "" then
            pcall(vim.api.nvim_set_option_value, "winhl", winhl_str, { win = preview_win })
        end
    end

    -- Highlight additions (green) in the preview buffer
    local preview_hl = (opts and opts.preview_hl) or
    (diff_highlights and diff_highlights.config and diff_highlights.config.preview and diff_highlights.config.preview.hl_group) or
    (diff_highlights and diff_highlights.default_highlights and diff_highlights.default_highlights.preview) or "DiffAdd"

    -- `additions` is an array of {line_idx, start_col, end_col} (1-indexed!)
    if preview_hl and additions then
        for _, seg in ipairs(additions) do
            local line_idx = seg[1]
            local start_col = seg[2]
            local end_col = seg[3]
            -- Defensive: adjust for 1-based to 0-based indexing
            if lines[line_idx] then
                api.nvim_buf_add_highlight(preview_buf, ns, preview_hl, line_idx - 1, start_col - 1, end_col - 1)
            end
        end
    end

    -- State keeping so we can later clear this preview if needed
    preview_state = preview_state or {}
    preview_state[bufnr] = preview_state[bufnr] or {}
    local line = opts.line or 0
    preview_state[bufnr][line] = {
        win = preview_win,
        buf = preview_buf,
    }
end

-- three cases
-- 1) only additive changes: Simple ghost text should do
-- 2) only deletions: just make whatever needs to go red
-- 3) both. Make deletions read, and have a floating box to the side that shows what will replace it (with additions marked in green)
-- TODO we're not using the options just yet. Although we probably should if the user switches to another buffer by the time the code completion shows up
M.display_single_line_diff = function(cursor_line, new_content, opts)
    opts = opts or {}
    local bufnr = resolve_bufnr(opts)

    diff_highlights.ensure_highlights()
    M.clear({ bufnr = bufnr })

    local diff = M.get_diff_single_line(cursor_line, new_content[1])
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
            table.insert(green_positions, { iter2, iter2 + #diff[2] })
            iter2 = iter2 + #diff[2]
        elseif diff[1] == -1 then
            -- display as red on current line
            table.insert(red_positions, { iter1, iter1 + #diff[2] })
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
            vim.api.nvim_buf_set_extmark(0, ns, cursor_line, math.min(#current_line, pos[1] - 1), {
                virt_text = { { new_content[1]:sub(pos[1], pos[2] - 1), "InkWellDiffAdd" } }, -- TODO need a better floating text highlight group
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
        show_single_line_preview(bufnr, cursor_line, new_content[1], opts, green_positions)
    end
end

-- mimicking lower_bound from C++
local lower_bound = function(tbl, value, comparator)
    local low = 1
    local high = #tbl
    local ret = #tbl + 1
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if comparator(tbl[mid], value) then
            ret = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return ret
end

local function get_all_including_red(start_index, end_index, red_positions)
    -- binary search for the first index in red_positions where red_positions[index][2] >= start_index
    -- binary search for the last index in red_positions where red_positions[index][1] <= end_index
    local f = lower_bound(red_positions, start_index, function(a, b) return a[2] >= b end)
    local s = lower_bound(red_positions, end_index, function(a, b) return a[1] <= b end)
    s = math.min(s, #red_positions)
    mdebug("red_positions: ", vim.inspect(red_positions))
    mdebug("f: ", f, "s: ", s, "start_index: ", start_index, "end_index: ", end_index)
    local positions = {}
    for i = f, s do
        local current_val = { math.max(red_positions[i][1], start_index) - start_index + 1, math.min(red_positions[i][2],
            end_index) - start_index + 1 }
        mdebug("current_val: ", vim.inspect(current_val))
        table.insert(positions, current_val)
    end
    mdebug("positions: ", vim.inspect(positions))
    return positions
end

local function get_all_including_green(start_index, end_index, green_positions)
    local f = lower_bound(green_positions, start_index, function(a, b) return a[1] >= b end)
    local s = lower_bound(green_positions, end_index, function(a, b) return a[1] <= b end)
    s = math.min(s, #green_positions)
    mdebug("green_positions: ", vim.inspect(green_positions))
    mdebug("f: ", f, "s: ", s, "start_index: ", start_index, "end_index: ", end_index)
    -- TODO s is not required in this function, we can just iterate until the condition is false
    local positions = {}
    for i = f, s do
        local difference = green_positions[i][2] - green_positions[i][1]
        local insertion_index = math.max(green_positions[i][1], start_index) - start_index + 1
        local current_val = { insertion_index, insertion_index + difference }
        table.insert(positions, current_val)
    end
    return positions
end

M.display_diff = function(patch, opts)
    print("patch: ", vim.inspect(patch))
    -- TODO check if the patch is visible on screen
    opts = opts or {}
    local bufnr = resolve_bufnr(opts)

    diff_highlights.ensure_highlights()
    M.clear({ bufnr = bufnr })

    local current_content = vim.api.nvim_buf_get_lines(0, patch.line_start - 1, patch.line_end, false)
    current_content = table.concat(current_content, "\n")
    if current_content == nil then
        current_content = ""
    end
    local diff = M.get_diff(patch.line_start, patch.line_end, patch.new_lines)
    mdebug("diff: ", vim.inspect(diff))

    local original_iter = 1
    local red_positions = {}
    local green_positions = {}
    local patch_green_positions = {}
    local addition_reference = {}
    local patch_iter = 1

    for _, diff in ipairs(diff) do
        if diff[1] == 0 then
            original_iter = original_iter + #diff[2]
            patch_iter = patch_iter + #diff[2]
        elseif diff[1] == 1 then
            -- insert BEFORE original_iter
            table.insert(addition_reference, { patch_iter, patch_iter + #diff[2] - 1 })
            -- TODO the end index above is inclusive, but exclusive in green_positions. Make it consistent.
            -- I can simply just drop the third index below. It adds nothing since we can look up the length thanks to addition_reference
            table.insert(green_positions, { original_iter, original_iter + #diff[2], #addition_reference })
            table.insert(patch_green_positions, { patch_iter, patch_iter + #diff[2] })
            patch_iter = patch_iter + #diff[2]
        elseif diff[1] == -1 then
            table.insert(red_positions, { original_iter, original_iter + #diff[2] })
            original_iter = original_iter + #diff[2]
        end
    end

    -- adjust red and green positions to do it on a per-line basis
    local adjusted_red_positions = {}
    local adjusted_green_positions = {}
    local line_number = patch.line_start

    -- TODO assert that both red_positions and green_positions are already sorted
    local line_start_index = 1
    for iter = 1, #current_content do
        if current_content:sub(iter, iter) == "\n" or iter == #current_content then
            local found_positions = get_all_including_red(line_start_index, iter, red_positions)
            for _, position in ipairs(found_positions) do
                table.insert(adjusted_red_positions, { line_number, position[1], position[2] })
            end
            line_number = line_number + 1
            line_start_index = iter + 1
        end
    end
    mdebug("red_positions: ", vim.inspect(red_positions))
    mdebug("adjusted_red_positions: ", vim.inspect(adjusted_red_positions))

    line_number = patch.line_start
    -- TODO the snippet below can just take in a function and a table as an argument and be the same as the snippet above
    line_start_index = 1
    -- print("current_content: ", current_content)
    mdebug("current_content: ", current_content)
    for iter = 1, #current_content + 1 do
        if iter > #current_content or current_content:sub(iter, iter) == "\n" then
            local line_end_index = iter
            mdebug("line_start_index: ", line_start_index, "line_end_index: ", line_end_index)
            local found_positions = get_all_including_green(line_start_index, line_end_index, green_positions)
            for index, position in ipairs(found_positions) do
                local difference = green_positions[index][2] - green_positions[index][1]
                table.insert(adjusted_green_positions,
                    { line_number, position[1], position[1] + difference, green_positions[index][3] })                                  -- TODO double-check if this works
            end
            line_number = line_number + 1
            line_start_index = iter + 1
        end
    end

    mdebug("addition_reference: ", vim.inspect(addition_reference))
    mdebug("green_positions: ", vim.inspect(green_positions))
    mdebug("adjusted_green_positions: ", vim.inspect(adjusted_green_positions))

    local concatenated_patch = table.concat(patch.new_lines, "\n")

    if #green_positions == 0 then
        for _, pos in ipairs(adjusted_red_positions) do
            local current_line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]
            mdebug("pos: ", vim.inspect(pos))
            vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, pos[2] - 1, {
                end_row = pos[1] - 1,
                end_col = math.min(#current_line, pos[3]), -- need to provide one column to the right since it is zero-based exclusive
                hl_group = "InkWellDiffDelete",
                hl_eol = false,
                priority = 1000
            })
        end
    elseif #red_positions == 0 then
        for _, pos in ipairs(adjusted_green_positions) do
            local current_line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]
            local start_index = addition_reference[pos[4]][1]
            local end_index = addition_reference[pos[4]][2]
            local insert_text = concatenated_patch:sub(start_index, end_index)
            local insert_lines_raw = vim.split(insert_text, "\n")

            if #insert_lines_raw >= 1 then
                local first_line = insert_lines_raw[1]
                vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, math.min(#current_line, pos[2] - 1), {
                    virt_text = { { first_line, "InkWellDiffAdd" } },
                    virt_text_pos = "inline",
                    priority = 1000,
                })
            end
            if #insert_lines_raw > 1 then
                local virt_lines = {}
                for i = 2, #insert_lines_raw do
                    table.insert(virt_lines, { { insert_lines_raw[i], "InkWellDiffAdd" } })
                end
                vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, math.min(#current_line, pos[2] - 1), {
                    virt_lines = virt_lines,
                    virt_lines_above = false,
                    priority = 1000,
                })
            end
        end
    else
        for _, pos in ipairs(adjusted_red_positions) do
            local current_line = vim.api.nvim_buf_get_lines(0, pos[1] - 1, pos[1], false)[1]
            vim.api.nvim_buf_set_extmark(0, ns, pos[1] - 1, pos[2] - 1, {
                end_row = pos[1] - 1,
                end_col = math.min(#current_line, pos[3]),
                hl_group = "InkWellDiffDelete",
                hl_eol = false,
                priority = 1000,
            })
        end
        -- TODO we don't want to show a bunch of previews. We want to show one big preview
        show_preview(bufnr, patch, opts, patch_green_positions)
    end
end

return M
