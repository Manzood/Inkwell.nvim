-- responsible for storing the query until a tab completion is triggered
Previous_Query_Data = {
    request_id = 0,
    response = "",
    suggested_changes = {},
    cursor_line = 0,
    used = false,
    valid_change = false,
}
