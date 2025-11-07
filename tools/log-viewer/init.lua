-- Log viewer for GhostCursor query logs
-- Displays logs in a structured, expandable tree format

local M = {}

-- Get log file path (same logic as logger.lua)
local function get_log_path()
    local data_dir = vim.fn.stdpath("data")
    local log_dir = data_dir .. "/ghostcursor/log"
    return log_dir .. "/query_log.jsonl"
end

-- Read all log entries from file
local function read_log_entries()
    local log_path = get_log_path()
    local file = io.open(log_path, "r")
    if not file then
        return {}
    end

    local entries = {}
    for line in file:lines() do
        if line and line ~= "" then
            local ok, entry = pcall(vim.json.decode, line)
            if ok and entry then
                table.insert(entries, entry)
            end
        end
    end
    file:close()
    return entries
end

-- Pretty print JSON with indentation
local function pretty_json(obj, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    
    if type(obj) == "table" then
        local is_array = false
        local max_key = 0
        for k, _ in pairs(obj) do
            if type(k) == "number" then
                is_array = true
                max_key = math.max(max_key, k)
            else
                is_array = false
                break
            end
        end
        
        if is_array and max_key == #obj then
            -- Array format
            local lines = { "[" }
            for i, v in ipairs(obj) do
                local val = pretty_json(v, indent + 1)
                local comma = i < #obj and "," or ""
                table.insert(lines, indent_str .. "  " .. val .. comma)
            end
            table.insert(lines, indent_str .. "]")
            return table.concat(lines, "\n")
        else
            -- Object format
            local lines = { "{" }
            local keys = {}
            for k, _ in pairs(obj) do
                table.insert(keys, k)
            end
            table.sort(keys)
            
            for i, k in ipairs(keys) do
                local v = obj[k]
                local val = pretty_json(v, indent + 1)
                local comma = i < #keys and "," or ""
                local key_str = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
                table.insert(lines, indent_str .. "  " .. key_str .. ": " .. val .. comma)
            end
            table.insert(lines, indent_str .. "}")
            return table.concat(lines, "\n")
        end
    elseif type(obj) == "string" then
        -- Escape quotes and newlines
        local escaped = obj:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
        return '"' .. escaped .. '"'
    else
        return tostring(obj)
    end
end

-- Format a log entry for display
local function format_entry(entry, index, expanded)
    expanded = expanded or {}
    local lines = {}
    
    -- Header line
    local timestamp = entry.timestamp_iso or entry.timestamp or "unknown"
    local model = entry.model or "unknown"
    local request_id = entry.request_id or index
    local header = string.format("▶ [%s] Request #%d - %s", timestamp, request_id, model)
    table.insert(lines, header)
    
    -- Fields
    local fields = {
        { key = "timestamp", label = "timestamp" },
        { key = "timestamp_iso", label = "timestamp_iso" },
        { key = "request_id", label = "request_id" },
        { key = "url", label = "url" },
        { key = "model", label = "model" },
        { key = "filetype", label = "filetype" },
        { key = "cursor_line", label = "cursor_line" },
        { key = "suggested_line", label = "suggested_line" },
        { key = "error", label = "error" },
    }
    
    for _, field in ipairs(fields) do
        if entry[field.key] ~= nil then
            local value = entry[field.key]
            -- Don't truncate - let wrap handle long lines
            table.insert(lines, "  ├─ " .. field.label .. ": " .. tostring(value))
        end
    end
    
    -- Collapsible fields
    local collapsible_fields = {
        { key = "query_payload", label = "query_payload" },
        { key = "response", label = "response" },
        { key = "context_lines", label = "context_lines" },
    }
    
    for _, field in ipairs(collapsible_fields) do
        if entry[field.key] ~= nil then
            local is_expanded = expanded[field.key] or false
            local prefix = is_expanded and "▼" or "▶"
            table.insert(lines, "  ├─ " .. prefix .. " " .. field.label .. ":")
            
            if is_expanded then
                local value = entry[field.key]
                local formatted
                if type(value) == "string" then
                    -- Try to parse as JSON first
                    local ok, parsed = pcall(vim.json.decode, value)
                    if ok then
                        formatted = pretty_json(parsed, 0)
                    else
                        formatted = value
                    end
                else
                    formatted = pretty_json(value, 0)
                end
                
                -- Indent the expanded content
                for line in formatted:gmatch("[^\n]+") do
                    table.insert(lines, "  │  " .. line)
                end
            else
                -- Show preview (but don't truncate - let it wrap)
                local preview = "(collapsed - press Enter to expand)"
                if type(entry[field.key]) == "string" then
                    -- Show first line or first 100 chars, whichever is shorter
                    local first_line = entry[field.key]:match("([^\n]+)")
                    if first_line and #first_line > 100 then
                        preview = first_line:sub(1, 100) .. "..."
                    elseif first_line then
                        preview = first_line
                    end
                end
                table.insert(lines, "  │  " .. preview)
            end
        end
    end
    
    -- Footer
    table.insert(lines, "")
    
    return lines
end

-- Render all entries to buffer
local function render_buffer(bufnr, entries, expanded_state)
    expanded_state = expanded_state or {}
    local lines = {}
    
    -- Header
    table.insert(lines, "GhostCursor Query Logs")
    table.insert(lines, "Entries: " .. #entries)
    table.insert(lines, "Last updated: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, "")
    table.insert(lines, "Keybindings:")
    table.insert(lines, "  j/k     - Navigate up/down")
    table.insert(lines, "  Enter/o - Expand/collapse field")
    table.insert(lines, "  r       - Refresh")
    table.insert(lines, "  q       - Close")
    table.insert(lines, "")
    table.insert(lines, string.rep("─", 80))
    table.insert(lines, "")
    
    if #entries == 0 then
        table.insert(lines, "No log entries found.")
        table.insert(lines, "Log file: " .. get_log_path())
    else
        -- Render entries (newest first)
        for i = #entries, 1, -1 do
            local entry = entries[i]
            local entry_expanded = expanded_state[i] or {}
            local entry_lines = format_entry(entry, i, entry_expanded)
            for _, line in ipairs(entry_lines) do
                table.insert(lines, line)
            end
        end
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- Toggle expansion of a field
local function toggle_field(entries, expanded_state, entry_idx, field_key)
    if not expanded_state[entry_idx] then
        expanded_state[entry_idx] = {}
    end
    expanded_state[entry_idx][field_key] = not (expanded_state[entry_idx][field_key] or false)
end

-- Find which entry and field the cursor is on
local function get_cursor_location(bufnr, entries, expanded_state)
    local line_num = vim.api.nvim_win_get_cursor(0)[1] - 1
    
    -- Skip header lines
    local header_lines = 12
    if line_num < header_lines then
        return nil, nil
    end
    
    -- Get the actual line content from buffer
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local current_line_content = buffer_lines[line_num + 1] or ""
    
    -- Check if we're on a collapsible field line
    -- The line should look like: "  ├─ ▶ query_payload:" or "  ├─ ▼ query_payload:"
    -- Use a more direct approach that doesn't rely on Unicode character classes
    local field_key = nil
    
    -- First check if line has the structure: spaces + ├─ + symbol + space + field_name + :
    if current_line_content:match("├─") and current_line_content:match(":") then
        -- Extract the field name: everything after ├─ symbol space and before :
        -- Pattern: ├─ followed by optional spaces, then a symbol (any char), then space, then field name, then :
        local match = current_line_content:match("├─%s*[^%s]%s+([^:]+):")
        if match then
            field_key = match:gsub("^%s+", ""):gsub("%s+$", "")
        end
        
        -- Alternative: match everything between ├─ and :, then extract last word
        if not field_key then
            local before_colon = current_line_content:match("├─%s*([^:]+):")
            if before_colon then
                -- Extract field name (everything after the last space)
                local field_match = before_colon:match("%s+([^%s]+)%s*$")
                if field_match then
                    field_key = field_match
                end
            end
        end
    end
    
    if not field_key then
        return nil, nil
    end
    
    -- Find which entry this line belongs to by scanning upward for the entry header
    -- Entry headers look like: "▶ [timestamp] Request #id model"
    local entry_idx = nil
    for i = line_num, header_lines, -1 do
        local line = buffer_lines[i + 1] or ""
        -- Check if this is an entry header line
        if line:match("^▶ %[") then
            -- Extract request ID from header: "▶ [timestamp] Request #id model"
            local request_id_match = line:match("Request #(%d+)")
            if request_id_match then
                local request_id = tonumber(request_id_match)
                -- Find the entry index (entries are rendered newest first, so reverse the index)
                -- Entry at index #entries has request_id = #entries, entry at #entries-1 has request_id = #entries-1, etc.
                -- But we need to account for the fact that request_id might not match index exactly
                -- So we'll search through entries to find the matching one
                for j = #entries, 1, -1 do
                    local entry = entries[j]
                    if entry.request_id == request_id or (not entry.request_id and j == request_id) then
                        entry_idx = j
                        break
                    end
                end
                -- If we couldn't find by request_id, use the position-based approach
                if not entry_idx then
                    -- Count how many entry headers we've seen from the top
                    local entry_count = 0
                    for k = header_lines, i do
                        if buffer_lines[k + 1]:match("^▶ %[") then
                            entry_count = entry_count + 1
                        end
                    end
                    -- Since entries are rendered newest first, entry_count corresponds to entry index
                    entry_idx = #entries - entry_count + 1
                end
                break
            end
        end
    end
    
    if entry_idx then
        -- Map label to key
        local key_map = {
            query_payload = "query_payload",
            response = "response",
            context_lines = "context_lines",
        }
        local mapped_key = key_map[field_key]
        if mapped_key then
            return entry_idx, mapped_key
        end
    end
    
    return nil, nil
end

-- Open the log viewer
function M.open()
    local entries = read_log_entries()
    local expanded_state = {}
    
    -- Check if buffer already exists and close any windows using it
    local existing_bufnr = nil
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) then
            local buf_name = vim.api.nvim_buf_get_name(buf)
            if buf_name == "GhostCursor Logs" or buf_name:match("GhostCursor Logs") then
                existing_bufnr = buf
                -- Close any windows showing this buffer
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                -- Delete the buffer
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
                break
            end
        end
    end
    
    -- Create buffer with unique name
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "GhostCursor Logs")
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    
    -- Render initial content (need modifiable = true to write)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    render_buffer(bufnr, entries, expanded_state)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    
    -- Create window (larger size, nearly fullscreen)
    local width = math.min(vim.o.columns - 8, 160)
    local height = math.min(vim.o.lines - 8, 50)
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = (vim.o.columns - width) / 2,
        row = (vim.o.lines - height) / 2,
        style = "minimal",
        border = "rounded",
    }
    
    local win_id = vim.api.nvim_open_win(bufnr, true, win_opts)
    
    -- Set window options for better text display
    vim.api.nvim_win_set_option(win_id, "wrap", true)
    vim.api.nvim_win_set_option(win_id, "linebreak", true)
    vim.api.nvim_buf_set_option(bufnr, "wrap", true)
    vim.api.nvim_buf_set_option(bufnr, "linebreak", true)
    vim.api.nvim_buf_set_option(bufnr, "textwidth", 0)  -- No text width limit
    vim.api.nvim_buf_set_option(bufnr, "wrapmargin", 0)  -- No wrap margin
    
    -- Keybindings
    local function refresh()
        entries = read_log_entries()
        vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        render_buffer(bufnr, entries, expanded_state)
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    end
    
    local function expand_toggle()
        local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line_content = buffer_lines[current_line + 1] or ""
        
        local entry_idx, field_key = get_cursor_location(bufnr, entries, expanded_state)
        
        if entry_idx and field_key then
            toggle_field(entries, expanded_state, entry_idx, field_key)
            vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
            render_buffer(bufnr, entries, expanded_state)
            vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
            
            -- Try to restore cursor position (approximate)
            local total_lines = #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local new_line = math.min(current_line, total_lines - 1)
            vim.api.nvim_win_set_cursor(0, { new_line + 1, 0 })
        else
            -- Check if user is on entry header (can't expand that)
            if current_line_content:match("^▶ %[") then
                vim.notify("Navigate down to a field line (like '  ├─ ▶ query_payload:') to expand/collapse", vim.log.levels.INFO)
            elseif current_line_content:match("├─") then
                -- We're on a line with ├─ but pattern didn't match - show debug info
                vim.notify(string.format("Debug - Line: '%s' | Has ├─ but pattern failed. Trying to extract field...", 
                    current_line_content:sub(1, 60)), 
                    vim.log.levels.WARN)
            else
                vim.notify("Cannot expand - not on a collapsible field line", vim.log.levels.INFO)
            end
        end
    end
    
    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>close<cr>", { silent = true })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "r", "", { callback = refresh, silent = true })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "<CR>", "", { callback = expand_toggle, silent = true })
    vim.api.nvim_buf_set_keymap(bufnr, "n", "o", "", { callback = expand_toggle, silent = true })
    
    -- Set filetype for syntax highlighting
    vim.api.nvim_buf_set_option(bufnr, "filetype", "ghostcursor-logs")
end

-- Create command
vim.api.nvim_create_user_command("GhostCursorLogs", function()
    M.open()
end, { desc = "Open GhostCursor query log viewer" })

return M

