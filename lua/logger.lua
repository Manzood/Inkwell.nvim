-- Query logging module
local query_log = {
    history = {},      -- In-memory history (last N queries)
    max_history = 100, -- Keep last 100 queries in memory
    log_file = nil,    -- Will be set lazily
}


-- Get log file path
local function get_log_path()
    local data_dir = vim.fn.stdpath("data")
    local log_dir = data_dir .. "/ghostcursor/log"
    -- Ensure directory exists
    vim.fn.mkdir(log_dir, "p")
    return log_dir .. "/query_log.jsonl"
end
get_log_path()

-- Write a log entry to file
local function write_log_entry(entry)
    local log_path = get_log_path()
    local file = io.open(log_path, "a")
    if not file then
        vim.notify("Failed to open log file: " .. log_path, vim.log.levels.WARN)
        return false
    end
    
    local ok, json_line = pcall(vim.fn.json_encode, entry)
    if not ok then
        file:close()
        vim.notify("Failed to encode log entry to JSON: " .. tostring(json_line), vim.log.levels.ERROR)
        return false
    end
    
    file:write(json_line .. "\n")
    file:close()
    return true
end

-- Log a query
function query_log.log_query(query_data)
    if not query_data then
        vim.notify("logger.log_query: query_data is nil", vim.log.levels.WARN)
        return
    end
    
    local entry = {
        timestamp = os.time(),
        timestamp_iso = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        request_id = query_data.request_id,
        url = query_data.url or nil,
        model = query_data.model or nil,
        filetype = query_data.filetype or nil,
        cursor_line = query_data.cursor_line or nil,
        context_lines = query_data.context_lines or nil,
        -- Accept both 'query' and 'query_payload' for compatibility
        query_payload = query_data.query_payload or query_data.query or nil,
        response = query_data.response or nil,
        suggested_line = query_data.suggested_line or nil,
        error = query_data.error or nil,
    }

    -- Add to in-memory history
    table.insert(query_log.history, entry)
    if #query_log.history > query_log.max_history then
        table.remove(query_log.history, 1) -- Remove oldest
    end

    -- Write to file (async to avoid blocking)
    vim.schedule(function()
        local ok, err = pcall(write_log_entry, entry)
        if not ok then
            vim.notify("Failed to write log entry: " .. tostring(err), vim.log.levels.ERROR)
        end
    end)
end

-- Get recent queries from memory
function query_log.get_recent(n)
    n = n or 10
    local start = math.max(1, #query_log.history - n + 1)
    local recent = {}
    for i = start, #query_log.history do
        table.insert(recent, query_log.history[i])
    end
    return recent
end

-- Read all queries from log file (for viewing past queries)
function query_log.read_all()
    local log_path = get_log_path()
    local file = io.open(log_path, "r")
    if not file then
        return {}
    end

    local queries = {}
    for line in file:lines() do
        if line and line ~= "" then
            local ok, entry = pcall(vim.json.decode, line)
            if ok and entry then
                table.insert(queries, entry)
            end
        end
    end
    file:close()
    return queries
end

return query_log
