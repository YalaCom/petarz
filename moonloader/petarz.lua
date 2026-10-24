script_name('Petarz')
script_author('Petarz contributors')
script_version('1.0.0')
script_description('Локальный 2D-компаньон. /petarz')
require 'lib.moonloader'
local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local root = getWorkingDirectory()
package.path = root..'\\lib\\?.lua;'..root..'\\lib\\?\\init.lua;'..package.path
local Engine = require 'petarz.engine'
local Store = require 'petarz.store'
local Catalog = require 'petarz.catalog'
local Games = require 'petarz.games'
local UI = require 'petarz.ui'
local dataDir = root..'\\config\\petarz'
local savePath = dataDir..'\\save.json'
local state, ui, saveError
local ready, shuttingDown, escapeConsumed = false, false, false
local lastHealth, wasDead, wasSpawned, pauseAt
local lastAutosave, lastTick, nextBubble = 0, 0, 0
local pendingWelcome=false
math.randomseed(os.time() % 2147483647)

local function chat(text)
    -- SA-MP 0.3.7 consumes CP1251; mimgui and disk files consume UTF-8.
    local ok,converted = pcall(function() return encoding.UTF8:decode('[Petarz] '..text) end)
    if ok and isSampAvailable() then sampAddChatMessage(converted,0xF4BE88) end
end
local function save()
    if not state then return true end
    local ok,err = Store.save(savePath,Engine.export(state))
    if not ok then
        saveError=err
        if ui then UI.notify(ui,'Не удалось сохранить: '..tostring(err)) end
        return false
    end
    saveError=nil
    return true
end
local function act(action,arg)
    if not state then return false,'Сначала познакомьтесь с питомцем.' end
    local ok,message=Engine.act(state,action,arg,os.time())
    UI.notify(ui,message)
    if ok then
        if action=='pet' or action=='feed' then ui.bubble=Engine.thought(state,os.time()); ui.bubbleUntil=os.clock()+6 end
        save()
    end
    return ok,message
end
ui=UI.new(imgui,Engine,Catalog,Games,root..'\\resource\\petarz\\',act,save)
local function adopt(name,sex)
    local candidate=Engine.new(os.time(),name,sex)
    -- Do not pretend adoption is durable until the first save succeeds.
    local previous=state; state=candidate
    if not save() then state=previous; return end
    UI.notify(ui,'Привет, '..state.name..'! Ваша дружба начинается.')
    ui.tab='home'
end
local function closeMenu()
    ui.open[0]=false; Games.cancel(ui.game)
    if state then save() end
end
local function toggle()
    if ui.open[0] then closeMenu() else UI.toggle(ui) end
end
imgui.OnInitialize(function() UI.initialize(ui) end)
local mainFrame=imgui.OnFrame(function()
    return ready and ui.open[0] and not isPauseMenuActive()
end,function()
    UI.draw(ui,state,adopt)
end)
mainFrame.LockPlayer=true
local overlayFrame=imgui.OnFrame(function()
    return ready and state~=nil and state.settings.overlay and not ui.open[0]
        and not isPauseMenuActive() and isSampAvailable() and sampIsLocalPlayerSpawned()
end,function()
    UI.overlay(ui,state)
end)
overlayFrame.HideCursor=true
overlayFrame.LockPlayer=false

local function observePlayer(now)
    local spawned=sampIsLocalPlayerSpawned()
    local exists=doesCharExist(PLAYER_PED)
    local dead=exists and isCharDead(PLAYER_PED)
    -- SA-MP can clear the spawned flag immediately on death. Observe the ped too.
    if state.settings.gameReactions and dead and not wasDead then
        if Engine.gameEvent(state,'death',now) then
            ui.shockUntil=os.clock()+4
            ui.bubble='Я рядом. Давай немного передохнём.'; ui.bubbleUntil=os.clock()+7
        end
    end
    if spawned and exists and not dead then
        local health=getCharHealth(PLAYER_PED)
        if state.settings.gameReactions then
            if not wasSpawned then
                Engine.gameEvent(state,'spawn',now)
            elseif lastHealth and health<lastHealth-5 and Engine.gameEvent(state,'damage',now) then
                ui.shockUntil=os.clock()+3
            end
        end
        lastHealth=health
    else lastHealth=nil end
    wasDead=dead; wasSpawned=spawned
end
local function needBubble(now)
    if os.clock()<nextBubble then return end
    nextBubble=os.clock()+85
    if state.settings.quiet or state.sleeping then return end
    local a=state.stats; local h=tonumber(os.date('%H',now))
    if a.hunger<30 or a.energy<25 or a.hygiene<30 or a.joy<35 or a.bond<15 or a.health<40 or h>=23 or h<7 or (state.job and now>=state.job.finishAt) then
        ui.bubble=Engine.thought(state,now); ui.bubbleUntil=os.clock()+8
    end
end
function main()
    if type(isSampAvailable)~='function' or type(sampRegisterChatCommand)~='function' or type(sampIsLocalPlayerSpawned)~='function' then
        print('Petarz: SA-MP API unavailable. Check compatible MoonLoader / SAMPFUNCS versions.')
        return
    end
    repeat wait(250) until isSampAvailable()
    if not doesDirectoryExist(root..'\\config') then createDirectory(root..'\\config') end
    if not doesDirectoryExist(dataDir) then createDirectory(dataDir) end
    local raw,message=Store.load(savePath)
    if raw then
        if type(raw)=='table' and raw.version==Engine.VERSION then state=Engine.restore(raw,os.time())
        else
            -- Preserve unknown-version data: never overwrite a newer save with an older script.
            chat('Версия сохранения не поддерживается. Обновите Petarz; файл сохранён без изменений.')
            return
        end
    end
    sampRegisterChatCommand('petarz',toggle)
    ready=true
    lastTick=os.time(); lastAutosave=lastTick; nextBubble=os.clock()+20
    chat('Твой маленький мир готов. Меню: /petarz')
    if message and message~='Сохранение пока не создано.' then UI.notify(ui,message) end
    if not state then
        if sampIsLocalPlayerSpawned() then UI.toggle(ui) else pendingWelcome=true end
    end
    while true do
        wait(30)
        if pendingWelcome and sampIsLocalPlayerSpawned() and not isPauseMenuActive() then
            pendingWelcome=false
            if not ui.open[0] then UI.toggle(ui) end
        end
        if state then
            local now=os.time()
            if isPauseMenuActive() then
                if not pauseAt then pauseAt=now; Games.cancel(ui.game); save() end
            elseif pauseAt then
                -- Pausing is a break, not an all-night neglect session.
                Engine.tick(state,now,false); pauseAt=nil; lastTick=now
            end
            if now~=lastTick and not pauseAt then
                local continuous=now-lastTick<=10
                lastTick=now
                -- A suspended process (OS sleep / long stall) is an offline break.
                Engine.tick(state,now,continuous)
                if isSampAvailable() then observePlayer(now) end
                needBubble(now)
            end
            if now-lastAutosave>=60 then lastAutosave=now; save() end
        end
    end
end
function onWindowMessage(message,key)
    if key~=0x1B then return end
    if message==0x100 and ready and ui.open[0] then
        closeMenu(); escapeConsumed=true
        consumeWindowMessage(true,false)
    elseif message==0x101 and escapeConsumed then
        escapeConsumed=false
        consumeWindowMessage(true,false)
    end
end
function onScriptTerminate(script,quitGame)
    if script==thisScript() and not shuttingDown then
        shuttingDown=true
        if ready then save() end
    end
end
