local progress = require 'progress'

local os_clock = os.clock
local pairs = pairs

local keydata

local mt = {}
mt.__index = mt

local function remove_exceeds_level(data, max_level)
    if type(data) ~= 'table' then
        return
    end
    for level in pairs(data) do
        if level > max_level then
            data[level] = nil
        end
    end
end

local function can_remove(is_slk, ttype, level, key)
    if not is_slk then
        return true
    end
    if ttype == 'doodad' then
        if level <= 10 then
            return false
        end
    else
        if level <= 4 then
            return false
        end
    end
    if keydata.profile and keydata.profile[key] then
        return false
    end
    return true
end

local function remove_same(key, data, default, obj, is_slk, ttype)
    local dest = default[key]
    if type(dest) == 'table' then
        for i = 1, #data do
            if data[i] == dest[i] and can_remove(is_slk, ttype, i, key) then
                data[i] = nil
            end
        end
        if not next(data) then
            obj[key] = nil
        end
    else
        if not is_slk and data == dest then
            obj[key] = nil
        end
    end
end

local function clean_obj(name, obj, type, default, config)
    local parent = obj._lower_parent
    local max_level = obj._max_level
    local default = default[parent]
    local is_remove_exceeds_level = config.remove_exceeds_level
    local is_remove_same = config.remove_same
    local is_slk = config.target_format == 'slk' and type ~= 'doodad'
    for key, data in pairs(obj) do
        if key:sub(1, 1) ~= '_' then
            if is_remove_exceeds_level and max_level then
                remove_exceeds_level(data, max_level)
            end
            if is_remove_same then
                remove_same(key, data, default, obj, is_slk, type)
            end
        end
    end
end

local function processing(w2l, type, chunk)
    local default = w2l:parse_lni(io.load(w2l.default / (type .. '.ini')))
    keydata = w2l:keyconvert(type)
    local config = w2l.config
    local names = {}
    for name in pairs(chunk) do
        names[#names+1] = name
    end
    table.sort(names, function(a, b)
        return chunk[a]['_id'] < chunk[b]['_id']
    end)
    
    local clock = os_clock()
    for i, name in ipairs(names) do
        clean_obj(name, chunk[name], type, default, config)
        if os_clock() - clock >= 0.1 then
            clock = os_clock()
            message(('清理数据[%s] (%d/%d)'):format(chunk[name]._id, i, #names))
            progress(i / #names)
        end
    end
end

return function (w2l, slk)
    local count = 0
    for type, name in pairs(w2l.info.obj) do
        count = count + 1
        progress:start(count / 7)
        processing(w2l, type, slk[type])
        progress:finish()
    end
end
