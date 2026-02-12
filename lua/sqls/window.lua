local api = vim.api

local M = {}

local sqlsgroup = api.nvim_create_augroup("SQLSBufferHelper", { clear = true })

---@alias state {bufnr: number, lines: string[], results_winnr: number | nil}
---@type table<number, state | nil>
local source_state = {}


local function get_source_state()
    local bufnr = api.nvim_get_current_buf()
    return source_state[bufnr]
end

---@return boolean
local function is_results_win()
    local winnr = api.nvim_get_current_win()
    for _, state in pairs(source_state) do
        if state.results_winnr == winnr then
            return true
        end
    end

    return false
end

---@param winnr number
local function remove_state_by_results_win(winnr)
    for source_bufnr, state in pairs(source_state) do
        if state.results_winnr == winnr then
            source_state[source_bufnr] = nil
            return
        end
    end
end

function M.hide_results()
    for _, state in pairs(source_state) do
        if state.results_winnr ~= nil then
            if api.nvim_win_is_valid(state.results_winnr) then
                api.nvim_win_close(state.results_winnr, true)
            end
            state.results_winnr = nil
        end
    end
end

---@param state state
local function notify(state)
    local label = state.lines[#state.lines - 3]
    if label ~= nil then
        api.nvim_echo({ { label } }, false, {})
    end
end

local function create_results()
    local state = get_source_state()
    if not state or state.lines == nil then return end

    local bufnr = api.nvim_create_buf(false, true)

    api.nvim_buf_set_lines(bufnr, 0, 1, false, state.lines)
    api.nvim_set_option_value('filetype', 'sqls_output', { buf = bufnr })

    local winnr = api.nvim_open_win(bufnr, false, { split = 'below', win = 0 })
    vim.wo[winnr].wrap = false

    state.results_winnr = winnr

    api.nvim_buf_set_keymap(bufnr, "n", "q", "<Cmd>q<CR>", {})
    api.nvim_buf_set_keymap(bufnr, "n", "$", "$ze", {})

    notify(state)
end


function M.show_results()
    if is_results_win() then return end

    M.hide_results()

    create_results()
end

api.nvim_create_autocmd("BufEnter", {
    group = sqlsgroup,
    callback = M.show_results,
})


api.nvim_create_autocmd("WinClosed", {
    group = sqlsgroup,
    callback = function(args)
        local winnr = tonumber(args.match)
        if winnr ~= nil then
            remove_state_by_results_win(winnr)
        end
    end,
})

function M.set_source_lines(bufnr, lines)
    source_state[bufnr] = { lines = lines, bufnr = bufnr }
end

return M
