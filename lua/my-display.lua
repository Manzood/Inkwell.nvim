local mdebug = require("debug-util").debug

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

local default_highlights = {
    add = "InkWellGhostText",
    delete = "InkWellDiffDelete",
    preview = "InkWellDiffPreview",
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
            hl_group = "InkWellPreviewSerene",
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
            hl_group = "InkWellPreviewNeon",
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
            hl_group = "InkWellPreviewDusk",
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
            hl_group = "InkWellPreviewMinimal",
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
            hl_group = "InkWellPreviewCompact",
            highlight = {
                fg = "#b0c4de",
                bg = "#1f2430",
            },
            winhl = {
                NormalFloat = "InkWellPreviewCompactFloat",
                FloatBorder = "InkWellPreviewCompactBorder",
            },
            winhl_highlights = {
                InkWellPreviewCompactFloat = {
                    bg = "#1f2430",
                },
                InkWellPreviewCompactBorder = {
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
            hl_group = "InkWellPreviewSlimText",
            highlight = {
                fg = "#67e8f9",
                bg = "#10131b",
            },
            winhl = {
                NormalFloat = "InkWellPreviewSlimFloat",
                FloatBorder = "InkWellPreviewSlimBorder",
            },
            winhl_highlights = {
                InkWellPreviewSlimFloat = {
                    bg = "#10131b",
                },
                InkWellPreviewSlimBorder = {
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
            hl_group = "InkWellPreviewAurora",
            highlight = {
                fg = "#9ce5ff",
                bg = "#11212f",
            },
        },
    },
}
-- TODO we're going to come up with a better theme later
-- TODO add tests for checking how the diff library handles whitespace
function M.test_diff()
    local string1 = "Hi, this is a test string\n"
    local string2 = "Hi, this here string has some text\n"
    local testdiff = dmp.diff_main(string1, string2)
    dmp.diff_cleanupSemantic(testdiff)
    mdebug(vim.inspect((testdiff)))
end

function M.calculate_diff(cursor_line, new_content)
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

    -- some reference code for now
        -- mdebug(diff[1], diff[2])
        -- if diff[1] == 1 then
        --     -- addition
        --     -- vim.api.nvim_buf_set_extmark(0, ns, cursor_line, 0, {
        --     --     end_row = cursor_line,
        --     --     end_col = #current_content,
        --     --     hl_group = "InkWellDiffAdd",
        --     --     hl_eol = false,
        --     --     priority = 1000,
        --     -- })
        -- else
        --     -- deletion
        --     vim.api.nvim_buf_set_extmark(0, ns, cursor_line, 0, {
        --         end_row = cursor_line,
        --         end_col = #current_content,
        --         hl_group = "InkWellDiffDelete",
        --         hl_eol = false,
        --         priority = 1000,
        --     })
        -- end

    -- M.test_diff()

    local current_content = vim.api.nvim_buf_get_lines(0, cursor_line, cursor_line + 1, false)[1]
    local diff = dmp.diff_main(current_content, new_content)
    dmp:diff_cleanupSemantic(diff)

    return diff
end

M.display_diff = function (cursor_line, new_content)
    M.clear()

    local diff = M.calculate_diff(cursor_line, new_content)
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
    -- quick test to see if it works
    vim.api.nvim_buf_set_extmark(0, ns, cursor_line, 0, {
        end_row = cursor_line,
        end_col = #current_line - 1,
        hl_group = "InkWellDiffDelete",
        hl_eol = false,
        priority = 1000,
    })

    -- iterate through red and green positions and update the colour of the text at that position
    -- for _, pos in ipairs(red_positions) do
    --     vim.api.nvim_buf_set_extmark(0, ns, cursor_line, pos[1], {
    --         end_row = cursor_line,
    --         -- take minimum of the size of the current line and pos[2]
    --         end_col = math.min(#current_line, pos[2]), 
    --         hl_group = "InkWellDiffDelete",
    --         hl_eol = false,
    --         priority = 1000,
    --     })
    -- end

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

M.clear = function()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

return M