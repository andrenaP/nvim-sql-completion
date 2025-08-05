local M = {}

-- Configuration
M.config = {
    min_chars = 3,
    db_path = "/link/to/folder/markdown_data.db",
    debug = true,
    completion_triggers = {
        file = {
            name = "FilePath",
            trigger = "[[",
            match = "%[%[([^%]]*)$",
            stop_trigger = "]]",
            kind = "󰆼 Link",
            sql_cmd = "SELECT path FROM files WHERE path LIKE '%%%s%%' LIMIT 10;"
        },
	tag = {
	    name = "Tag",
	    trigger = "#",
	    match = "#([^%s]*)$",
	    stop_trigger = " ",
	    kind = " Tag",
	    sql_cmd = "SELECT tag FROM tags WHERE tag LIKE '%%%s%%' LIMIT 10;"
	}
    }
}

-- Debug function
local function debug(...)
    if M.config.debug then
        local args = { ... }
        local msg = "[SQL-Completion] "
        for _, arg in ipairs(args) do
            if type(arg) == "table" then
                msg = msg .. vim.inspect(arg) .. " "
            else
                msg = msg .. tostring(arg) .. " "
            end
        end
        print(msg)
    end
end

-- Function to fetch suggestions from the SQL database
local function fetch_suggestions(prefix, config)
    debug("Fetching suggestions for prefix:", prefix, "using SQL cmd:", config.sql_cmd)
    local suggestions = {}

    -- Check if database exists
    local db_exists = vim.fn.filereadable(M.config.db_path) == 1
    if not db_exists then
        debug("Database not found at:", M.config.db_path)
        return suggestions
    end

    -- Format SQL command
    local cmd = string.format("sqlite3 %s \"%s\"", vim.fn.shellescape(M.config.db_path), config.sql_cmd:format(prefix))
    debug("Executing SQL command:", cmd)

    local handle = io.popen(cmd)
    if handle then
        for suggestion in handle:lines() do
            debug("Found suggestion:", suggestion)
            table.insert(suggestions, {
                word = suggestion:match("([^/\\]+)$"),
                kind = config.kind,
                dup = 1,
                empty = 1,
                icase = 1,
                noselect = true
            })
        end
        handle:close()
    end

    debug("Total suggestions found:", #suggestions)
    return suggestions
end

-- Function to detect context based on triggers in the config
local function detect_context(line, col)
    local before_cursor = line:sub(1, col)

    for _, trigger_config in pairs(M.config.completion_triggers) do
        local prefix = before_cursor:match(trigger_config.match)
        if prefix then
            return trigger_config, prefix
        end
    end

    return nil
end

-- Function to provide completion
function M.auto_complete()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local col = cursor[2]
    local current_line = vim.api.nvim_get_current_line()

    debug("Current line:", current_line)
    debug("Cursor position:", col)

    -- Determine the appropriate completion context
    local context, prefix = detect_context(current_line, col)
    prefix = prefix and prefix:gsub("'", "''") -- Double single quotes in prefix
    debug("Detected context:", context and context.name, "with prefix:", prefix)

    if context and prefix and #prefix >= M.config.min_chars then
        local suggestions = fetch_suggestions(prefix, context)

        -- Only trigger completion if there are suggestions
        if #suggestions > 0 then
            local start_col = col - #prefix
            debug("Starting completion at column:", start_col)

            -- Set completeopt to prevent auto-selection
            vim.opt.completeopt = { "menu", "menuone", "noselect", "noinsert" }

            -- Show completion menu without selecting first item
            vim.fn.complete(start_col + 1, suggestions)
        end
    end
end

-- Function to accept completion with Enter
function M.accept_completion()
    if vim.fn.pumvisible() == 1 then
        -- Get current completion info
        local info = vim.fn.complete_info()
        -- Only add stop_trigger if an item is selected
        if info.selected ~= -1 then
            local cursor = vim.api.nvim_win_get_cursor(0)
            local col = cursor[2]
            local current_line = vim.api.nvim_get_current_line()
            local context = detect_context(current_line, col)
            if context then
                debug("Accepting completion with context:", context.name, "stop_trigger:", context.stop_trigger)
                -- Close the popup menu and insert the stop_trigger
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
                vim.schedule(function()
                    vim.api.nvim_feedkeys(context.stop_trigger, "n", false)
                end)
                return ""
            end
        end
    end
    return "\n" -- Normal Enter behavior if no completion
end

-- Set up autocommand and key mappings for completion
function M.setup(opts)
    -- Merge user config with defaults
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    debug("Setting up with config:", M.config)

    -- Create autocommand group
    local group = vim.api.nvim_create_augroup("WikiAutoComplete", { clear = true })

    -- Set completeopt globally
    vim.opt.completeopt = { "menu", "menuone", "noselect", "noinsert" }

    -- Autocommand to trigger auto-completion on typing
    vim.api.nvim_create_autocmd("TextChangedI", {
        group = group,
        pattern = "*",
        callback = function()
            M.auto_complete()
        end
    })

    -- Map Enter to accept the completion
    vim.keymap.set('i', '<CR>', function()
        return M.accept_completion()
    end, { expr = true, noremap = true })

    debug("Setup complete")
end

return M
