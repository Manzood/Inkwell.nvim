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

-- Check if a path is expanded (needed by render_json_value)
local function is_path_expanded(expanded_state, entry_idx, path)
    if not expanded_state[entry_idx] then
        return false
    end
    return expanded_state[entry_idx][path] or false
end

-- Render a JSON value recursively with expand/collapse support
-- line_to_path: table mapping buffer line numbers to their corresponding paths
-- line_offset: current buffer line offset (where we're rendering)
-- Returns: lines array, new_line_offset (where we ended up)
local function render_json_value(value, base_path, indent_level, expanded_state, entry_idx, line_to_path, line_offset)
    indent_level = indent_level or 0
    local indent_str = string.rep("  ", indent_level)
    local lines = {}
    line_offset = line_offset or 0
    
    if type(value) == "table" then
        -- Check if it's an array
        local is_array = false
        local max_key = 0
        local count = 0
        for k, _ in pairs(value) do
            count = count + 1
            if type(k) == "number" then
                is_array = true
                max_key = math.max(max_key, k)
            else
                is_array = false
                break
            end
        end
        
        if is_array and max_key == count then
            -- Array
            local path = base_path .. "[]"
            local is_expanded = is_path_expanded(expanded_state, entry_idx, path)
            local prefix = is_expanded and "▼" or "▶"
            local array_line = indent_str .. prefix .. " ["
            table.insert(lines, array_line)
            
            -- Map this line to the path
            if line_to_path then
                line_to_path[line_offset] = path
            end
            local current_line = line_offset + 1
            
            if is_expanded then
                for i, v in ipairs(value) do
                    local item_path = base_path .. "[" .. (i - 1) .. "]"
                    local item_lines, new_offset = render_json_value(v, item_path, indent_level + 1, expanded_state, entry_idx, line_to_path, current_line)
                    for _, line in ipairs(item_lines) do
                        table.insert(lines, line)
                    end
                    current_line = new_offset
                    -- Append comma to the last line if there are more items
                    if i < #value then
                        local last_line_idx = #lines
                        if last_line_idx > 0 then
                            -- Append comma to the last line
                            lines[last_line_idx] = lines[last_line_idx] .. ","
                        else
                            -- Fallback: add comma as new line (shouldn't happen)
                            table.insert(lines, indent_str .. "  ,")
                            current_line = current_line + 1
                        end
                    end
                end
                table.insert(lines, indent_str .. " ]")
                current_line = current_line + 1
            else
                table.insert(lines, indent_str .. "  ... (" .. #value .. " items)")
                current_line = current_line + 1
            end
            
            return lines, current_line
        else
            -- Object
            local path = base_path .. "{}"
            local is_expanded = is_path_expanded(expanded_state, entry_idx, path)
            local prefix = is_expanded and "▼" or "▶"
            local object_line = indent_str .. prefix .. " {"
            table.insert(lines, object_line)
            
            -- Map this line to the path
            if line_to_path then
                line_to_path[line_offset] = path
            end
            local current_line = line_offset + 1
            
            if is_expanded then
                local keys = {}
                for k, _ in pairs(value) do
                    table.insert(keys, k)
                end
                table.sort(keys, function(a, b)
                    if type(a) == "number" and type(b) == "number" then
                        return a < b
                    end
                    return tostring(a) < tostring(b)
                end)
                
                for i, k in ipairs(keys) do
                    local v = value[k]
                    local key_str = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
                    local item_path = base_path .. "." .. tostring(k)
                    
                    -- Check if the value is a table (collapsible structure)
                    local is_table = type(v) == "table"
                    local nested_path = nil
                    if is_table then
                        -- Determine the nested path based on whether it's an array or object
                        local is_array = false
                        local max_key = 0
                        local count = 0
                        for key, _ in pairs(v) do
                            count = count + 1
                            if type(key) == "number" then
                                is_array = true
                                max_key = math.max(max_key, key)
                            else
                                is_array = false
                                break
                            end
                        end
                        nested_path = item_path .. (is_array and max_key == count and "[]" or "{}")
                    end
                    
                    local item_lines, new_offset = render_json_value(v, item_path, indent_level + 1, expanded_state, entry_idx, line_to_path, current_line)
                    
                    -- First line goes on same line as key, rest are indented
                    if #item_lines > 0 then
                        -- Check if first line is a collapsible structure (has ▶ or ▼)
                        local first_line = item_lines[1]
                        if first_line:match("[▶▼]") and nested_path then
                            -- The collapsible structure is on the same line as the key
                            -- Map this line to the nested path (overwrite any mapping from render_json_value)
                            if line_to_path then
                                line_to_path[current_line] = nested_path
                            end
                        end
                        table.insert(lines, indent_str .. "  " .. key_str .. ": " .. first_line)
                        -- The first line is merged with the key line, so we're at current_line + 1 now
                        -- But render_json_value tracked it as current_line, so we need to adjust
                        -- Use new_offset - 1 + 1 = new_offset (since render_json_value counted the first line)
                        current_line = current_line + 1
                        for j = 2, #item_lines do
                            table.insert(lines, item_lines[j])
                        end
                        -- new_offset already accounts for all lines including the first one
                        -- But we merged the first line with the key line, so we're actually at new_offset
                        current_line = new_offset
                    end
                    -- Append comma to the last line if there are more keys
                    if i < #keys then
                        local last_line_idx = #lines
                        if last_line_idx > 0 then
                            -- Append comma to the last line
                            lines[last_line_idx] = lines[last_line_idx] .. ","
                        else
                            -- Fallback: add comma as new line (shouldn't happen)
                            table.insert(lines, indent_str .. "  ,")
                            current_line = current_line + 1
                        end
                    end
                end
                table.insert(lines, indent_str .. " }")
                current_line = current_line + 1
            else
                local key_count = 0
                for _ in pairs(value) do
                    key_count = key_count + 1
                end
                table.insert(lines, indent_str .. "  ... (" .. key_count .. " keys)")
                current_line = current_line + 1
            end
            
            return lines, current_line
        end
    elseif type(value) == "string" then
        -- Escape quotes and newlines
        local escaped = value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
        table.insert(lines, '"' .. escaped .. '"')
        return lines, line_offset + 1
    else
        table.insert(lines, tostring(value))
        return lines, line_offset + 1
    end
end

-- Format a log entry for display
-- line_to_path: table mapping buffer line numbers to their corresponding paths
-- line_offset: current buffer line offset (where we're rendering this entry)
-- Returns: lines array, new_line_offset (where we ended up)
local function format_entry(entry, index, expanded_state, line_to_path, line_offset)
    expanded_state = expanded_state or {}
    local entry_expanded = expanded_state[index] or {}
    local lines = {}
    line_offset = line_offset or 0
    local current_line = line_offset
    
    -- Header line
    local timestamp = entry.timestamp_iso or entry.timestamp or "unknown"
    local model = entry.model or "unknown"
    local request_id = entry.request_id or index
    local header = string.format("▶ [%s] Request #%d - %s", timestamp, request_id, model)
    table.insert(lines, header)
    current_line = current_line + 1
    
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
            current_line = current_line + 1
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
            local is_expanded = entry_expanded[field.key] or false
            local prefix = is_expanded and "▼" or "▶"
            local field_line = "  ├─ " .. prefix .. " " .. field.label .. ":"
            table.insert(lines, field_line)
            
            -- Map this line to the top-level field path
            if line_to_path then
                line_to_path[current_line] = field.key
            end
            current_line = current_line + 1
            
            if is_expanded then
                local value = entry[field.key]
                local parsed_value = value
                
                -- Try to parse as JSON if it's a string
                if type(value) == "string" then
                    local ok, parsed = pcall(vim.json.decode, value)
                    if ok then
                        parsed_value = parsed
                    end
                end
                
                -- Use recursive renderer for nested structures
                if type(parsed_value) == "table" then
                    local base_path = field.key
                    -- The nested content starts at current_line
                    -- render_json_value will create mappings using current_line as the base offset
                    local json_lines, new_offset = render_json_value(parsed_value, base_path, 0, expanded_state, index, line_to_path, current_line)
                    for _, line in ipairs(json_lines) do
                        table.insert(lines, "  │  " .. line)
                    end
                    -- Update current_line based on what render_json_value returned
                    -- new_offset already accounts for all lines rendered
                    current_line = new_offset
                else
                    -- Simple value - just display it
                    local formatted = type(value) == "string" and value or tostring(value)
                    for line in formatted:gmatch("[^\n]+") do
                        table.insert(lines, "  │  " .. line)
                        current_line = current_line + 1
                    end
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
                current_line = current_line + 1
            end
        end
    end
    
    -- Footer
    table.insert(lines, "")
    current_line = current_line + 1
    
    return lines, current_line
end

-- Render all entries to buffer
-- Returns: line_to_path mapping table
local function render_buffer(bufnr, entries, expanded_state, line_to_path)
    expanded_state = expanded_state or {}
    line_to_path = line_to_path or {}
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
    
    local header_lines = #lines
    local current_line = header_lines
    
    if #entries == 0 then
        table.insert(lines, "No log entries found.")
        table.insert(lines, "Log file: " .. get_log_path())
    else
        -- Render entries (newest first)
        for i = #entries, 1, -1 do
            local entry = entries[i]
            local entry_lines, new_offset = format_entry(entry, i, expanded_state, line_to_path, current_line)
            for _, line in ipairs(entry_lines) do
                table.insert(lines, line)
            end
            current_line = new_offset
        end
    end
    
    -- Sanitize lines: split any lines containing newlines into multiple lines
    local sanitized_lines = {}
    for _, line in ipairs(lines) do
        if line:match("\n") then
            -- Split line by newlines
            for split_line in line:gmatch("[^\n]+") do
                table.insert(sanitized_lines, split_line)
            end
            -- If line ends with newline, add empty line
            if line:match("\n$") then
                table.insert(sanitized_lines, "")
            end
        else
            table.insert(sanitized_lines, line)
        end
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, sanitized_lines)
    return line_to_path
end

-- Toggle expansion of a field (supports nested paths like "query_payload.messages[0]")
local function toggle_field(entries, expanded_state, entry_idx, field_path)
    if not expanded_state[entry_idx] then
        expanded_state[entry_idx] = {}
    end
    local was_expanded = expanded_state[entry_idx][field_path] or false
    expanded_state[entry_idx][field_path] = not was_expanded
    
    -- If we're expanding a top-level field, automatically expand its immediate nested structure
    if not was_expanded then  -- We just expanded it
        local top_level_fields = {"query_payload", "response", "context_lines"}
        
        -- Check if this is a top-level field
        local is_top_level = false
        for _, field in ipairs(top_level_fields) do
            if field_path == field then
                is_top_level = true
                break
            end
        end
        
        if is_top_level then
            -- Try to auto-expand both object and array structures
            -- The actual structure type will be determined by what exists in the data
            expanded_state[entry_idx][field_path .. "{}"] = true
            expanded_state[entry_idx][field_path .. "[]"] = true
        end
    end
end


-- Find which entry and field the cursor is on
-- Uses line_to_path mapping for reliable path detection
local function get_cursor_location(bufnr, entries, expanded_state, line_to_path)
    local line_num = vim.api.nvim_win_get_cursor(0)[1] - 1
    
    -- Skip header lines
    local header_lines = 12
    if line_num < header_lines then
        return nil, nil
    end
    
    -- Try to get path from line_to_path mapping first (most reliable)
    local field_path = nil
    if line_to_path then
        -- Check current line and nearby lines (in case of wrapping or slight offsets)
        for offset = 0, 2 do
            local check_line = line_num + offset
            if line_to_path[check_line] then
                field_path = line_to_path[check_line]
                break
            end
        end
        -- Debug: check a wider range if not found
        if not field_path then
            for offset = -2, 5 do
                local check_line = line_num + offset
                if line_to_path[check_line] then
                    field_path = line_to_path[check_line]
                    break
                end
            end
        end
    end
    
    -- Fallback: check for top-level field if mapping didn't work
    if not field_path then
        local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line_content = buffer_lines[line_num + 1] or ""
        
        -- Check for top-level field (starts with "  ├─" and has ▶/▼)
        if current_line_content:match("^%s+├─") and current_line_content:match(":") then
            -- Check if it's a collapsible field (has ▶ or ▼)
            if current_line_content:match("[▶▼]") then
                -- Extract the field name - look for query_payload, response, or context_lines
                if string.find(current_line_content, "query_payload", 1, true) then
                    field_path = "query_payload"
                elseif string.find(current_line_content, "response", 1, true) then
                    field_path = "response"
                elseif string.find(current_line_content, "context_lines", 1, true) then
                    field_path = "context_lines"
                else
                    -- Fallback: extract field name using pattern matching
                    local match = current_line_content:match("├─%s*[▶▼]%s+([^:]+):")
                    if match then
                        field_path = match:gsub("^%s+", ""):gsub("%s+$", "")
                    else
                        local before_colon = current_line_content:match("├─%s*[▶▼]%s*([^:]+):")
                        if before_colon then
                            local field_match = before_colon:match("%s+([^%s]+)%s*$")
                            if field_match then
                                field_path = field_match
                            end
                        end
                    end
                end
            end
        end
    end
    
    if not field_path then
        return nil, nil
    end
    
    -- Find which entry this line belongs to by scanning upward for the entry header
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local entry_idx = nil
    for i = line_num, header_lines, -1 do
        local line = buffer_lines[i + 1] or ""
        if line:match("^▶ %[") then
            local request_id_match = line:match("Request #(%d+)")
            if request_id_match then
                local request_id = tonumber(request_id_match)
                -- Find the entry index
                for j = #entries, 1, -1 do
                    local entry = entries[j]
                    if entry.request_id == request_id or (not entry.request_id and j == request_id) then
                        entry_idx = j
                        break
                    end
                end
                if not entry_idx then
                    local entry_count = 0
                    for k = header_lines, i do
                        if buffer_lines[k + 1]:match("^▶ %[") then
                            entry_count = entry_count + 1
                        end
                    end
                    entry_idx = #entries - entry_count + 1
                end
                break
            end
        end
    end
    
    -- If we didn't find entry_idx, try counting entries from top
    if not entry_idx then
        local entry_count = 0
        for i = header_lines, line_num do
            if buffer_lines[i + 1]:match("^▶ %[") then
                entry_count = entry_count + 1
            end
        end
        if entry_count > 0 then
            entry_idx = #entries - entry_count + 1
        end
    end
    
    if entry_idx then
        -- Validate that the path starts with a valid base field
        local key_map = {
            query_payload = "query_payload",
            response = "response",
            context_lines = "context_lines",
        }
        
        -- Extract base field (everything before first ., [, or {)
        local base_field = field_path:match("^([^%.%[%{]+)")
        
        -- Check if base field is valid
        if key_map[base_field] then
            return entry_idx, field_path
        end
    end
    
    return nil, nil
end

-- Open the log viewer
function M.open()
    -- Clean up log file to keep only last 100 entries
    local entries = read_log_entries()
    if #entries > 100 then
        -- Trim to last 100 entries
        local log_path = get_log_path()
        local start = #entries - 100 + 1
        local trimmed_entries = {}
        for i = start, #entries do
            table.insert(trimmed_entries, entries[i])
        end
        
        -- Write trimmed entries back to file
        local file = io.open(log_path, "w")
        if file then
            for _, entry in ipairs(trimmed_entries) do
                local ok, json_line = pcall(vim.fn.json_encode, entry)
                if ok then
                    file:write(json_line .. "\n")
                end
            end
            file:close()
            entries = trimmed_entries
        end
    end
    
    local expanded_state = {}
    local line_to_path = {}  -- Mapping from buffer line numbers to paths
    
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
    line_to_path = render_buffer(bufnr, entries, expanded_state, line_to_path)
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
        line_to_path = {}  -- Reset mapping
        vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
        line_to_path = render_buffer(bufnr, entries, expanded_state, line_to_path)
        vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    end
    
    local function expand_toggle()
        local current_line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line_content = buffer_lines[current_line + 1] or ""
        
        local entry_idx, field_key = get_cursor_location(bufnr, entries, expanded_state, line_to_path)
        
        if entry_idx and field_key then
            toggle_field(entries, expanded_state, entry_idx, field_key)
            line_to_path = {}  -- Reset mapping before re-rendering
            vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
            line_to_path = render_buffer(bufnr, entries, expanded_state, line_to_path)
            vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
            
            -- Try to restore cursor position (approximate)
            local total_lines = #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local new_line = math.min(current_line, total_lines - 1)
            vim.api.nvim_win_set_cursor(0, { new_line + 1, 0 })
        else
            -- Debug output
            local nearby_mappings = {}
            for offset = -3, 3 do
                local check_line = current_line + offset
                if line_to_path and line_to_path[check_line] then
                    table.insert(nearby_mappings, string.format("L%d:%s", check_line, line_to_path[check_line]))
                end
            end
            
            -- Check if user is on entry header (can't expand that)
            if current_line_content:match("^▶ %[") then
                vim.notify("Navigate down to a field line (like '  ├─ ▶ query_payload:') to expand/collapse", vim.log.levels.INFO)
            else
                local debug_msg = string.format("Cannot expand - Line %d: '%s' | Nearby mappings: %s", 
                    current_line, 
                    current_line_content:sub(1, 40),
                    #nearby_mappings > 0 and table.concat(nearby_mappings, ", ") or "none")
                vim.notify(debug_msg, vim.log.levels.WARN)
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

-- Purge the log file (delete all entries)
function M.purge()
    local log_path = get_log_path()
    local file = io.open(log_path, "w")
    if file then
        file:close()
        vim.notify("GhostCursor log file purged successfully", vim.log.levels.INFO)
    else
        vim.notify("Failed to purge log file: " .. log_path, vim.log.levels.ERROR)
    end
end

-- Create command
vim.api.nvim_create_user_command("GhostCursorLogs", function()
    M.open()
end, { desc = "Open GhostCursor query log viewer" })

-- Create purge command
vim.api.nvim_create_user_command("GhostCursorLogsPurge", function()
    M.purge()
end, { desc = "Purge all entries from GhostCursor log file" })

return M

