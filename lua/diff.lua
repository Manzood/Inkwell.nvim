-- TODO make a function that takes two arrays of strings and returns a diff between them.
-- Add a function to check the diff to see if the diff is a single line change, or a multi-line change.
-- If it is a single line change, return the line number and the change.
-- If it is a multi-line change, return the start and end line numbers and the changes.
-- If it is not a change, return nil.

SINGLE_LINE_CHANGE = "single_line_change"
MULTI_LINE_CHANGE = "multi_line_change"
NO_CHANGE = "no_change"

diff = {
    type = NO_CHANGE,
    lines = {},
    changes = {},
}

local function get_diff(old, new)
    if old == new then
        return NO_CHANGE
    end
    for i = 1, #old do
        if old[i] ~= new[i] then
            -- append the change to the changes array
            table.insert(diff.changes, new[i])
            table.insert(diff.lines, i)
        end
    end
    if #diff.lines == 1 then
        diff.type = SINGLE_LINE_CHANGE
    else
        diff.type = MULTI_LINE_CHANGE
    end
    return diff
end
