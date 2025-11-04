local M = {}

-- Loads .env variables from a file into the Lua environment
function M.load_env(path)
    path = path or (vim.fn.getcwd() .. "/.env")
    local file = io.open(path, "r")
    if not file then
        vim.notify(".env file not found at " .. path, vim.log.levels.WARN)
        return
    end

    for line in file:lines() do
        local key, value = line:match("^(%S+)%s*=%s*(.+)$")
        if key and value then
            -- strip possible quotes
            value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
            vim.fn.setenv(key, value)
        end
    end

    file:close()
end

return M
