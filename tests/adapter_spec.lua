-- Run from repository root: luajit tests/adapter_spec.lua
-- Executes the actual MoonLoader adapter with deterministic platform stubs.
-- This validates wiring and lifecycle, not the Windows/D3D/GTA binary ABI.
package.path = './moonloader/lib/?.lua;' .. package.path
local E = require 'petarz.engine'
local C = require 'petarz.catalog'
local checked = 0
local function check(value, message)
    checked = checked + 1
    assert(value, message)
end

local function machine(raw, options)
    local m = {
        now = 1792843200, clock = 100, frames = {}, commands = {}, chats = {},
        saves = {}, ticks = {}, events = {}, paused = false, health = 100,
        spawned = true, dead = false, directories = {}, consumed = 0,
    }
    if options and options.unspawned then m.spawned = false end
    local script = {}
    local platform = setmetatable({}, { __index = _G })
    local engine = setmetatable({}, { __index = E })
    engine.tick = function(s, now, online)
        m.ticks[#m.ticks + 1] = { now = now, online = online }
        return E.tick(s, now, online)
    end
    engine.gameEvent = function(s, event, now)
        m.events[#m.events + 1] = event
        return E.gameEvent(s, event, now)
    end
    local store = {
        load = function() return raw, raw and nil or 'Сохранение пока не создано.' end,
        save = function(path, state)
            m.saves[#m.saves + 1] = { path = path, data = state }
            return true
        end,
    }
    local games = { cancel = function() m.cancelled = (m.cancelled or 0) + 1 end }
    local ui = {
        new = function(_, _, _, _, _, act, save)
            m.ui = { open = { [0] = false }, game = {}, act = act, save = save }
            return m.ui
        end,
        notify = function(_, message) m.notice = message end,
        initialize = function() m.initialized = true end,
        toggle = function(u) u.open[0] = not u.open[0] end,
        draw = function(_, state, adopt) m.state, m.adopt = state, adopt end,
        overlay = function(_, state) m.overlayState = state end,
    }
    local imgui = {
        OnInitialize = function(callback) m.initialize = callback end,
        OnFrame = function(condition, draw)
            local frame = { condition = condition, draw = draw }
            m.frames[#m.frames + 1] = frame
            return frame
        end,
    }
    local modules = {
        ['lib.moonloader'] = {}, ['mimgui'] = imgui,
        ['encoding'] = { UTF8 = { decode = function(_, value) return value end } },
        ['petarz.engine'] = engine, ['petarz.catalog'] = C,
        ['petarz.games'] = games, ['petarz.ui'] = ui, ['petarz.store'] = store,
    }
    platform.require = function(name) return assert(modules[name], 'unexpected module: ' .. name) end
    platform.package = { path = package.path }
    platform.os = setmetatable({ time = function() return m.now end, clock = function() return m.clock end }, { __index = os })
    platform.math = setmetatable({ randomseed = function() end }, { __index = math })
    for _, name in ipairs({ 'script_name', 'script_author', 'script_version', 'script_description' }) do
        platform[name] = function() end
    end
    platform.getWorkingDirectory = function() return 'C:\\Games\\Arizona\\moonloader' end
    platform.isSampAvailable = function() return true end
    platform.sampRegisterChatCommand = function(name, callback) m.commands[name] = callback end
    platform.sampAddChatMessage = function(message) m.chats[#m.chats + 1] = message end
    platform.doesDirectoryExist = function(path) return m.directories[path] or false end
    platform.createDirectory = function(path) m.directories[path] = true end
    platform.isPauseMenuActive = function() return m.paused end
    platform.sampIsLocalPlayerSpawned = function() return m.spawned end
    platform.doesCharExist = function() return true end
    platform.isCharDead = function() return m.dead end
    platform.getCharHealth = function() return m.health end
    platform.consumeWindowMessage = function() m.consumed = m.consumed + 1 end
    platform.thisScript = function() return script end
    platform.PLAYER_PED = 1
    platform.wait = function(milliseconds) return coroutine.yield(milliseconds) end
    if options and options.missingNative then platform.sampIsLocalPlayerSpawned = false end
    local chunk, err
    if setfenv then
        chunk, err = loadfile('./moonloader/petarz.lua')
        if chunk then setfenv(chunk, platform) end
    else
        chunk, err = loadfile('./moonloader/petarz.lua', 't', platform)
    end
    assert(chunk, err); chunk()
    m.platform, m.script = platform, script
    m.thread = coroutine.create(platform.main)
    function m:step(seconds)
        self.now, self.clock = self.now + (seconds or 0), self.clock + (seconds or 0)
        local ok, result = coroutine.resume(self.thread)
        assert(ok, result)
        return result
    end
    m:step()
    if coroutine.status(m.thread) ~= 'dead' then m:step() end
    return m
end

local m = machine(E.export(E.new(1792843200, 'Лисёнок', 'boy')))
check(type(m.commands.petarz) == 'function' and m.commands.pet == nil, 'unique local command avoids server alias conflict')
check(#m.frames == 2 and m.frames[1].LockPlayer == true, 'main frame locks game controls')
check(m.frames[2].HideCursor == true and m.frames[2].LockPlayer == false, 'overlay leaves cursor and player free')
check(m.frames[1].condition() == false and m.frames[2].condition() == true, 'loaded pet starts as overlay')
m.initialize(); check(m.initialized, 'font/texture initialization is registered')
m.commands.petarz()
check(m.ui.open[0] and m.frames[1].condition() and not m.frames[2].condition(), 'command opens menu and hides overlay')
m.frames[1].draw()
check(m.state and m.state.name == 'Лисёнок', 'restored state reaches UI')
m.platform.onWindowMessage(0x100, 0x1B)
check(not m.ui.open[0] and m.cancelled == 1, 'Escape closes menu and abandons mini-game')
check(m.consumed == 1 and coroutine.status(m.thread) == 'suspended', 'Escape keydown consumed without blocking main loop')
m.platform.onWindowMessage(0x101, 0x1B)
check(m.consumed == 2, 'matching Escape keyup consumed after menu closes')
m.platform.onWindowMessage(0x100, 0x1B)
m.platform.onWindowMessage(0x101, 0x1B)
check(m.consumed == 2, 'Escape passes to GTA while menu closed')
m.commands.petarz(); m.commands.petarz()
check(not m.ui.open[0] and m.cancelled == 2, 'command toggles and closes through shared cleanup')

m:step(1)
m:step(61)
check(#m.saves >= 1 and m.saves[#m.saves].path:match('config\\petarz\\save.json$'), 'autosave uses supported local config path')
check(m.ticks[#m.ticks].online == false, 'long process suspension uses offline rules')
m.health = 80; m:step(1)
check(m.events[#m.events] == 'damage', 'health loss is observed locally')
check(m.ticks[#m.ticks].online == true, 'normal second resumes online rules')
local shock = m.ui.shockUntil
m.health = 70; m:step(1)
check(m.ui.shockUntil == shock, 'damage cooldown does not retrigger visible reaction')
m.dead, m.spawned = true, false; m:step(1)
check(m.events[#m.events] == 'death', 'ped death detected even when SA-MP clears spawned flag')
local events = #m.events
m:step(1)
check(#m.events == events, 'continuous death does not repeat death event')
m.spawned, m.dead, m.health = true, false, 100; m:step(1)
check(m.events[#m.events] == 'spawn', 'respawn transition observed')
m.state.sleeping = true
m.ui.shockUntil = nil
m.health = 90; m:step(1)
check(m.ui.shockUntil == nil, 'sleeping companion does not visibly react to damage')
m.state.sleeping = false
m.state.settings.gameReactions = false
events = #m.events
m.health = 70; m:step(1)
check(#m.events == events and m.ui.shockUntil == nil, 'disabled game reactions do not call engine')
m.state.settings.gameReactions = true

m.paused = true; m:step(10)
local ticks = #m.ticks
m:step(3600)
check(#m.ticks == ticks and not m.frames[1].condition() and not m.frames[2].condition(), 'pause hides UI and avoids online neglect')
m.paused = false; m:step(1)
check(#m.ticks == ticks + 1 and m.ticks[#m.ticks].online == false, 'unpause catches up using offline rules')
local saves = #m.saves
m.platform.onScriptTerminate({}, false)
check(#m.saves == saves, 'unrelated script termination ignored')
m.platform.onScriptTerminate(m.script, false)
m.platform.onScriptTerminate(m.script, true)
check(#m.saves == saves + 1, 'own shutdown saves exactly once')

local fresh = machine(nil)
check(fresh.ui.open[0], 'first launch opens adoption')
fresh.frames[1].draw(); fresh.adopt('Луна', 'girl')
fresh.frames[1].draw()
check(fresh.state and fresh.state.name == 'Луна' and fresh.state.sex == 'girl', 'adoption creates named pet')
check(#fresh.saves == 1 and fresh.saves[1].data.name == 'Луна', 'adoption saves before claiming success')
local login = machine(nil, { unspawned = true })
check(not login.ui.open[0] and not login.frames[1].condition(), 'adoption menu leaves Arizona login unobstructed')
login:step(1)
check(not login.ui.open[0], 'welcome stays pending before first spawn')
login.spawned = true; login:step(1)
check(login.ui.open[0] and login.frames[1].condition(), 'first spawn opens pending adoption menu')
login.commands.petarz(); login:step(1)
check(not login.ui.open[0], 'pending welcome is one-shot after first spawn')

local newer = machine({ version = 999 })
check(coroutine.status(newer.thread) == 'dead', 'unknown save version stops adapter')
check(#newer.saves == 0 and newer.commands.petarz == nil, 'unknown save cannot be overwritten')
check(newer.chats[1]:find('не поддерживается', 1, true), 'unknown-version warning shown')
local unsupported = machine(nil, { missingNative = true })
check(coroutine.status(unsupported.thread) == 'dead' and unsupported.commands.petarz == nil, 'missing native API stops safely before startup')
print('adapter_spec: ' .. checked .. ' checks passed')
