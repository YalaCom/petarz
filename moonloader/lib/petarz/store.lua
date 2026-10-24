-- Petarz persistence. UTF-8 source; compatible with Lua 5.1 / LuaJIT.
-- load(path) -> state [, warning], or nil, error. Missing first save is normal.
-- save(path, state) -> true, or nil, error. Parent directory must already exist.
-- JSON only: save files can never run Lua. A validated .bak is used for recovery.
local Store = {}
local MAX_BYTES, MAX_DEPTH = 512 * 1024, 24
local NULL = {} -- JSON null survives parsing without creating array holes.
local serial = 0

local function validUtf8(s)
    local i, n = 1, #s
    while i <= n do
        local a = s:byte(i)
        if a < 128 then
            i = i + 1
        else
            local count, lo, hi
            if a >= 194 and a <= 223 then count, lo, hi = 1, 128, 191
            elseif a >= 224 and a <= 239 then
                count, lo, hi = 2, a == 224 and 160 or 128, a == 237 and 159 or 191
            elseif a >= 240 and a <= 244 then
                count, lo, hi = 3, a == 240 and 144 or 128, a == 244 and 143 or 191
            else return false end
            if i + count > n then return false end
            local b = s:byte(i + 1)
            if b < lo or b > hi then return false end
            for j = 2, count do
                b = s:byte(i + j)
                if b < 128 or b > 191 then return false end
            end
            i = i + count + 1
        end
    end
    return true
end

local function utf8(cp)
    if cp < 128 then return string.char(cp) end
    if cp < 2048 then return string.char(192 + math.floor(cp / 64), 128 + cp % 64) end
    if cp < 65536 then
        return string.char(224 + math.floor(cp / 4096), 128 + math.floor(cp / 64) % 64, 128 + cp % 64)
    end
    return string.char(240 + math.floor(cp / 262144), 128 + math.floor(cp / 4096) % 64,
        128 + math.floor(cp / 64) % 64, 128 + cp % 64)
end

