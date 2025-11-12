-- local curl = require("plenary.curl")
-- local json = vim.fn.json_encode
local env = require "env"
local display_diff = require("display-diff")
local project_markers = { ".git", "package.json", "pyproject.toml", ".editorconfig", ".project_root", ".env" }
local project_root = vim.fs.root(0, project_markers)
local logger = require("logger")
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
}

local PROVIDERS = {
    GROQ = "groq",
    AWS = "aws",
    OLLAMA = "ollama",
}


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
- If there is no meaningful change or continuation, output the string "\42"
- Never alter any other lines.

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

NO_CHANGE_STRING = "\\42"

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

Parse_Response = function(response, provider)
    -- add check to see if it was decoded successfully
    local decoded, err = vim.json.decode(response)
    if err then
        print("Error decoding response: " .. err)
        return
    end
    if provider == PROVIDERS.GROQ then
        return decoded.choices[1].message.content
    elseif provider == PROVIDERS.OLLAMA then
        return decoded.message.content
    end
end

function Query_via_cmd_line(url, query, api_key)
    local request_id = (Previous_Query_Data.request_id or 0) + 1
    Previous_Query_Data.request_id = request_id
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

    local current_job = vim.system(command,
        { text = true },
        function(result)
            -- Ignore if buffer changed since this request started
            if request_id ~= Previous_Query_Data.request_id then
                print("Ignoring stale response.")
                return
            end

            logger.log_query({
                request_id = request_id,
                url = url,
                model = GPTOSS20B,
                query = query,
                response = result.stdout,
            })

            -- print("Done")
            Previous_Query_Data.response = result.stdout
            -- print(result.stdout)
            local suggested_change = vim.json.decode(Parse_Response(result.stdout, PROVIDERS.GROQ))
            if suggested_change and suggested_change.new_line == NO_CHANGE_STRING then return end

            if suggested_change then
                Previous_Query_Data.suggested_line = suggested_change.new_line
                Previous_Query_Data.last_request_id = request_id
                Previous_Query_Data.line_number = cursor_line
                vim.schedule(function()
                    display_diff.display_diff(cursor_line, suggested_change.new_line)
                end)
            end
        end
    )

    return current_job
end

