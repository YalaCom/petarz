-- Run from repository root: lua tests/store_spec.lua
package.path = './moonloader/lib/?.lua;' .. package.path
local Store = require 'petarz.store'
local root = '/tmp/petarz-store-spec-' .. tostring(os.time()) .. '-' .. tostring(math.random(100000, 999999))
local checked = 0
local function check(value, message)
    checked = checked + 1
    assert(value, message)
end
local function write(path, text)
    local f = assert(io.open(path, 'wb')); assert(f:write(text)); assert(f:close())
end
local function clean(path)
    os.remove(path); os.remove(path .. '.bak'); os.remove(path .. '.tmp')
end

local missing, reason = Store.load(root)
check(missing == nil and reason == 'Сохранение пока не создано.', 'new save should be absent')
local s = { name = 'Лисёнок Ёжик', sex = 'boy', stats = { hunger = 87.25 },
    coins = 125, sleeping = false, owned = { scarf = true },
    escaped = '"строка"\\\n\t\0', list = { 1, false, 'ёж' }, empty = {} }
check(Store.save(root, s), 'save valid state')
local loaded, warning = Store.load(root)
check(loaded.name == s.name and loaded.escaped == s.escaped, 'UTF8 and control chars roundtrip')
check(loaded.list[2] == false and loaded.stats.hunger == 87.25 and warning == nil, 'types roundtrip')
s.coins = 200
check(Store.save(root, s), 'repeat save')
local backup = assert(Store.load(root .. '.bak'))
check(backup.coins == 125, 'backup must contain last committed state')
write(root, '{broken json')
loaded, warning = Store.load(root)
check(loaded.coins == 125 and warning ~= nil, 'corrupt primary uses backup')
check(Store.save(root, { name = 'Восстановлен', coins = 130 }), 'repair corrupt primary')
check(assert(Store.load(root)).coins == 130, 'repaired primary loads')
check(assert(Store.load(root .. '.bak')).coins == 125, 'repair retains valid backup')
write(root, '')
check(assert(Store.load(root)).coins == 125, 'empty primary uses backup')
check(Store.save(root, { name = 'После пустого файла', coins = 140 }), 'repair empty primary')
check(assert(Store.load(root)).coins == 140, 'empty primary repaired')
os.remove(root .. '.bak')

write(root, '{"name":"\\u041b\\u0438\\u0441\\u0451\\u043d\\u043e\\u043a","star":"\\uD83C\\uDF1F"}')
loaded = assert(Store.load(root))
check(loaded.name == 'Лисёнок' and #loaded.star == 4, 'unicode and surrogate decoding')
for _, invalid in ipairs({
    '{"x":1,"x":2}', '{"x":null,"x":1}', '{"x":01}', '{"x":1.}', '{"x":1e}',
    '{"x":1e9999}', '{"x":NaN}', '{"x":"\\uD800"}', '{"x":"\\uDC00"}',
    '{"x":"\\q"}', '{"x":[1,]}', '{"x":true} garbage', 'false',
    '{"x":"' .. string.char(192, 128) .. '"}', string.rep('[', 30) .. '1' .. string.rep(']', 30),
    'os.execute("touch /tmp/petarz-store-should-never-exist")',
}) do
    write(root, invalid)
    check(Store.load(root) == nil, 'reject invalid input: ' .. invalid:sub(1, 35))
end
write(root, string.rep(' ', 512 * 1024 + 1))
check(Store.load(root) == nil, 'size limit on load')
clean(root)
local cycle = {}; cycle.self = cycle
check(Store.save(root, cycle) == nil, 'reject cycles')
check(Store.save(root, { bad = 0 / 0 }) == nil, 'reject NaN')
check(Store.save(root, { bad = math.huge }) == nil, 'reject infinity')
check(Store.save(root, { bad = function() end }) == nil, 'reject functions')
check(Store.save(root, { bad = string.rep('a', 512 * 1024) }) == nil, 'size limit on save')
check(Store.save(root, { good = true }), 'valid save remains possible after errors')
write(root .. '.tmp', 'unknown data')
check(Store.save(root, { good = false }) == nil, 'do not overwrite unknown temp')
check(assert(Store.load(root)).good == true, 'previous state survives failed write')
check(io.open('/tmp/petarz-store-should-never-exist', 'rb') == nil, 'no execution')
clean(root)
-- Corrupt originals are intentionally preserved for inspection. Remove this run's one quarantine.
os.remove(root .. '.corrupt-' .. tostring(os.time()) .. '-1')
print('store_spec: ' .. checked .. ' checks passed')
