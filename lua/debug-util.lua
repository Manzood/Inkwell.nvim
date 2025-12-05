DEBUG_MODE = true

local M = {}

M.debug = function(...) 
    if not DEBUG_MODE then return end
    print(...)
end

return M