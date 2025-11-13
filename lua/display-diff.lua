local mdebug = require("debug-util").debug
local M = {}

local ns = vim.api.nvim_create_namespace("ghostcursor_display_diff")

local default_highlights = {
    add = "GhostcursorGhostText",
    delete = "GhostcursorDiffDelete",
    preview = "GhostcursorDiffPreview",
}

local highlight_initialized = false
local preview_state = {}
local config = {
    preview = {
        border = "rounded",
        padding = 2,
        row_offset = -1,
        hl_group = default_highlights.preview,
        highlight = nil,
        winhl = nil,
        winhl_highlights = nil,
    },
}

local presets = {
    serene = {
        preview = {
            border = "rounded",
            padding = 2,
            row_offset = -1,
            hl_group = "GhostcursorPreviewSerene",
            highlight = {
                fg = "#bac8ff",
                bg = "#1f2335",
                italic = true,
            },
        },
    },
    neon = {
        preview = {
            border = "single",
            padding = 1,
            row_offset = -1,
            hl_group = "GhostcursorPreviewNeon",
            highlight = {
                fg = "#00f1ff",
                bg = "#121212",
                bold = true,
            },
        },
    },
    dusk = {
        preview = {
            border = "none",
            padding = 1,
            row_offset = 0,
            hl_group = "GhostcursorPreviewDusk",
            highlight = {
                fg = "#f5d7b5",
                bg = "#221b29",
            },
        },
    },
    minimal = {
        preview = {
            border = "none",
            padding = 1,
            row_offset = 0,
            hl_group = "GhostcursorPreviewMinimal",
            highlight = {
                fg = "#c8d0e0",
                bg = "#1b1d23",
            },
        },
    },
    compact = {
        preview = {
            border = "rounded",
            padding = 0,
            row_offset = -1,
            hl_group = "GhostcursorPreviewCompact",
            highlight = {
                fg = "#b0c4de",
                bg = "#1f2430",
            },
            winhl = {
                NormalFloat = "GhostcursorPreviewCompactFloat",
                FloatBorder = "GhostcursorPreviewCompactBorder",
            },
            winhl_highlights = {
                GhostcursorPreviewCompactFloat = {
                    bg = "#1f2430",
                },
                GhostcursorPreviewCompactBorder = {
                    fg = "#2c3742",
                    bg = "#1f2430",
                },
            },
        },
    },
    slimline = {
        preview = {
            border = "single",
            padding = 0,
            row_offset = -1,
            hl_group = "GhostcursorPreviewSlimText",
            highlight = {
                fg = "#67e8f9",
                bg = "#10131b",
            },
            winhl = {
                NormalFloat = "GhostcursorPreviewSlimFloat",
                FloatBorder = "GhostcursorPreviewSlimBorder",
            },
            winhl_highlights = {
                GhostcursorPreviewSlimFloat = {
                    bg = "#10131b",
                },
                GhostcursorPreviewSlimBorder = {
                    fg = "#1d222e",
                    bg = "#10131b",
                },
            },
        },
    },
    aurora = {
        preview = {
            border = "double",
            padding = 1,
            row_offset = -1,
            hl_group = "GhostcursorPreviewAurora",
            highlight = {
                fg = "#9ce5ff",
                bg = "#11212f",
            },
        },
    },
}

local function merge_config(target, overrides)
    if type(overrides) ~= "table" then
        return
    end
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(target[key]) == "table" then
            merge_config(target[key], value)
        else
            target[key] = value
        end
    end
end

local function highlight_exists(group)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = true })
    if not ok or not hl then
        return false
    end
    if hl.link then
        return true
    end
    return next(hl) ~= nil -- TODO why is this necessary?
end

local function ensure_highlights()
    if highlight_initialized then
        return
    end

    local preview_group = config.preview.hl_group or default_highlights.preview

    local groups = {
        add = default_highlights.add,
        delete = default_highlights.delete,
        preview = preview_group,
    }

    for kind, group in pairs(groups) do
        if highlight_exists(group) then
            goto continue
        end

        if kind == "add" then
            local comment_hl = vim.tbl_extend("force", {},
                vim.api.nvim_get_hl(0, { name = "Comment", link = false }) or {})
            if next(comment_hl) then
                vim.api.nvim_set_hl(0, group, {
                    default = true,
                    blend = 35,
                    fg = comment_hl.fg,
                    italic = comment_hl.italic,
                })
            else
                vim.api.nvim_set_hl(0, group, {
                    link = "Comment",
                    default = true,
                })
            end
        elseif kind == "delete" then
            vim.api.nvim_set_hl(0, group, { link = "DiffDelete", default = true })
        elseif kind == "preview" then
            local spec = config.preview.highlight
            if type(spec) == "table" and next(spec) then
                vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { default = true }, spec))
            else
                vim.api.nvim_set_hl(0, group, { link = "DiffAdd", default = true })
            end
        end

        ::continue::
    end

    local winhl_specs = config.preview.winhl_highlights
    if type(winhl_specs) == "table" then
        for group, spec in pairs(winhl_specs) do
            if type(group) == "string" and type(spec) == "table" and next(spec) and not highlight_exists(group) then
                vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { default = true }, spec))
            end
        end
    end

    highlight_initialized = true
