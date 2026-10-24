-- Run from repository root: lua tests/engine_spec.lua (also texlua).
package.path='./moonloader/lib/?.lua;'..package.path
local E=require 'petarz.engine'
local C=require 'petarz.catalog'
local passed=0
local function eq(a,b,msg) assert(a==b,(msg or 'equal')..': '..tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<.001,tostring(a)..' != '..tostring(b)) end
local function test(name,fn)
    local ok,err=pcall(fn)
    if not ok then io.stderr:write('FAIL '..name..': '..tostring(err)..'\n'); os.exit(1) end
    passed=passed+1; print('PASS '..name)
end
local noon=os.time{year=2026,month=10,day=24,hour=12,min=0,sec=0}
local night=os.time{year=2026,month=10,day=24,hour=23,min=0,sec=0}
local function fresh(t) return E.new(t or noon,'Персик','boy') end
test('new pet identity and Russian name validation',function()
    local s=E.new(noon,'  Мурка  ','girl')
    eq(s.name,'Мурка'); eq(s.sex,'girl'); eq(s.room,'bedroom'); eq(E.level(s),1)
    assert(E.validateName('Ёжик')); assert(not E.validateName('Кот<script>'))
    assert(not E.validateName('abcdefghijklmnopq')); assert(not E.validateName('\255'))
    assert(not E.validateName('Їжак')); assert(not E.validateName('--')); assert(not E.validateName('Кот123'))
end)
test('daylight rates are slow and clock rollback changes nothing',function()
    local s=fresh(); E.tick(s,noon+3600)
    near(s.stats.hunger,76); near(s.stats.energy,83.8); near(s.stats.bond,20)
    local saved=E.export(s); E.tick(s,noon)
    eq(s.lastUpdate,saved.lastUpdate); eq(s.stats.hunger,saved.stats.hunger)
end)
test('overnight awake penalty only while online',function()
    local online=fresh(night); local offline=E.export(online)
    E.tick(online,night+7200,true); E.tick(offline,night+7200,false)
    assert(online.stats.energy<offline.stats.energy)
    near(online.stats.bond,17); near(offline.stats.bond,20)
    assert(online.stats.joy<offline.stats.joy)
end)
test('offline catchup is capped and cannot destroy relationship',function()
    local raw=fresh(); raw.stats.bond=72
    local s=E.restore(raw,noon+365*86400)
    eq(s.stats.bond,72); eq(s.stats.health,100)
    assert(s.stats.hunger>=20); assert(s.stats.energy>=25); assert(s.stats.joy>=25)
    eq(s.lastUpdate,noon+365*86400)
end)
test('offline values below safety floors do not worsen',function()
    local s=fresh(); s.stats.hunger=8; s.stats.energy=12; s.stats.joy=10
    E.tick(s,noon+86400,false)
    near(s.stats.hunger,8); near(s.stats.energy,12); near(s.stats.joy,10)
end)
test('sleep restores energy and survives save/reload',function()
    local s=fresh(night); s.stats.energy=10
    assert(E.act(s,'sleep',nil,night)); eq(E.mood(s),'sleeping')
    assert(not E.act(s,'pet',nil,night+30))
    s=E.restore(E.export(s),night+8*3600)
    near(s.stats.energy,100); eq(s.stats.bond,20)
    assert(E.act(s,'wake',nil,night+8*3600)); eq(s.sleeping,false)
    assert(s.achievements.sleep); near(s.stats.bond,21)
end)
test('feeding consumes food once and prevents click farming',function()
    local s=fresh(); s.stats.hunger=45
    local count=s.inventory.apple
    assert(E.act(s,'feed','apple',noon)); eq(s.inventory.apple,count-1)
    local xp=s.xp
    assert(not E.act(s,'feed','apple',noon+1)); eq(s.inventory.apple,count-1); eq(s.xp,xp)
    s.stats.hunger=100
    assert(not E.act(s,'feed','porridge',noon+301)); eq(s.inventory.porridge,2)
end)
test('daily care bonus is once per calendar day',function()
    local s=fresh(); s.stats.hunger=40; s.stats.hygiene=40
    assert(E.act(s,'feed','apple',noon)); assert(E.act(s,'wash',nil,noon)); assert(E.act(s,'pet',nil,noon))
    eq(s.coins,192); eq(s.daily.care.reward,true)
    assert(E.act(s,'pet',nil,noon+601)); eq(s.coins,192)
end)
test('store enforces level price ownership and inventory',function()
    local s=fresh(); local coins=s.coins
    assert(not E.act(s,'buy',{kind='room',id='kitchen'},noon)); eq(s.coins,coins)
    s.xp=60; assert(E.act(s,'buy',{kind='clothes',id='scarf'},noon)); eq(s.coins,60)
    assert(not E.act(s,'buy',{kind='clothes',id='scarf'},noon)); eq(s.coins,60)
    assert(E.act(s,'outfit','scarf',noon)); eq(s.outfit,'scarf')
    assert(not E.act(s,'room','kitchen',noon)); eq(s.room,'bedroom')
    assert(E.act(s,'buy',{kind='food',id='apple'},noon)); eq(s.coins,52); eq(s.inventory.apple,4)
    s.coins=0; assert(not E.act(s,'buy',{kind='food',id='apple'},noon)); eq(s.coins,0)
end)
test('jobs are timed and claims cannot be duplicated',function()
    local s=fresh(); local coins=s.coins
    assert(E.act(s,'work','flowers',noon)); assert(s.job)
    assert(not E.act(s,'collect',nil,noon+599)); eq(s.coins,coins)
    assert(not E.act(s,'work','flowers',noon+600)); eq(s.coins,coins)
    assert(E.act(s,'collect',nil,noon+600)); eq(s.coins,coins+16); eq(s.job,nil)
    assert(not E.act(s,'collect',nil,noon+601)); eq(s.coins,coins+16)
end)
test('work income has a daily cap even across many jobs',function()
    local s=fresh(); local t=noon
    for i=1,12 do
        for _,k in ipairs({'energy','hunger','joy'}) do s.stats[k]=100 end
        assert(E.act(s,'work','flowers',t)); t=t+600
        assert(E.act(s,'collect',nil,t))
    end
    eq(s.daily.earned,180); eq(s.coins,360)
    assert(not E.act(s,'work','flowers',t))
end)
test('minigame score clamp reward cooldown and daily limit',function()
    local s=fresh(); local t=noon
    assert(not E.act(s,'game',{id='memory',score=0/0},t))
    assert(not E.act(s,'game',{id='injected',score=100},t))
    assert(E.act(s,'game',{id='memory',score=999999},t)); eq(s.coins,192)
    assert(not E.act(s,'game',{id='memory',score=100},t+1)); eq(s.coins,192)
    for i=2,12 do t=t+120; assert(E.act(s,'game',{id='pattern',score=50},t)) end
    local coins=s.coins
    assert(not E.act(s,'game',{id='rhythm',score=100},t+120)); eq(s.coins,coins); eq(s.daily.games,12)
end)
test('malformed save is normalized without throwing or fake money',function()
    local s=E.restore({name={},stats={energy=math.huge,hunger=0/0,bond=-50},coins=-99,xp='999',
        owned='oops',inventory={apple=-50},job={id='flowers'},daily=false,diary={'oops'},
        cooldowns={feed=math.huge},settings={quiet=true,gameReactions=false},theme='cream'},noon)
    eq(s.name,'Персик'); eq(s.stats.energy,88); eq(s.stats.bond,0); eq(s.coins,0); eq(s.inventory.apple,0)
    eq(s.xp,0); eq(s.job,nil); eq(s.settings.quiet,true); eq(s.settings.gameReactions,false); eq(s.theme,'cream')
    assert(E.act(s,'pet',nil,noon)); assert(s.stats.bond>0)
end)
test('game reactions are rate limited optional and never change money',function()
    local s=fresh(); local coins=s.coins
    assert(E.gameEvent(s,'damage',noon)); assert(not E.gameEvent(s,'damage',noon+1)); eq(s.coins,coins)
    s.settings.gameReactions=false; assert(not E.gameEvent(s,'death',noon+500)); eq(s.coins,coins)
end)
test('spawn and damage never suppress a new death reaction',function()
    local s=fresh()
    assert(E.gameEvent(s,'spawn',noon))
    assert(E.gameEvent(s,'damage',noon+1))
    assert(E.gameEvent(s,'death',noon+2))
    assert(not E.gameEvent(s,'death',noon+3))
    assert(not E.gameEvent(s,'damage',noon+3))
    assert(E.gameEvent(s,'spawn',noon+120))
    assert(not E.gameEvent(s,'damage',noon+181))
    assert(E.gameEvent(s,'damage',noon+182))
    assert(E.gameEvent(s,'death',noon+302))
end)
test('sleep and reaction settings suppress every game event',function()
    local s=fresh(); assert(E.act(s,'sleep',nil,noon))
    for _,event in ipairs({'spawn','damage','death','invalid'}) do assert(not E.gameEvent(s,event,noon+1)) end
    assert(E.act(s,'wake',nil,noon+2)); s.settings.gameReactions=false
    for _,event in ipairs({'spawn','damage','death'}) do assert(not E.gameEvent(s,event,noon+3)) end
    assert(not E.gameEvent(s,'invalid',noon+4))
end)
test('export and restore do not alias live nested state',function()
    local s=fresh(); local copy=E.export(s)
    copy.stats.hunger=1; copy.owned.rooms.garden=true
    eq(s.stats.hunger,80); eq(s.owned.rooms.garden,nil)
    local restored=E.restore(copy,noon); restored.inventory.apple=999
    eq(copy.inventory.apple,3)
end)
test('level boundaries and progress are monotone',function()
    local s=fresh()
    s.xp=59; eq(E.level(s),1); assert(E.progress(s)>.98)
    s.xp=60; eq(E.level(s),2); near(E.progress(s),0)
    s.xp=239; eq(E.level(s),2); assert(E.progress(s)>.99)
    s.xp=240; eq(E.level(s),3); near(E.progress(s),0)
    s.xp=54000; eq(E.level(s),30); eq(E.progress(s),1)
end)
test('daily reward and game limits reset on calendar change',function()
    local s=fresh(); s.daily.games=12; s.daily.earned=180; s.daily.care.reward=true
    E.tick(s,noon+86400,false)
    eq(s.daily.games,0); eq(s.daily.earned,0); eq(s.daily.care.reward,nil)
    s.stats.energy=100; s.stats.hunger=100
    assert(E.act(s,'game',{id='rhythm',score=100},noon+86400))
end)
test('restored ownership cannot equip unpurchased items',function()
    local s=E.restore({version=1,outfit='raincoat',room='studio',owned={clothes={none=true},rooms={bedroom=true}}},noon)
    eq(s.outfit,'none'); eq(s.room,'bedroom')
    assert(not E.act(s,'outfit','raincoat',noon)); assert(not E.act(s,'room','studio',noon))
end)
test('survival has bounded values and does not delete an exhausted pet',function()
    local s=fresh(night)
    for i=1,7 do E.tick(s,night+i*86400,true) end
    eq(s.name,'Персик'); assert(s.stats.health>=0); assert(s.stats.bond>=0)
    for _,value in pairs(s.stats) do assert(value>=0 and value<=100) end
    eq(E.mood(s),'tired'); assert(E.act(s,'sleep',nil,s.lastUpdate))
end)
test('catalog IDs unique and every outfit has a stable id',function()
    for _,kind in ipairs({'foods','rooms','clothes','jobs','themes','games'}) do
        local seen={}
        for _,v in ipairs(C[kind]) do assert(not seen[v.id]); seen[v.id]=true; assert(type(v.name)=='string') end
    end
    eq(C.clothes[1].id,'none'); eq(C.clothes[2].id,'scarf'); eq(C.clothes[3].id,'raincoat')
end)
print(string.format('%d engine tests passed.',passed))
