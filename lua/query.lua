-- local curl = require("plenary.curl")
-- local json = vim.fn.json_encode
local env = require "env"
local display_diff = require("display-diff")
local my_display = require("my-display")
local project_markers = { ".git", "package.json", "pyproject.toml", ".editorconfig", ".project_root", ".env" }
local project_root = vim.fs.root(0, project_markers)
local logger = require("logger")
local mdebug = require("debug-util").debug
require("query-data")
require("constants")

local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:match("@(.*)"), ":h:h")
package.path = package.path .. ";" .. plugin_root .. "/tools/?.lua"
local log_viewer = require("log-viewer.init")

print(project_root)
env.load_env(project_root .. "/.env")

Suggestion_Just_Accepted = false
local GROQ_API_KEY = os.getenv("GROQ_API_KEY")
-- TODO add check to see if the API key didn't make it

Current_Request_Id = 0

function Create_Query(model, query_type)
    local filetype = vim.bo.filetype
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
    local start_line = math.max(cursor_line - QUERY_NUMBER_OF_LINES, 1)
    local end_line = math.min(cursor_line + QUERY_NUMBER_OF_LINES, #vim.api.nvim_buf_get_lines(0, 0, -1, false))
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
    local content = table.concat(lines, "\n")

    local prompt = query_type == Query_Type.SINGLE_LINE and SINGLE_LINE_PROMPT or MULTI_LINE_PROMPT
    prompt = prompt:gsub("<filetype>", filetype):gsub("<code excerpt>", content):gsub("<cursor_line>",
        cursor_line)
    prompt = prompt:gsub("<start_line>", start_line):gsub("<end_line>", end_line) -- TODO test this
    -- print("prompt: " .. prompt)

    local payload = {
        model = model,
        messages = {
            { role = "system", content = SYSTEM_PROMPT },
            { role = "user",   content = prompt },
        },
        temperature = 0.2,
        stream = false, -- TODO test out what difference this makes
    }
    return vim.fn.json_encode(payload)
end

local function sanitize_message(message)
    -- parse message to find the first line that contains the word new_line
    -- remove all lines before that line
    local lines = vim.split(message, "\n")
    local ret = message
    for i, line in ipairs(lines) do
        if line:find("{") then -- works for multi-line as well since new_line is a substring of new_lines
            ret = table.concat(lines, "\n", i, #lines)
            break
        end
    end

    -- TODO remove everything after the expected closing bracket? And then verify if it's right
    -- TODO if nothing contained new_line, the output format was wrong

    -- mdebug("ret: ", ret, "ret.sub(1, 1): ", ret.sub(1, 1), "ret.sub(-1, -1): ", ret.sub(-1, -1))
    -- TODO should probably do a little better than this
    if ret:sub(1, 1) == "`" then
        mdebug(ret)
        ret = ret:sub(2, -2)
        mdebug(ret)
    end
    if ret:sub(-1, -1) == "`" then
        ret = ret:sub(1, -2)
    end
    return ret
end

-- TODO. Possibly use regex
local function validate_message_format(message)

end

Parse_Response = function(response, provider)
    -- TODO add check to see if it was decoded successfully
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

-- TODO rename this function
function Query_via_cmd_line(url, model, query_type, api_key)
    local query = Create_Query(model, query_type)
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
            -- mdebug("GROQ Response: " .. Parse_Response(result.stdout, PROVIDERS.GROQ))
            -- local suggested_change = vim.json.decode(Parse_Response(result.stdout, PROVIDERS.GROQ))
            local ok, suggested_changes = pcall(function()
                -- TODO verify the output format in this case
                return vim.json.decode(Parse_Response(result.stdout, PROVIDERS.GROQ))
            end)
            if not ok then
                mdebug("Error decoding response: " .. vim.inspect(err))
                return
            end

            if not suggested_changes then return end -- TODO possibly redundant
            if not suggested_changes.patches or #suggested_changes.patches == 0 then return end -- TODO test this scenario

            logger.log_query({
                request_id = request_id,
                url = url,
                model = model,
                query = query,
                response = result.stdout,
                suggested_changes = suggested_changes.patches,
                cursor_line = cursor_line,
                original_line = original_line,
            })

            if suggested_changes then
                for _, patch in ipairs(suggested_changes.patches) do
                    -- catches common AI confusion about line numbers in the format 
                    -- TODO possibly rethink the format, and possibly allow the below as an acceptable output
                    if patch.line_start > patch.line_end or (patch.line_start == patch.line_end and #patch.new_lines == 0) then
                        patch.new_lines = {""}
                        patch.delete_line = true
                    end
                end
                Previous_Query_Data.suggested_changes = suggested_changes
                Previous_Query_Data.request_id = request_id
                Previous_Query_Data.cursor_line = cursor_line
                Previous_Query_Data.used = false
                Previous_Query_Data.valid_change = true
                vim.schedule(function()
                    for _, patch in ipairs(suggested_changes.patches) do
                        my_display.display_single_line_diff(cursor_line, patch.new_lines);
                    end
                end)
            end
        end
    )

    -- TODO this probably not useful, need to take a look
    return current_job
end

-- TODO Consider streaming the output instead of having it show up in one go
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
            -- mdebug("parsing done: " .. Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            -- local suggested_change = vim.json.decode(Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            local ok, suggested_change = pcall(function()
                return vim.json.decode(Parse_Response(result.stdout, PROVIDERS.OLLAMA))
            end)
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

function Query_Groq()
    Query_via_cmd_line(GROQ_URL, MODELS.GPTOSS20B, Query_Type.SINGLE_LINE, GROQ_API_KEY)
    -- Query_via_cmd_line(GROQ_URL, MODELS.GPTOSS20B, content, Query_Type.MULTI_LINE, GROQ_API_KEY)
    -- Query_via_cmd_line(GROQ_URL, MODELS.LLAMA3_8B, content, GROQ_API_KEY)
end

function Query_Phi3()
    query_local_model(OLLAMA_CHAT_URL, MODELS.PHI3, Create_Query(MODELS.PHI3, Query_Type.SINGLE_LINE))
end

-- TODO add AWS support
local function query_aws(prompt)

end