end

local function to_chars(str)
    local chars = {}
    for c in str:gmatch(".") do
        table.insert(chars, c)
    end
    return chars
end

-- TODO cross check if this is necessary
local function ensure_preview_table(bufnr)
    preview_state[bufnr] = preview_state[bufnr] or {}
    return preview_state[bufnr]
end

local function close_preview(bufnr, line)
    local store = preview_state[bufnr]
    if not store then
        return
    end
    local entry = store[line]
    if not entry then
        return
    end
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
    if not vim.api.nvim_win_is_valid(win) then
        return 0
    end
    vim.api.nvim_win_call(win, function()
        local topline = vim.fn.line("w0")
        row = line + 1 - topline
    end)
    row = row or 0
    local height = vim.api.nvim_win_get_height(win)
    if row < 0 then
        row = 0
    elseif row >= height then
        row = height - 1
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
    if not win or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local preview_buf = vim.api.nvim_create_buf(false, true)
    -- if updated line contains newlines
    if updated_line:find("\n") then
        mdebug("updated_line contains newlines: ", updated_line)
    end
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { updated_line })
    vim.api.nvim_set_option_value("modifiable", false, { buf = preview_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })

    local width = vim.fn.strdisplaywidth(updated_line)
    if width == 0 then
        width = 1
    end

    local row = compute_window_row(win, line)

    local ghost_col = 0
    vim.api.nvim_win_call(win, function()
        local virt = vim.fn.virtcol({ line + 1, "$" })
        local info = vim.fn.getwininfo(win)[1] or {}
        local textoff = info.textoff or 0
        ghost_col = math.max(0, (virt > 0 and virt - 1 or 0) + textoff)
    end)

    local configured_border = config.preview.border
    local border = opts and opts.preview_border
    if border == nil then
        border = configured_border
    end
    if border == nil then
        border = "rounded"
    end
    local has_border = border and border ~= "none" and border ~= false
    local border_padding = has_border and 1 or 0

    local padding = (opts and opts.preview_padding) or config.preview.padding or 2
    local row_offset = (opts and opts.preview_row_offset) or config.preview.row_offset or 0
    local target_col = ghost_col + padding + border_padding

    local win_width = vim.api.nvim_win_get_width(win)
    local effective_width = width + (has_border and 2 or 0)
    local max_col = math.max(0, win_width - effective_width)
    if target_col > max_col then
        target_col = max_col
    end

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

    local winhl = (opts and opts.preview_winhl) or config.preview.winhl
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

    local preview_hl = (opts and opts.preview_hl) or config.preview.hl_group or default_highlights.preview

    if additions and preview_hl then
        for _, seg in ipairs(additions) do
            local start_col = seg.preview_col or 0
            local end_col = start_col + vim.fn.strdisplaywidth(seg.text)
            vim.api.nvim_buf_add_highlight(preview_buf, ns, preview_hl, 0, start_col, end_col)
        end
    end

    store[line] = {
        win = preview_win,
        buf = preview_buf,
    }
end

local function build_diff(original_chars, updated_chars)
    local m = #original_chars
    local n = #updated_chars

    local dp = {}
    for i = 0, m do
        dp[i] = {}
        dp[i][0] = 0
    end
    for j = 0, n do
        dp[0][j] = 0
    end

    for i = 1, m do
        for j = 1, n do
            if original_chars[i] == updated_chars[j] then
                dp[i][j] = dp[i - 1][j - 1] + 1
            else
                local prev_row = dp[i - 1][j] or 0
                local prev_col = dp[i][j - 1] or 0
                dp[i][j] = prev_row > prev_col and prev_row or prev_col
            end
        end
    end

    local ops = {}

    local function backtrack(i, j)
        if i > 0 and j > 0 and original_chars[i] == updated_chars[j] then
            backtrack(i - 1, j - 1)
            table.insert(ops, { type = "equal", text = original_chars[i] })
        elseif j > 0 and (i == 0 or (dp[i] and dp[i][j - 1] or 0) >= (dp[i - 1] and dp[i - 1][j] or 0)) then
            backtrack(i, j - 1)
            table.insert(ops, { type = "add", text = updated_chars[j] })
        elseif i > 0 then
            backtrack(i - 1, j)
            table.insert(ops, { type = "delete", text = original_chars[i] })
        end
    end

    backtrack(m, n)

    if #ops == 0 then
        return ops
    end

    local merged = {}
    local current = { type = ops[1].type, text = ops[1].text }

    for idx = 2, #ops do
        local op = ops[idx]
        if op.type == current.type then
            current.text = current.text .. op.text
        else
            table.insert(merged, current)
            current = { type = op.type, text = op.text }
        end
    end
    table.insert(merged, current)

    return merged
