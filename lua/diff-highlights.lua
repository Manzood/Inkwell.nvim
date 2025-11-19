local M = {}

local default_highlights = {
    add = "InkWellGhostText",
    delete = "InkWellDiffDelete",
    preview = "InkWellDiffPreview",
}

local highlight_initialized = false
local preview_state = {}
M.config = {
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

-- TODO go through the highlight stuff
local function highlight_exists(group)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = true })
    if not ok or not hl then
        return false
    end
    if hl.link then
        return true
    end
    return next(hl) ~= nil
end

function M.ensure_highlights()
    if highlight_initialized then
        return
    end

    local preview_group = M.config.preview.hl_group or default_highlights.preview

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
            local spec = M.config.preview.highlight
            if type(spec) == "table" and next(spec) then
                vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { default = true }, spec))
            else
                vim.api.nvim_set_hl(0, group, { link = "DiffAdd", default = true })
            end
        end

        ::continue::
    end

    local winhl_specs = M.config.preview.winhl_highlights
    if type(winhl_specs) == "table" then
        for group, spec in pairs(winhl_specs) do
            if type(group) == "string" and type(spec) == "table" and next(spec) and not highlight_exists(group) then
                vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", { default = true }, spec))
            end
        end
    end

    highlight_initialized = true
end



return M