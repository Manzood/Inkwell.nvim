-- local curl = require("plenary.curl")
-- local json = vim.fn.json_encode
local env = require "env"
local display_diff = require("display-diff")
local project_markers = { ".git", "package.json", "pyproject.toml", ".editorconfig", ".project_root", ".env" }
local project_root = vim.fs.root(0, project_markers)
local logger = require("logger")
local mdebug = require("debug-util").debug
require("query-data")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:match("@(.*)"), ":h:h")
package.path = package.path .. ";" .. plugin_root .. "/tools/?.lua"
local log_viewer = require("log-viewer.init")

env.load_env(project_root .. "/.env")

-- TODO read the URL from a config file
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
OLLAMA_GENERATE_URL = "http://localhost:11434/api/generate"
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"

-- create enum for models
local MODELS = {
    PHI3 = "phi3",
    GPTOSS20B = "openai/gpt-oss-20b",
    LLAMA3_8B = "llama-3.1-8b-instant",
}

local PROVIDERS = {
    GROQ = "groq",
    AWS = "aws",
    OLLAMA = "ollama",
}

NO_CHANGE_STRING =
"<NO_CHANGE_STRING>" -- TODO make this something more obscure. But also something a language model won't struggle to output correctly.
-- alternative: have a specific output when it comes to deleting lines. And an empty output means no change.
DELETE_LINE_STRING = "<DELETE_LINE_STRING>"

local API_AGENT_PROMPT = [[
You are a precise code-completion agent.
You will be given a code snippet and the current line under the cursor.

Your task:
Predict the most likely improved or continued version of that single line
based on the local context and project style.

Requirements:
- Suggest at most one line.
- Prefer functional or semantic improvements (logic, correctness, completion)
  over whitespace or cosmetic formatting.
- Keep indentation and naming consistent with the file.
- The change suggested can be an partial change in a planned series of changes. It is okay to suggest such a change because it can help guide the user in that direction.
- If there is no meaningful change or continuation, output the string <NO_CHANGE_STRING> as the new line. Please do not output anything aside from that.
- If you instead intend to delete the current line, output the string <DELETE_LINE_STRING> as the new line. Please do not output anything aside from that.
- *Never* alter any other lines.

Input:
Language: <filetype>
Context (±10 lines around cursor):
<code excerpt>
The user's cursor is on line <cursor_line> of the code above.

Output (JSON):
{
  "new_line": "<suggested line or empty string>"
}

Notes:
- Please do *NOT* include any "```json```" type formatting. Just output it as Json, and it will be parsed correctly.
- Please do not ignore the whitespace in the current line when you output it.
]]

-- TODO add parsing for backticks and JSON in the response, since some smaller language models don't seem to understand the output format no matter how specific you are
-- It might just be easier to ask every model to output in a well-known JSON format, and then parse it.

Suggestion_Just_Accepted = false

local GROQ_API_KEY = os.getenv("GROQ_API_KEY")
-- TODO add check to see if the API key didn't make it

Current_Request_Id = 0

function Create_Query(model, content)
    local filetype = vim.bo.filetype
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    -- trim content to be +-10 lines around the cursor line
    local lines = vim.api.nvim_buf_get_lines(0, cursor_line - 10, cursor_line + 10, false)
    local content = table.concat(lines, "\n")
    cursor_line = 10 -- TODO check if this is correct. Also try and make it configurable

    local prompt = API_AGENT_PROMPT:gsub("<filetype>", filetype):gsub("<code excerpt>", content):gsub("<cursor_line>",
        cursor_line)

    local payload = {
        model = model,
        messages = {
            { role = "system", content = "You are a precise code-completion agent." },
            { role = "user",   content = prompt },
        },
        temperature = 0.2,
        stream = false, -- TODO MIGHT NOT WORK FOR GROQ. I'll need to make some kind of query builder
    }

    return vim.fn.json_encode(payload)
end

