local curl = require("plenary.curl")
local json = vim.fn.json_encode
local env = require "env"

local project_markers = { ".git", "package.json", "pyproject.toml", ".editorconfig", ".project_root", ".env" }
local project_root = vim.fs.root(0, project_markers)
env.load_env(project_root .. "/.env")

local GROQ_API_KEY = os.getenv("GROQ_API_KEY")
-- TODO add check to see why the API key didn't make it

local function query_groq(prompt)
    local response = curl.post("https://api.groq.com/openai/v1/chat/completions", {
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. GROQ_API_KEY,
        },
        body = json({
            model = "openai/gpt-oss-20b",
            messages = {
                -- { role = "system", content = "You are GhostCursor.nvim." },
                { role = "user", content = prompt },
            },
            -- temperature = 1,
            -- max_completion_tokens = 8192,
            -- top_p = 1,
            -- stream = true,
            -- reasoning_effort = "medium",
            -- stop = "null"
        }),
    })

    if response.status == 200 then
        local decoded = vim.json.decode(response.body)
        -- print(decoded.choices[1].message.content)
        return decoded.choices[1].message.content
    else
        print("Groq API request failed:", response.status, response.body)
    end
end
