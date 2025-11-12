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
local function render_json_value(value, base_path, indent_level, expanded_state, entry_idx)
    indent_level = indent_level or 0
    local indent_str = string.rep("  ", indent_level)
    local lines = {}
    
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
            table.insert(lines, indent_str .. prefix .. " [")
            
            if is_expanded then
                for i, v in ipairs(value) do
                    local item_path = base_path .. "[" .. (i - 1) .. "]"
                    local item_lines = render_json_value(v, item_path, indent_level + 1, expanded_state, entry_idx)
                    for _, line in ipairs(item_lines) do
                        table.insert(lines, line)
                    end
                    if i < #value then
                        table.insert(lines, indent_str .. "  ,")
                    end
                end
                table.insert(lines, indent_str .. " ]")
            else
                table.insert(lines, indent_str .. "  ... (" .. #value .. " items)")
            end
        else
            -- Object
            local path = base_path .. "{}"
            local is_expanded = is_path_expanded(expanded_state, entry_idx, path)
            local prefix = is_expanded and "▼" or "▶"
            table.insert(lines, indent_str .. prefix .. " {")
            
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
                    local item_lines = render_json_value(v, item_path, indent_level + 1, expanded_state, entry_idx)
                    
                    -- First line goes on same line as key, rest are indented
                    if #item_lines > 0 then
                        table.insert(lines, indent_str .. "  " .. key_str .. ": " .. item_lines[1])
                        for j = 2, #item_lines do
                            table.insert(lines, item_lines[j])
                        end
                    end
                    if i < #keys then
                        table.insert(lines, indent_str .. "  ,")
                    end
                end
                table.insert(lines, indent_str .. " }")
            else
                local key_count = 0
                for _ in pairs(value) do
                    key_count = key_count + 1
                end
                table.insert(lines, indent_str .. "  ... (" .. key_count .. " keys)")
            end
        end
    elseif type(value) == "string" then
        -- Escape quotes and newlines
        local escaped = value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
        table.insert(lines, '"' .. escaped .. '"')
    else
        table.insert(lines, tostring(value))
    end
    
    return lines
end

-- Format a log entry for display
local function format_entry(entry, index, expanded_state)
    expanded_state = expanded_state or {}
    local entry_expanded = expanded_state[index] or {}
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
            local is_expanded = entry_expanded[field.key] or false
            local prefix = is_expanded and "▼" or "▶"
            table.insert(lines, "  ├─ " .. prefix .. " " .. field.label .. ":")
            
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
                    local json_lines = render_json_value(parsed_value, base_path, 0, expanded_state, index)
                    for _, line in ipairs(json_lines) do
                        table.insert(lines, "  │  " .. line)
                    end
                else
                    -- Simple value - just display it
                    local formatted = type(value) == "string" and value or tostring(value)
                    for line in formatted:gmatch("[^\n]+") do
                        table.insert(lines, "  │  " .. line)
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
            local entry_lines = format_entry(entry, i, expanded_state)
            for _, line in ipairs(entry_lines) do
                table.insert(lines, line)
            end
        end
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- Toggle expansion of a field (supports nested paths like "query_payload.messages[0]")
local function toggle_field(entries, expanded_state, entry_idx, field_path)
    if not expanded_state[entry_idx] then
        expanded_state[entry_idx] = {}
    end
    expanded_state[entry_idx][field_path] = not (expanded_state[entry_idx][field_path] or false)
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
    
    -- Check if we're on a collapsible line (top-level field or nested structure)
    -- Top-level: "  ├─ ▶ query_payload:" or "  ├─ ▼ query_payload:"
    -- Nested: "  │    ▶ [" or "  │    ▶ {" or "  │      ▶ [0]"
    local field_path = nil
    
    -- Check for top-level field (starts with "  ├─")
    if current_line_content:match("^%s+├─") and current_line_content:match(":") then
        -- Extract the field name: everything after ├─ symbol space and before :
        local match = current_line_content:match("├─%s*[^%s]%s+([^:]+):")
        if match then
            field_path = match:gsub("^%s+", ""):gsub("%s+$", "")
        end
        
        -- Alternative: match everything between ├─ and :, then extract last word
        if not field_path then
            local before_colon = current_line_content:match("├─%s*([^:]+):")
            if before_colon then
                local field_match = before_colon:match("%s+([^%s]+)%s*$")
                if field_match then
                    field_path = field_match
                end
            end
        end
    -- Check for nested structure (starts with "  │" and has ▶, ▼, or ►)
    -- Pattern: "  │    ▶ {" or "  │    ▼ {" or "  │    ▶ [" or "  │    ►{" etc.
    elseif current_line_content:match("│") and current_line_content:match("[▶▼►]") then
        -- Reconstruct the full nested path by scanning upward and building path components
        local base_field = nil
        
        -- Find the base field first - use the simplest possible approach
        for i = line_num, header_lines, -1 do
            local line = buffer_lines[i + 1] or ""
            -- Look for the field header line (has ├─ and :)
            if line:match("├─") and line:match(":") then
                -- Direct string search - most reliable
                if string.find(line, "query_payload", 1, true) then
                    base_field = "query_payload"
                    break
                elseif string.find(line, "response", 1, true) then
                    base_field = "response"
                    break
                elseif string.find(line, "context_lines", 1, true) then
                    base_field = "context_lines"
                    break
                end
            end
        end
        
        if base_field then
            -- Build path components by scanning upward
            local path_components = {base_field}
            local current_indent = #current_line_content:match("^%s*")
            
            -- Scan upward to find parent structures
            for i = line_num - 1, header_lines, -1 do
                local line = buffer_lines[i + 1] or ""
                if line:match("^%s+├─") then
                    break  -- Reached base field
                end
                
                local line_indent = #line:match("^%s*")
                
                -- Only process lines that are less indented (parent structures)
                if line_indent < current_indent and line:match("[▶▼►]") then
                    -- Check for object key (format: "  │    "key": ▶" or "  │      "key": value")
                    -- Try pattern with expand/collapse symbol first (handle ▶, ▼, and ►)
                    local key_match = line:match('"%([^"]+)"%s*:%s*[▶▼►]')
                    -- If not found, try pattern without symbol (might be on next line)
                    if not key_match then
                        key_match = line:match('"%([^"]+)"%s*:')
                    end
                    if key_match then
                        table.insert(path_components, 1, "." .. key_match)
                        current_indent = line_indent
                    -- Check for array marker (handle ▶, ▼, and ►)
                    elseif line:match("[▶▼►]%s*%[") or line:match("[▶▼►]%[") then
                        -- Count array items to get index
                        local item_count = 0
                        for j = i + 1, line_num do
                            local check_line = buffer_lines[j + 1] or ""
                            local check_indent = #check_line:match("^%s*")
                            -- Count non-collapsed items at the array's indent level
                            if check_indent == line_indent + 2 and not (check_line:match("[▶▼►]") or check_line:match(",") or check_line:match("%]")) then
                                item_count = item_count + 1
                            elseif check_line:match("%]") then
                                break
                            end
                        end
                        table.insert(path_components, 1, "[" .. item_count .. "]")
                        current_indent = line_indent
                    -- Check for object marker (handle ▶, ▼, and ►)
                    elseif line:match("[▶▼►]%s*%{") or line:match("[▶▼►]%{") then
                        table.insert(path_components, 1, "{}")
                        current_indent = line_indent
                    end
                end
            end
            
            -- Build the path string
            local path_str = table.concat(path_components)
            
            -- Add the current structure marker (handle ▶, ▼, and ► with or without space)
            -- Since we're on a line with │ and triangle, it's definitely a nested structure
            -- Default to {} if we can't determine the exact type
            if current_line_content:match("[▶▼►]%s*%[") or current_line_content:match("[▶▼►]%[") then
                field_path = path_str .. "[]"
            elseif current_line_content:match("[▶▼►]%s*%{") or current_line_content:match("[▶▼►]%{") then
                field_path = path_str .. "{}"
            else
                -- Default: assume it's an object (most common case)
                field_path = path_str .. "{}"
            end
        end
    end
    
    -- CRITICAL FALLBACK: If field_path is still nil, use the simplest possible approach
    if not field_path then
        -- Scan upward and use direct string search
        for i = line_num, header_lines, -1 do
            local line = buffer_lines[i + 1] or ""
            if line:match("├─") and line:match(":") then
                -- Debug: log the actual line content
                -- Use string.find with plain text search (no patterns)
                -- Also try case-insensitive and partial matches
                local line_lower = string.lower(line)
                if string.find(line_lower, "query_payload", 1, true) or string.find(line, "query_payload", 1, true) then
                    field_path = "query_payload{}"
                    break
                elseif string.find(line_lower, "response", 1, true) or string.find(line, "response", 1, true) then
                    field_path = "response{}"
                    break
                elseif string.find(line_lower, "context_lines", 1, true) or string.find(line, "context_lines", 1, true) then
                    field_path = "context_lines{}"
                    break
                end
            end
        end
    end
    
    if not field_path then
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
    
    -- If we didn't find entry_idx, try a simpler approach: count entries from top
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
        
        -- Extract base field (everything before first . or [)
        local base_field = field_path:match("^([^%.%[]+)")
        
        -- Check if base field is valid
        if key_map[base_field] then
            -- Path is valid - return it (supports any depth of nesting)
            return entry_idx, field_path
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
            -- Debug: show what we detected
            local has_pipe = current_line_content:match("│") and "yes" or "no"
            local has_triangle_debug = current_line_content:match("[▶▼►]") and "yes" or "no"
            local triangle_char = current_line_content:match("[▶▼►]") or "none"
            local has_brace = (current_line_content:match("%{") or current_line_content:match("%[")) and "yes" or "no"
            
            -- Check if user is on entry header (can't expand that)
            if current_line_content:match("^▶ %[") then
                vim.notify("Navigate down to a field line (like '  ├─ ▶ query_payload:') to expand/collapse", vim.log.levels.INFO)
            else
                -- Additional debug: show what we found when scanning upward
                local found_base_field = nil
                local current_line_debug = vim.api.nvim_win_get_cursor(0)[1] - 1
                for i = current_line_debug, 12, -1 do
                    local line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
                    if line:match("├─") and line:match(":") then
                        found_base_field = line:sub(1, 60)
                        break
                    end
                end
                
                -- Also check what base_field was set to in get_cursor_location
                local entry_idx_debug, field_path_debug = get_cursor_location(bufnr, entries, expanded_state)
                
                vim.notify(string.format("Debug - Line: '%s' | │:%s | Triangle:%s (%s) | Brace/Bracket:%s | Entry:%s | Path:%s | Base field line: %s | After get_cursor_location: Entry:%s Path:%s", 
                    current_line_content:sub(1, 50),
                    has_pipe,
                    has_triangle_debug,
                    triangle_char,
                    has_brace,
                    tostring(entry_idx) or "nil",
                    tostring(field_path) or "nil",
                    found_base_field or "not found",
                    tostring(entry_idx_debug) or "nil",
                    tostring(field_path_debug) or "nil"), 
                    vim.log.levels.WARN)
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

