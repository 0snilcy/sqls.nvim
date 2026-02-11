local api = vim.api
local fn = vim.fn
local util = vim.lsp.util

local nvim_exec_autocmds = api.nvim_exec_autocmds

local M = {}

local sqlsgroup = vim.api.nvim_create_augroup("SQLSBufferHelper", { clear = true })
local buf_lines = {}
local buf_windows = {}
local win_buffers = {}
local active_win_buf = nil

local function hide_widnow()
    local winnr = buf_windows[active_win_buf]

    for key, value in pairs(buf_windows) do
        if value == winnr then
            buf_windows[key] = nil
        end
    end

    if winnr ~= nil and api.nvim_win_is_valid(winnr) then
        local ok, wins = pcall(vim.api.nvim_tabpage_list_wins, 0)

        if #wins > 1 then
            vim.schedule(function()
                pcall(vim.api.nvim_win_close, winnr, true)
            end)
        else
            pcall(vim.api.nvim_buf_delete,
                vim.api.nvim_win_get_buf(winnr),
                { force = true }
            )
        end
    end

    active_win_buf = nil
end

local function show_win()
    local curbufnr = api.nvim_get_current_buf()
    if active_win_buf == curbufnr then return end

    hide_widnow()

    local lines = buf_lines[curbufnr]
    if lines == nil then return end

    local bufnr = api.nvim_create_buf(false, true)

    vim.schedule(function()
        api.nvim_buf_set_lines(bufnr, 0, 1, false, lines)
        api.nvim_set_option_value('filetype', 'sqls_output', { buf = bufnr })

        local winnr = vim.api.nvim_open_win(bufnr, false, {
            split = 'below',
            win = 0
        })

        buf_windows[curbufnr] = winnr
        win_buffers[bufnr] = true
        active_win_buf = curbufnr

        vim.wo[winnr].wrap = false

        api.nvim_buf_set_keymap(bufnr, "n", "q", "<Cmd>q<CR>", {})
        api.nvim_buf_set_keymap(bufnr, "n", "$", "$ze", {})

        local label = lines[#lines - 3]

        if label ~= nil then
            api.nvim_echo({ { label } }, false, {})
        end
    end)
end

api.nvim_create_autocmd("BufEnter", {
    group = sqlsgroup,
    callback = function(args)
        if win_buffers[args.buf] then return end
        show_win()
    end,
})

api.nvim_create_autocmd("WinClosed", {
    group = sqlsgroup,
    callback = function(args)
        local winnr = args.match

        if win_buffers[args.buf] then
            for key, value in pairs(buf_windows) do
                if value == tonumber(winnr) then
                    buf_lines[key] = nil
                end
            end
        end
    end,
})


---@param smods? vim.api.keyset.cmd.mods
---@return lsp.Handler
local function make_show_results_handler(smods)
    hide_widnow()

    return function(err, result, _)
        if err then
            vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
            return
        end
        if not result then
            return
        end


        local curbufnr = api.nvim_get_current_buf()
        buf_lines[curbufnr] = vim.split(result, '\n')
        show_win()
    end
end

---@param client_id integer
---@param command string
---@param smods? vim.api.keyset.cmd.mods
---@param range_given? boolean
---@param show_vertical? '-show-vertical'
---@param line1? integer
---@param line2? integer
function M.exec(client_id, command, smods, range_given, show_vertical, line1, line2)
    local client = assert(vim.lsp.get_client_by_id(client_id))

    local range
    if range_given then
        range = vim.lsp.util.make_given_range_params(
            { line1, 0 },
            { line2, math.huge },
            0,
            client.offset_encoding
        ).range
        range['end'].character = range['end'].character - 1
    end

    client:request(
        vim.lsp.protocol.Methods.workspace_executeCommand,
        {
            command = command,
            arguments = { vim.uri_from_bufnr(0), show_vertical },
            range = range,
        },
        make_show_results_handler(smods)
    )
end

---@alias sqls_operatorfunc fun(type: 'block'|'line'|'char', client_id: integer)

---@param show_vertical? '-show-vertical'
---@return sqls_operatorfunc
local function make_query_mapping(show_vertical)
    return function(type, client_id)
        local range
        local _, lnum1, col1, _ = unpack(fn.getpos("'["))
        local _, lnum2, col2, _ = unpack(fn.getpos("']"))
        if type == 'block' then
            vim.notify('sqls does not support block-wise ranges!', vim.log.levels.ERROR)
            return
        end

        local client = assert(vim.lsp.get_client_by_id(client_id))

        if type == 'line' then
            range = vim.lsp.util.make_given_range_params(
                { lnum1, 0 },
                { lnum2, math.huge },
                0,
                client.offset_encoding
            ).range
            range['end'].character = range['end'].character - 1
        elseif type == 'char' then
            range = vim.lsp.util.make_given_range_params(
                { lnum1, col1 - 1 },
                { lnum2, col2 - 1 },
                0,
                client.offset_encoding
            ).range
        end

        client:request(
            vim.lsp.protocol.Methods.workspace_executeCommand,
            {
                command = 'executeQuery',
                arguments = { vim.uri_from_bufnr(0), show_vertical },
                range = range,
            },
            make_show_results_handler()
        )
    end
end

M.query = make_query_mapping()
M.query_vertical = make_query_mapping('-show-vertical')

---@alias sqls_switch_function fun(client_id: integer, query: string)
---@alias sqls_prompt_function fun(client_id: integer, switch_function: sqls_switch_function, query?: string)
---@alias sqls_answer_formatter fun(answer: string): string
---@alias sqls_switcher fun(client_id: integer, query?: string)
---@alias sqls_event_name
---| 'SqlsDatabaseChoice'
---| 'SqlsConnectionChoice'


---@param client_id integer
---@param switch_function sqls_switch_function
---@param answer_formatter sqls_answer_formatter
---@param event_name sqls_event_name
---@param query? string
---@return lsp.Handler
local function make_choice_handler(client_id, switch_function, answer_formatter, event_name, query)
    return function(err, result, _)
        if err then
            vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
            return
        end
        if not result then
            return
        end
        if result == '' then
            vim.notify('sqls: No choices available')
            return
        end
        local choices = vim.split(result, '\n')
        local function switch_callback(answer)
            if not answer then return end
            switch_function(client_id, answer_formatter(answer))
            nvim_exec_autocmds('User', {
                pattern = event_name,
                data = { choice = answer },
            })
        end
        if query then
            local answer = choices[tonumber(query)]
            switch_callback(answer)
            return
        end
        vim.ui.select(choices, { prompt = 'sqls.nvim' }, switch_callback)
    end
end

---@type lsp.Handler
local function switch_handler(err, _, _)
    if err then
        vim.notify('sqls: ' .. err.message, vim.log.levels.ERROR)
    end
end

---@param command string
---@return sqls_switch_function
local function make_switch_function(command)
    return function(client_id, query)
        local client = assert(vim.lsp.get_client_by_id(client_id))
        client:request(
            vim.lsp.protocol.Methods.workspace_executeCommand,
            {
                command = command,
                arguments = { query },
            },
            switch_handler
        )
    end
end

---@param command string
---@param answer_formatter sqls_answer_formatter
---@param event_name sqls_event_name
---@return sqls_prompt_function
local function make_prompt_function(command, answer_formatter, event_name)
    return function(client_id, switch_function, query)
        local client = assert(vim.lsp.get_client_by_id(client_id))
        client:request(
            vim.lsp.protocol.Methods.workspace_executeCommand,
            {
                command = command,
            },
            make_choice_handler(client_id, switch_function, answer_formatter, event_name, query)
        )
    end
end

---@type sqls_answer_formatter
local function format_database_answer(answer) return answer end
---@type sqls_answer_formatter
local function format_connection_answer(answer) return vim.split(answer, ' ')[1] end

local database_switch_function = make_switch_function('switchDatabase')
local connection_switch_function = make_switch_function('switchConnections')
local database_prompt_function = make_prompt_function(
    'showDatabases',
    format_database_answer,
    'SqlsDatabaseChoice'
)
local connection_prompt_function = make_prompt_function(
    'showConnections',
    format_connection_answer,
    'SqlsConnectionChoice'
)

---@param prompt_function sqls_prompt_function
---@param switch_function sqls_switch_function
---@return sqls_switcher
local function make_switcher(prompt_function, switch_function)
    return function(client_id, query)
        prompt_function(client_id, switch_function, query)
    end
end

M.switch_database = make_switcher(database_prompt_function, database_switch_function)
M.switch_connection = make_switcher(connection_prompt_function, connection_switch_function)

return M