-- TODO Consider streaming the output instead of having it show up in one big go
local function query_local_model(url, model, query)
    local request_id = Last_Request_Id

    -- TODO wrap creating the command in a single function
    local command = {
        "curl", "-s",
        "-X", "POST", url,
        "-H", "Content-Type: application/json",
        "-d", query,
    }
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    local current_job = vim.system(
        command,
        { text = true },
        function(result)
            if result.code ~= 0 then
                print("Ollama query failed:", result.stderr)
                return
            end

            logger.log_query({
                request_id = request_id,
                url = url,
                model = model,
                query = query,
                response = result.stdout,
            })

            -- print(result.stdout)

            Last_response = result.stdout
            local suggested_change = Parse_Response(result.stdout, PROVIDERS.OLLAMA)
            -- print(suggested_change)
            if suggested_change and suggested_change == NO_CHANGE_STRING then return end
            if suggested_change then
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
end

function Query_Phi3(content)
    query_local_model(OLLAMA_CHAT_URL, MODELS.PHI3, Create_Query(MODELS.PHI3, content))
end

-- local function old_query_groq(prompt)
--     local response = curl.post(GROQ_URL, {
--         headers = {
--             ["Content-Type"] = "application/json",
--             ["Authorization"] = "Bearer " .. GROQ_API_KEY,
--         },
--         body = json({
--             model = "openai/gpt-oss-20b",
--             messages = {
--                 -- { role = "system", content = "You are GhostCursor.nvim." },
--                 { role = "user", content = prompt },
--             },
--             -- temperature = 1,
--             -- max_completion_tokens = 8192,
--             -- top_p = 1,
--             -- stream = true,
--             -- reasoning_effort = "medium",
--             -- stop = "null"
--         }),
--     })

--     if response.status == 200 then
--         local decoded = vim.json.decode(response.body)
--         -- print(decoded.choices[1].message.content)
--         return decoded.choices[1].message.content
--     else
--         print("Groq API request failed:", response.status, response.body)
--     end
-- end

local function query_aws(prompt)

end

Sample_response = [[
{"id":"chatcmpl-11f8af06-9f2e-4e88-85e8-2fda9309e5b1","object":"chat.completion","created":1762417271,"model":"openai/gpt-oss-20b","choices":[{"index":0,"message":{"
role":"assistant","content":"{\n  \"new_line\": \"    if content ~= '' then Query_Groq(content) end\"\n}","reasoning":"We need to suggest a line at cursor line 10. Let's count lin
es. Provided snippet:\n\n1 local cnt = 0\n2 Send_query = debounce(function(bufnr)\n3     local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)\n4     local content = table
.concat(lines, \"\\n\")\n5     -- send to API here\n6     cnt = cnt + 1\n7     Last_request_id = Last_request_id + 1\n8     cancel_current_request()\n9     -- Query_via_cmd_line(G
ROQ_URL, content)\n10     Query_Groq(content)\n11     -- print(\"Query sent for buffer\", bufnr, \"with count\", cnt)\n12 end, 300)\n13\n14 -- TODO maybe this will already be crea
ted elsewhere\n15 local group = api.nvim_create_augroup(\"GhostCursor\", { clear = true })\n16\n17 -- TODO double check what TextChangedI is\n18 api.nvim_create_autocmd({ \"TextCh
anged\", \"TextChangedI\" }, {\n19     group = group,\n20     callback = function(args)\n\nCursor line 10 is \"Query_Groq(content)\". We need to suggest improvement or continuatio
n. Maybe we want to pass bufnr or other context? Or handle error? Or maybe we want to add a check for empty content? Or maybe we want to throttle? But debounce already. Maybe we w
ant to add a guard: if content == \"\" then return? Or maybe we want to log? The TODO earlier: \"TODO maybe this will already be created elsewhere\" refers to group. Not relevant.
\n\nWe might want to add a check for empty content: if content == \"\" then return end. That would avoid sending empty query. That seems functional improvement.\n\nAlso maybe we w
ant to use Query_Groq(content, bufnr) if function expects buffer id. But we don't know signature.\n\nBetter: add a guard: if content == \"\" then return end. That is a small impro
vement.\n\nThus new line could be inserted before Query_Groq? But cursor is at line 10. We can replace line 10 with something else? The instruction: \"Predict the most likely impr
oved or continued version of that single line\". So we can modify line 10. So we can change \"Query_Groq(content)\" to \"if content ~= '' then Query_Groq(content) end\". That is a
 single line. That would be improvement.\n\nThus output new_line: \"if content ~= '' then Query_Groq(content) end\". Ensure indentation same as original: 4 spaces? Actually line 1
0 has 4 spaces indent? Let's check: line 2 has 4 spaces before local lines? Actually line 2: \"Send_query = debounce(function(bufnr)\" no indent. Inside function, lines 3-11 have
4 spaces indent. So line 10 has 4 spaces indent. So new line should have 4 spaces indent.\n\nThus output JSON: {\"new_line\":\"    if content ~= '' then Query_Groq(content) end\"}
.\n\nCheck: we need to escape quotes? JSON string. Use double quotes inside string. So we need to escape inner double quotes? We have single quotes inside string, so fine. So fina
l."},"logprobs":null,"finish_reason":"stop"}],"usage":{"queue_time":0.053267522,"prompt_tokens":426,"prompt_time":0.023929508,"completion_tokens":694,"completion_time":0.699691476
,"total_tokens":1120,"total_time":0.723620984,"completion_tokens_details":{"reasoning_tokens":664}},"usage_breakdown":null,"system_fingerprint":"fp_e99e93f2ac","x_groq":{"id":"req
_01k9c42r1aezpbhc2wmfjn0dkm"},"service_tier":"on_demand"}
]]