end

local function compute_inline_diff(original, updated)
    if original == updated then
        return {}
    end

    local original_chars = to_chars(original or "")
    local updated_chars = to_chars(updated or "")
    return build_diff(original_chars, updated_chars)
end

local function apply_diff(bufnr, line, ops, opts, updated_line)
    opts = opts or {}
    if #ops == 0 then
        close_preview(bufnr, line)
        return
    end

    local add_hl = opts.add_hl or default_highlights.add
    local delete_hl = opts.delete_hl or default_highlights.delete
    local priority = opts.priority or 2000
    local virt_text_pos = opts.virt_text_pos or "inline"

    local orig_col = 0
    local preview_col = 0
    local has_add, has_delete = false, false
    local additions = {}
    local deletions = {}

    for _, op in ipairs(ops) do
        local text = op.text or ""
        if op.type == "equal" then
            local width = #text
            orig_col = orig_col + width
            preview_col = preview_col + width
        elseif op.type == "delete" then
            has_delete = true
            local width = #text
            table.insert(deletions, { col = orig_col, width = width })
            orig_col = orig_col + width
        elseif op.type == "add" then
            has_add = true
            table.insert(additions, { orig_col = orig_col, preview_col = preview_col, text = text })
            preview_col = preview_col + #text
        end
    end

    for _, span in ipairs(deletions) do
        vim.api.nvim_buf_set_extmark(bufnr, ns, line, span.col, {
            end_row = line,
            end_col = span.col + span.width,
            hl_group = delete_hl,
            hl_eol = false,
            priority = priority,
            right_gravity = false,
            end_right_gravity = false,
            hl_mode = "combine",
        })
    end

    local show_preview_popup = opts.preview ~= false and has_add and has_delete
    if show_preview_popup then
        show_preview(bufnr, line, updated_line, opts, additions)
    else
        close_preview(bufnr, line)
        for _, seg in ipairs(additions) do
            vim.api.nvim_buf_set_extmark(bufnr, ns, line, seg.orig_col, {
                virt_text = { { seg.text, add_hl } },
                virt_text_pos = virt_text_pos,
                priority = priority,
                right_gravity = false,
                virt_text_hide = false,
            })
        end
    end
end

local function resolve_bufnr(opts)
    if opts and opts.bufnr then
        return opts.bufnr
    end
    return vim.api.nvim_get_current_buf()
end

function M.clear(opts)
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

function M.display_diff(line, updated_line, opts)
    opts = opts or {}
    local bufnr = resolve_bufnr(opts)
    if type(line) ~= "number" then
        error("display_diff expects a 0-indexed line number")
    end

    ensure_highlights()

    local current = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
    if current == nil then
        return
    end

    -- M.clear({ bufnr = bufnr, line = line })
    -- clear *all* visible diffs
    M.clear({ bufnr = bufnr })

    local new_line = updated_line or ""
    local ops = compute_inline_diff(current, new_line)
    apply_diff(bufnr, line, ops, opts, new_line)
end

function M.setup(user_config)
    if user_config ~= nil then
        merge_config(config, user_config)
        highlight_initialized = false
    end
    return config
end

M.config = config
M.themes = presets

function M.use_theme(name, overrides)
    local preset = presets[name]
    if not preset then
        error(("Unknown display-diff theme '%s'"):format(tostring(name)))
    end
    local merged = vim.deepcopy(preset)
    if overrides then
        merge_config(merged, overrides)
    end
    return M.setup(merged)
end

function M.get_themes()
    return vim.deepcopy(presets)
end

-- testing functionality
-- create a keybind to add a diff with the string "Hello world" to the current line the cursor is on
vim.keymap.set("n", "<leader>dd", function()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    M.display_diff(cursor_line, "Hello world")
end, { noremap = true, silent = true, desc = "Ghostcursor: inline diff test" })


return M
