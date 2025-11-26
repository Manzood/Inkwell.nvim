SYSTEM_PROMPT = "You are a precise code-completion agent."

-- TODO read the URL from a config file
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
OLLAMA_GENERATE_URL = "http://localhost:11434/api/generate"
OLLAMA_CHAT_URL = "http://localhost:11434/api/chat"
QUERY_NUMBER_OF_LINES = 30
MAX_LINES_TO_CHANGE = 10

MODELS = {
    PHI3 = "phi3",
    GPTOSS20B = "openai/gpt-oss-20b",
    LLAMA3_8B = "llama-3.1-8b-instant",
}

PROVIDERS = {
    GROQ = "groq",
    AWS = "aws",
    OLLAMA = "ollama",
}

-- TODO add a more basic version for weaker models.
-- Right now, I'm going to try and get the functionality working for stronger models.

-- TODO read this from config
Query_Type = {
    SINGLE_LINE = 0,
    MULTI_LINE = 1,
}

NO_CHANGE_STRING =
"<NO_CHANGE_STRING>" -- TODO make this something more obscure. But also something a language model won't struggle to output correctly.
-- alternative: have a specific output when it comes to deleting lines. And an empty output means no change.
DELETE_LINE_STRING = "<DELETE_LINE_STRING>"

-- TODO improve the base prompt to be more in line with the patch format
PATCH_OUTPUT_FORMAT = [[
Output Format:
{
  "patches": [
    {
      "line_start": <int>,
      "line_end": <int>,
      "new_lines": [<string>, <string>, ...]
    }
  ]
}

Explanation examples:
- If you want to suggest no change, you can output { "patches": [] }
- If you want to delete the current line, you can output { "patches": [{ "line_start": <current_line_number>, "line_end": <current_line_number - 1>, "new_lines": [] }] }
- If you want to insert code after line x, you can output { "patches": [{ "line_start": <x + 1>, "line_end": <x>, "new_lines": [<string>, <string>, ...] }] }
- If you just want to replace the contents from line x to line y, you can output { "patches": [{ "line_start": <x>, "line_end": <y>, "new_lines": [<string>, <string>, ...] }] }
]]

SINGLE_LINE_BASE_INSTRUCTIONS = [[
You are a precise code-completion agent.
You will be given a code snippet and the current line under the cursor.

Your task:
Predict the most likely improved or continued version of that single line based on the local context and project style.

Requirements:
- Suggest at most one line.
- Prefer functional or semantic improvements (logic, correctness, completion)
  over whitespace or cosmetic formatting.
- Keep indentation and naming consistent with the file.
- The change suggested can be an partial change in a planned series of changes. It is okay to suggest such a change because it can help guide the user in that direction.
- *Never* alter any other lines.

]]

-- TODO update this when you create your prompt
SINGLE_LINE_INPUT_FORMAT = [[
Input:
Language: <filetype>
Context Lines <start_line>-<end_line> of the file:
<code excerpt>
The user's cursor is on line <cursor_line> of the code above.

]]

-- TODO maybe remove this in the future
SINGLE_LINE_OUTPUT_FORMAT = [[
Output (JSON):
{
  "new_line": "<suggested line or empty string>"
}

]]

SINGLE_LINE_NOTES = [[
Notes:
- Please do *NOT* include any "```json```" type formatting. Just output it according to the exact output format, and it will be parsed correctly.
- Please do not ignore the whitespace in the current line when you output it.
]]

SINGLE_LINE_PROMPT = SINGLE_LINE_BASE_INSTRUCTIONS .. SINGLE_LINE_INPUT_FORMAT .. PATCH_OUTPUT_FORMAT .. SINGLE_LINE_NOTES

MULTI_LINE_BASE_INSTRUCTIONS = string.format([[
You are a precise code-completion agent.
You will be given a code snippet and the current line under the cursor.

Your task:
Predict the most likely improved or continued version of that code snippet
based on the local context and project style.

Requirements:
- You may suggest multiple lines of code, but they must form a continuous block starting from the current cursor line.
- You may change at most %d lines.
- Prefer functional or semantic improvements (logic, correctness, completion) over whitespace or cosmetic formatting.
- Keep indentation and naming consistent with the file.
- The completion can represent a *partial change* in a larger logical improvement.  (This is acceptable if it helps guide the user.)
- Never alter any lines outside your suggested block.

Do not include any other text or explanation besides the required output.

]], MAX_LINES_TO_CHANGE)

MULTI_LINE_INPUT_FORMAT = [[
Input:
Language: <filetype>
Context Lines <start_line>-<end_line> of the file:
<code excerpt>
The user's cursor is on line <cursor_line> of the code above.

]]

-- TODO once again this is an old format, possibly remove this
MULTI_LINE_OUTPUT_FORMAT = [[
Output (JSON):
Output:
You must produce exactly ONE of the following:

1. A JSON object of the form:
   {
     "new_lines": [
     "<suggested line or empty string>",
       "<suggested line or empty string>",
       ...
     ]
   }

2. If you predict NO meaningful change, output exactly:
   "<NO_CHANGE_STRING>"

3. If you intend to DELETE the current line entirely, output exactly:
   "<DELETE_LINE_STRING>"

]]

MULTI_LINE_NOTES = [[
Notes:
- Output according to the output format only - do NOT include ```json fences.
- Preserve indentation and whitespace exactly as appropriate for the code style.
]]

MULTI_LINE_PROMPT = MULTI_LINE_BASE_INSTRUCTIONS .. MULTI_LINE_INPUT_FORMAT .. PATCH_OUTPUT_FORMAT .. MULTI_LINE_NOTES

-- TODO add parsing for backticks and JSON in the response, since some smaller language models don't seem to understand the output format no matter how specific you are
-- It might just be easier to ask every model to output in a well-known JSON format, and then parse it.