local lang = require 'lang'

local w2l
local wtg
local wct
local wts

local type = type
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local find = string.find
local gsub = string.gsub
local format = string.format
local rep = string.rep
local buf
local lml_table

local sp_rep = setmetatable({}, {
    __index = function (self, k)
        self[k] = rep(' ', k)
        return self[k]
    end,
})

local function lml_string(str)
    if type(str) == 'string' then
        -- Check string from WTS firstly.
        if find(str, '^TRIGSTR_%d+$') then
            str = w2l:load_wts(wts, str)
        end
        -- Then check if the string should be in quotes.
        if find(str, "[%s%:%'%c]") then
            str = format("'%s'", gsub(str, "'", "''"))
        end
    end
    return str
end

local function lml_key(str)
    if type(str) == 'string' then
        if find(str:match '^%s*(.-)%s*$', "[%s%:%'%c]") then
            str = format("'%s'", gsub(str, "'", "''"))
        end
    end
    return str
end

local function lml_value(v, sp)
    if v[2] then
        buf[#buf+1] = format('%s%s: %s\n', sp_rep[sp], lml_key(v[1]), lml_string(v[2]))
    else
        buf[#buf+1] = format('%s%s\n', sp_rep[sp], lml_string(v[1]))
    end
    for i = 3, #v do
        lml_value(v[i], sp+4)
    end
end

local function convert_lml(tbl)
    buf = {}
    for i = 3, #tbl do
        lml_value(tbl[i], 0)
    end
    return table.concat(buf)
end

local function get_path(path, used, index,  max)
    local fmt = ('%%0%dd-%%s'):format(#tostring(max))
    path = path:match '^%s*(.-)%s*$'
    path = path:gsub('[$\\$/$:$*$?$"$<$>$|]', '_')
    path = fmt:format(index, path)
    while used[path:lower()] do
        local name, id = path:match '(.+)_(%d+)$'
        if name and id then
            id = id + 1
        else
            name = path
            id = 1
        end
        path = name .. '_' .. id
    end
    used[path:lower()] = true
    return path
end

local function read_dirs()
    local objs = {
        [0] = {}
    }
    for _, dir in ipairs(wtg.categories) do
        objs[dir.id] = {}
    end
    for _, trg in ipairs(wtg.triggers) do
        table.insert(objs[trg.category], trg)
    end
    for _, cat in ipairs(wtg.categories) do
        table.insert(objs[cat.category], cat)
    end
    if wtg.trgvars then
        for _, var in ipairs(wtg.trgvars) do
            table.insert(objs[var.category], var)
        end
    end
    local lml = { '', false }
    local function unpack(childs, dir_data)
        table.sort(childs, function (a, b)
            return wtg.sort[a] < wtg.sort[b]
        end)
        local used = {}
        for i, obj in ipairs(childs) do
            local result
            obj.path = get_path(obj.name, used, i, #childs)
            if obj.obj == 'trigger' then
                local trg = obj
                local trg_data = { trg.path, trg.name }
                if trg.type == 1 then
                    trg_data[#trg_data+1] = { lang.lml.COMMENT }
                end
                if trg.enable == 0 then
                    trg_data[#trg_data+1] = { lang.lml.DISABLE }
                end
                if trg.close == 1 then
                    trg_data[#trg_data+1] = { lang.lml.CLOSE }
                end
                if trg.run == 1 then
                    trg_data[#trg_data+1] = { lang.lml.RUN }
                end
                result = trg_data
            elseif obj.obj == 'var' then
                local var = obj
                local var_data = { var.path, var.name }
                result = var_data
            elseif obj.obj == 'category' then
                result = { obj.path, false }
                unpack(objs[obj.id], result)
            end
            dir_data[#dir_data+1] = result
        end
    end

    unpack(objs[0], lml)

    return convert_lml(lml)
end

local function get_trg_path(map, id, path)
    if not id or id == 0 then
        return path
    end
    local dir = map[id]
    return get_trg_path(map, dir.category, dir.path .. '\\' .. path)
end

local function read_triggers(files, map)
    if not wtg then
        return
    end
    local triggers = {}
    for i, trg in ipairs(wtg.triggers) do
        local path = get_trg_path(map, trg.category, trg.path)
        if trg.wct == 0 and trg.type == 0 then
            files[path..'.lml'] = convert_lml(trg.trg)
        end
        if #trg.des > 0 then
            files[path..'.txt'] = trg.des
        end
        if trg.wct == 1 then
            local buf = wct.triggers[i]
            if #buf > 0 then
                files[path..'.j'] = buf
            end
        end
    end
    if wtg.format_version then
        for i, var in ipairs(wtg.vars) do
            local id = var.id
            local trgvar = map[id]
            local path = get_trg_path(map, trgvar.category, trgvar.path)
            files[path..'.v.lml'] = convert_lml(var)
        end
    end
end

local function convert_vars(vars, id)
    local tbl = { '', false }
    for _, var in ipairs(vars) do
        if var.category == id then
            tbl[#tbl+1] = var
        end
    end
    return convert_lml(tbl)
end

local function convert_config(wtg)
    local lines = {}
    local function add(key, value)
        lines[#lines+1] = ('%s = %s'):format(key, value)
    end
    add('FormatVersion', wtg.format_version)
    for i = 1, 11 do
        add('Unknown'..tostring(i), wtg['unknown'..tostring(i)])
    end
    return table.concat(lines, '\r\n')
end

local function read_variables(files, map)
    local vars = convert_vars(wtg.vars, 0)
    if #vars > 0 then
        files['variable.lml'] = vars
    end
    for i, dir in ipairs(wtg.categories) do
        local vars = convert_vars(wtg.vars, dir.id)
        if #vars > 0 then
            local path = get_trg_path(map, dir.category, 'variable.lml')
            files[path] = vars
        end
    end
end

local function build_map()
    local map = {}
    for _, trg in ipairs(wtg.triggers) do
        map[trg.id] = trg
    end
    for _, cat in ipairs(wtg.categories) do
        map[cat.id] = cat
    end
    if wtg.trgvars then
        for _, var in ipairs(wtg.trgvars) do
            map[var.id] = var
        end
    end
    return map
end

return function (w2l_, wtg_, wct_, wts_)
    w2l = w2l_
    wtg = wtg_
    wct = wct_
    wts = wts_

    local files = {}

    if wtg.format_version then
        files['config.lua'] = convert_config(wtg)
    end

    if #wct.custom.comment > 0 then
        files['code.txt'] = wct.custom.comment
    end
    if #wct.custom.code > 0 then
        files['code.j'] = wct.custom.code
    end

    local listfile = read_dirs()
    if #listfile > 0 then
        files['catalog.lml'] = listfile
    end

    local map = build_map()
    read_triggers(files, map)
    if not wtg.format_version then
        read_variables(files, map)
    end

    return files
end