local function decode(source)
    if #source > MAX_BYTES then error('Файл сохранения больше 512 КБ.', 0) end
    if not validUtf8(source) then error('Сохранение содержит некорректный UTF-8.', 0) end
    local p, n = 1, #source
    local function fail() error('Повреждён JSON в позиции ' .. p .. '.', 0) end
    local function space()
        while p <= n do
            local b = source:byte(p)
            if b == 32 or b == 9 or b == 10 or b == 13 then p = p + 1 else break end
        end
    end
    local function hex4()
        local h = source:sub(p, p + 3)
        if #h ~= 4 or not h:match('^%x%x%x%x$') then fail() end
        p = p + 4
        return tonumber(h, 16)
    end
    local function str()
        if source:sub(p, p) ~= '"' then fail() end
        p = p + 1
        local parts, start = {}, p
        while p <= n do
            local b = source:byte(p)
            if b == 34 then
                parts[#parts + 1] = source:sub(start, p - 1)
                p = p + 1
                return table.concat(parts)
            elseif b == 92 then
                parts[#parts + 1] = source:sub(start, p - 1)
                p = p + 1
                local c = source:sub(p, p)
                p = p + 1
                local escaped = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b',
                    f = '\f', n = '\n', r = '\r', t = '\t' }
                if c == 'u' then
                    local cp = hex4()
                    if cp >= 55296 and cp <= 56319 then
                        if source:sub(p, p + 1) ~= '\\u' then fail() end
                        p = p + 2
                        local low = hex4()
                        if low < 56320 or low > 57343 then fail() end
                        cp = 65536 + (cp - 55296) * 1024 + low - 56320
                    elseif cp >= 56320 and cp <= 57343 then fail() end
                    parts[#parts + 1] = utf8(cp)
                elseif escaped[c] then parts[#parts + 1] = escaped[c]
                else fail() end
                start = p
            elseif b < 32 then fail()
            else p = p + 1 end
        end
        fail()
    end
    local value
    value = function(depth)
        if depth > MAX_DEPTH then error('Слишком большая вложенность сохранения.', 0) end
        space()
        local c = source:sub(p, p)
        if c == '"' then return str() end
        if c == '{' then
            p = p + 1
            local result = {}
            space()
            if source:sub(p, p) == '}' then p = p + 1; return result end
            while true do
                space()
                local key = str()
                if result[key] ~= nil then error('Повтор ключа в сохранении.', 0) end
                space()
                if source:sub(p, p) ~= ':' then fail() end
                p = p + 1
                result[key] = value(depth + 1)
                space()
                c = source:sub(p, p)
                p = p + 1
                if c == '}' then return result end
                if c ~= ',' then fail() end
            end
        elseif c == '[' then
            p = p + 1
            local result = {}
            space()
            if source:sub(p, p) == ']' then p = p + 1; return result end
            while true do
                result[#result + 1] = value(depth + 1)
                space()
                c = source:sub(p, p)
                p = p + 1
                if c == ']' then return result end
                if c ~= ',' then fail() end
            end
        elseif source:sub(p, p + 3) == 'true' then p = p + 4; return true
        elseif source:sub(p, p + 4) == 'false' then p = p + 5; return false
        elseif source:sub(p, p + 3) == 'null' then p = p + 4; return NULL
        else
            local start = p
            if c == '-' then p = p + 1 end
            c = source:sub(p, p)
            if c == '0' then p = p + 1
            elseif c:match('[1-9]') then
                repeat p = p + 1 until not source:sub(p, p):match('%d')
            else fail() end
            if source:sub(p, p) == '.' then
                p = p + 1
                if not source:sub(p, p):match('%d') then fail() end
                repeat p = p + 1 until not source:sub(p, p):match('%d')
            end
            c = source:sub(p, p)
            if c == 'e' or c == 'E' then
                p = p + 1
                c = source:sub(p, p)
                if c == '+' or c == '-' then p = p + 1 end
                if not source:sub(p, p):match('%d') then fail() end
                repeat p = p + 1 until not source:sub(p, p):match('%d')
            end
            local number = tonumber(source:sub(start, p - 1))
            if not number or number ~= number or number == math.huge or number == -math.huge then fail() end
            return number
        end
    end
    local result = value(1)
    space()
    if p <= n then fail() end
    if type(result) ~= 'table' or result == NULL then error('Ожидался объект сохранения.', 0) end
    return result
end

local function encode(state)
    local seen, parts, size = {}, {}, 0
    local function add(s)
        size = size + #s
        if size > MAX_BYTES then error('Сохранение больше 512 КБ.', 0) end
        parts[#parts + 1] = s
    end
    local function str(s)
        if not validUtf8(s) then error('Строка сохранения содержит некорректный UTF-8.', 0) end
        add('"' .. s:gsub('[%z\1-\31\\"]', function(c)
            local short = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return short[c] or string.format('\\u%04x', c:byte())
        end) .. '"')
    end
    local value
    value = function(v, depth)
        if depth > MAX_DEPTH then error('Слишком большая вложенность сохранения.', 0) end
        local kind = type(v)
        if v == NULL then add('null')
        elseif kind == 'string' then str(v)
        elseif kind == 'boolean' then add(v and 'true' or 'false')
        elseif kind == 'number' then
            if v ~= v or v == math.huge or v == -math.huge then error('Недопустимое число в сохранении.', 0) end
            add((string.format('%.17g', v):gsub(',', '.')))
        elseif kind == 'table' then
            if getmetatable(v) then error('Метатаблицы нельзя сохранять.', 0) end
            if seen[v] then error('Цикл в сохранении.', 0) end
            seen[v] = true
            local keys, count, max, array = {}, 0, 0, true
            for key in pairs(v) do
                count = count + 1
                keys[#keys + 1] = key
                if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then array = false
                elseif key > max then max = key end
            end
            array = array and count > 0 and count == max
            if array then
                add('[')
                for i = 1, count do if i > 1 then add(',') end; value(v[i], depth + 1) end
                add(']')
            else
                for _, key in ipairs(keys) do
                    if type(key) ~= 'string' then error('Ключ объекта должен быть строкой.', 0) end
                end
                table.sort(keys)
                add('{')
                for i, key in ipairs(keys) do
                    if i > 1 then add(',') end
                    str(key); add(':'); value(v[key], depth + 1)
                end
                add('}')
            end
            seen[v] = nil
        else error('Несохраняемый тип: ' .. kind .. '.', 0) end
    end
    if type(state) ~= 'table' or state == NULL then error('Ожидалась таблица сохранения.', 0) end
    value(state, 1)
    add('\n')
    return table.concat(parts)
end

local function read(path)
    local file, message, code = io.open(path, 'rb')
    if not file then return nil, message, code end
    local contents, errorRead = file:read(MAX_BYTES + 1)
    local closed, errorClose = file:close()
    -- read(n) returns nil at EOF for a zero-byte file; that is corrupt JSON,
    -- rather than an inaccessible file, so normal backup repair must work.
    if not contents and errorRead then return nil, errorRead, -1 end
    contents = contents or ''
    if not closed then return nil, errorClose or 'Ошибка закрытия файла.', -1 end
    return contents
end

local function parsed(path)
    local contents, message, code = read(path)
    if not contents then return nil, message, code end
    local ok, state = pcall(decode, contents)
    if not ok then return nil, state, -2 end
    return state
end

function Store.load(path)
    if type(path) ~= 'string' or path == '' then return nil, 'Не задан путь сохранения.' end
    local state, message, code = parsed(path)
    if state then return state end
    local backup = parsed(path .. '.bak')
    if backup then return backup, 'Основное сохранение недоступно. Восстановлена резервная копия.' end
    if code == 2 then return nil, 'Сохранение пока не создано.' end
    return nil, 'Не удалось прочитать сохранение: ' .. tostring(message)
end

local function exists(path)
    local file = io.open(path, 'rb')
    if file then file:close(); return true end
    return false
end

function Store.save(path, state)
    if type(path) ~= 'string' or path == '' then return nil, 'Не задан путь сохранения.' end
    local ok, contents = pcall(encode, state)
    if not ok then return nil, contents end
    local temporary = path .. '.tmp'
    if exists(temporary) then return nil, 'Уже существует временный файл сохранения. Сохраните его отдельно и удалите .tmp.' end
    local file, message = io.open(temporary, 'wb')
    if not file then return nil, 'Нельзя создать временное сохранение: ' .. tostring(message) end
    local wrote, writeMessage = file:write(contents)
    local flushed, flushMessage = file:flush()
    local closed, closeMessage = file:close()
    if not wrote or not flushed or not closed then
        os.remove(temporary)
        return nil, 'Ошибка записи сохранения: ' .. tostring(writeMessage or flushMessage or closeMessage)
    end
    -- Verify exactly what reached the filesystem before touching the previous save.
    local verified, verifyMessage = parsed(temporary)
    if not verified then os.remove(temporary); return nil, 'Проверка записи не пройдена: ' .. tostring(verifyMessage) end
    local previous, previousError, previousCode = parsed(path)
    local oldPath
    if previous then
        oldPath = path .. '.bak'
        if exists(oldPath) then
            local removed, removeMessage = os.remove(oldPath)
            if not removed then os.remove(temporary); return nil, 'Нельзя обновить резервную копию: ' .. tostring(removeMessage) end
        end
    elseif previousCode == -2 then
        -- Do not replace a good .bak with a corrupt primary file.
        repeat
            serial = serial + 1
            oldPath = path .. '.corrupt-' .. tostring(os.time()) .. '-' .. serial
        until not exists(oldPath)
    elseif previousCode ~= 2 then
        os.remove(temporary)
        return nil, 'Предыдущее сохранение недоступно: ' .. tostring(previousError)
    end
    if oldPath then
        local moved, moveMessage = os.rename(path, oldPath)
        if not moved then os.remove(temporary); return nil, 'Нельзя сохранить предыдущую версию: ' .. tostring(moveMessage) end
    end
    local installed, installMessage = os.rename(temporary, path)
    if not installed then
        if oldPath then os.rename(oldPath, path) end
        os.remove(temporary)
        return nil, 'Нельзя установить новое сохранение: ' .. tostring(installMessage)
    end
    return true
end

return Store