local function sanitize_message(message)
    -- parse message to find the first line that contains the word new_line
    -- remove all lines before that line
    local lines = vim.split(message, "\n")
    local ret = message
    for i, line in ipairs(lines) do
        if line:find("new_line") then
            -- if the previous line contains only an open bracket, include that in the return value
            -- if i > 1 then mdebug("ret: ", ret, "\nprinting lines: ", lines[i - 1], "\nother:\n", lines[i]) end
            if lines[i - 1] and lines[i - 1]:find("^%s*{") then
                ret = lines[i - 1] .. "\n" .. table.concat(lines, "\n", i, #lines)
            end
            ret = table.concat(lines, "\n", i, #lines)
        end
    end
    -- TODO if nothing contained new_line, the output format was wrong

    mdebug("ret: ", ret, "ret.sub(1, 1): ", ret.sub(1, 1), "ret.sub(-1, -1): ", ret.sub(-1, -1))
    if ret:sub(1, 1) == "`" then
        mdebug(ret)
        ret = ret:sub(2, -2)
        mdebug(ret)
    end
    if ret:sub(-1, -1) == "`" then
        ret = ret:sub(1, -2)
    end
    return message
end

local function verify_message_format(message)

end

Parse_Response = function(response, provider)
    -- add check to see if it was decoded successfully
    local decoded, err = vim.json.decode(response)
    if err then
        mdebug("Error decoding response: " .. vim.inspect(err))
        mdebug("Response: " .. response)
        return
    end
    if provider == PROVIDERS.GROQ then
        if not decoded.choices then
            mdebug("Decoded.choices doesn't exist")
            mdebug(vim.inspect(decoded))
        end
        return sanitize_message(decoded.choices[1].message.content)
    elseif provider == PROVIDERS.OLLAMA then
        return sanitize_message(decoded.message.content)
    end
end

function Query_via_cmd_line(url, query, api_key)
    local request_id = Current_Request_Id
    local command = { "curl", "-s",
        "-X", "POST", url,
        "-H", "Content-Type: application/json",
    }
    if api_key and api_key ~= "" then
        table.insert(command, "-H")
        table.insert(command, "Authorization: Bearer " .. api_key)
    end
    table.insert(command, "-d")
    table.insert(command, query)
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local original_line = vim.api.nvim_buf_get_lines(0, cursor_line - 1, cursor_line, false)[1]

    local current_job = vim.system(command,
        { text = true },
        function(result)
            -- Ignore if buffer changed since this request started
            if request_id ~= Current_Request_Id then
                mdebug("Ignoring stale response.")
                return
            end

            Previous_Query_Data.request_id = Current_Request_Id
            Previous_Query_Data.response = result.stdout
            mdebug("GROQ Response: " .. Parse_Response(result.stdout, PROVIDERS.GROQ))
            -- local suggested_change = vim.json.decode(Parse_Response(result.stdout, PROVIDERS.GROQ))
            local ok, suggested_change = pcall(function()
                return vim.json.decode(Parse_Response(result.stdout, PROVIDERS.GROQ))
            end)
            if not ok then
                mdebug("Error decoding response: " .. vim.inspect(err))
                return
            end
            if not suggested_change or suggested_change.new_line == NO_CHANGE_STRING then return end

            logger.log_query({
                request_id = request_id,
                url = url,
                -- model = MODELS.GPTOSS20B,
                model = MODELS.LLAMA3_8B,
                query = query,
                response = result.stdout,
                suggested_line = suggested_change.new_line,
                cursor_line = cursor_line,
                original_line = original_line,
            })

            if suggested_change then
                if suggested_change.new_line == DELETE_LINE_STRING then
                    suggested_change.new_line = ""
                    Previous_Query_Data.delete_line = true
                end
                Previous_Query_Data.suggested_line = suggested_change.new_line
                Previous_Query_Data.request_id = request_id
                Previous_Query_Data.cursor_line = cursor_line
                Previous_Query_Data.used = false
                Previous_Query_Data.valid_change = true
                vim.schedule(function()
                    display_diff.display_diff(cursor_line, suggested_change.new_line)
                end)
            end
        end
    )

    -- TODO this probably not useful, need to take a look
    return current_job
end

-- TODO Consider streaming the output instead of having it show up in one big go
local function query_local_model(url, model, query)
    local request_id = Current_Request_Id

    -- TODO wrap creating the command in a single function
    local command = {
        "curl", "-s",
        "-X", "POST", url,
        "-H", "Content-Type: application/json",
        "-d", query,
    }
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local original_line = vim.api.nvim_buf_get_lines(0, cursor_line - 1, cursor_line, false)[1]

    local current_job = vim.system(
        command,
        { text = true },
        function(result)
            if result.code ~= 0 then
                mdebug("Ollama query failed:", result.stderr)
                return
            end

            Previous_Query_Data.request_id = request_id
            Previous_Query_Data.response = result.stdout
            mdebug("parsing done: " .. Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            -- local suggested_change = vim.json.decode(Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            local ok, suggested_change = pcall(function()
                return vim.json.decode(Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            end)
            mdebug("ok: ", ok, "suggested_change: ", suggested_change)
            if not ok then
                mdebug("Error decoding response: " .. vim.inspect(err))
                return
            end
            if not suggested_change or suggested_change.new_line == NO_CHANGE_STRING then return end

            logger.log_query({
                request_id = request_id,
                url = url,
                model = model,
                query = query,
                response = result.stdout,
                suggested_line = suggested_change.new_line,
                cursor_line = cursor_line,
                original_line = original_line,
            })

            if suggested_change then
                if suggested_change.new_line == DELETE_LINE_STRING then
                    suggested_change.new_line = ""
                    Previous_Query_Data.delete_line = true
                end
                Previous_Query_Data.suggested_line = suggested_change.new_line
                Previous_Query_Data.request_id = request_id
                Previous_Query_Data.cursor_line = cursor_line
                Previous_Query_Data.used = false
                Previous_Query_Data.valid_change = true
                vim.schedule(function()
                    display_diff.display_diff(cursor_line, suggested_change.new_line)
                end)
            end
        end
    )

    return current_job
end

function Query_Groq(content)
    Query_via_cmd_line(GROQ_URL, Create_Query(MODELS.GPTOSS20B, content), GROQ_API_KEY)
    -- Query_via_cmd_line(GROQ_URL, Create_Query(MODELS.LLAMA3_8B, content), GROQ_API_KEY)
end

function Query_Phi3(content)
    query_local_model(OLLAMA_CHAT_URL, MODELS.PHI3, Create_Query(MODELS.PHI3, content))
end

local function query_aws(prompt)

end
