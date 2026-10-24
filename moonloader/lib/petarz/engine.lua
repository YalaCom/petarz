-- PETARZ simulation. UTF-8, Lua 5.1/LuaJIT. No game/network/file dependencies.
local C = require 'petarz.catalog'
local E = {VERSION=1}
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function clamp(v,a,b) return math.max(a, math.min(b,v)) end
local function num(v,default,a,b)
    if not finite(v) then return default end
    return clamp(v,a or -1e12,b or 1e12)
end
local function tableOr(t) return type(t)=='table' and t or {} end
function E.validateName(n)
    if type(n)~='string' then return false,'Введите имя питомца.' end
    n=n:gsub('^%s+',''):gsub('%s+$','')
    local count,i,letters=0,1,0
    while i<=#n do
        local b=n:byte(i)
        if (b>=65 and b<=90) or (b>=97 and b<=122) then
            letters=letters+1
            i=i+1
        elseif b==32 or b==45 then
            i=i+1
        elseif b==208 or b==209 then
            local b2=n:byte(i+1)
            local russian=b==208 and b2 and (b2==129 or (b2>=144 and b2<=191)) or b==209 and b2 and (b2==145 or (b2>=128 and b2<=143))
            if not russian then return false,'Используйте русские или латинские буквы.' end
            letters=letters+1
            i=i+2
        else return false,'Используйте русские или латинские буквы, пробел и дефис.' end
        count=count+1
    end
    if count<2 or count>16 then return false,'Имя должно содержать от 2 до 16 букв.' end
    if letters==0 then return false,'В имени должна быть хотя бы одна буква.' end
    return true,n
end
local function validName(n)
    local ok,name=E.validateName(n)
    return ok and name or 'Персик'
end
local function stamp(t) return math.floor(num(t,os.time(),0,4102444800)) end
local function day(now) return os.date('%Y-%m-%d',now) end
local function log(s,text,now)
    table.insert(s.diary,1,{at=now,text=text})
    while #s.diary>24 do table.remove(s.diary) end
end
local function addXp(s,v) s.xp=math.min(54000,s.xp+v) end
local function gain(s,stat,amount) s.stats[stat]=clamp(s.stats[stat]+amount,0,100) end
local function remaining(s,key,now) return math.max(0,(s.cooldowns[key] or 0)-now) end
local function cooled(s,key,now,seconds)
    local left=remaining(s,key,now)
    if left>0 then return false, 'Немного подождём: '..math.ceil(left/60)..' мин.' end
    s.cooldowns[key]=now+seconds
    return true
end
local function awake(s)
    if s.sleeping then return false,'Тс-с... Сначала разбудите питомца.' end
    if s.job then return false,'Питомец занят делом. Дождитесь завершения и заберите награду.' end
    return true
end
local function daily(s,now)
    local d=day(now)
    if s.daily.date~=d then s.daily={date=d,earned=0,games=0,care={}} end
end
local function care(s,key,now)
    s.daily.care[key]=true
    local n=0
    for _,k in ipairs({'feed','wash','pet'}) do if s.daily.care[k] then n=n+1 end end
    if n==3 and not s.daily.care.reward then
        s.daily.care.reward=true
        s.coins=s.coins+12; addXp(s,8)
        log(s,'День заботы: еда, чистота и ласка. +12 монет.',now)
    end
end
local function achievement(s,id,text,now)
    if not s.achievements[id] then
        s.achievements[id]=now
        log(s,text,now)
    end
end
function E.new(now,name,sex)
    now=stamp(now)
    local s={version=E.VERSION,name=validName(name),sex=(sex=='girl' or sex=='female') and 'girl' or 'boy',
        bornAt=now,lastUpdate=now,coins=180,xp=0,sleeping=false,room='bedroom',theme='midnight',outfit='none',
        stats={hunger=80,energy=88,hygiene=82,joy=76,bond=20,health=100},
        owned={rooms={bedroom=true},clothes={none=true}},inventory={apple=3,porridge=2,treat=1,soup=0},
        cooldowns={},job=nil,diary={},achievements={},daily={date=day(now),earned=0,games=0,care={}},
        settings={overlay=true,gameReactions=true,quiet=false}}
    log(s,'Теперь у вас есть маленький друг. Доверие растёт постепенно.',now)
    return s
end
function E.level(s) return math.min(30,1+math.floor(math.sqrt(math.max(0,s.xp)/60))) end
function E.progress(s)
    local l=E.level(s)
    if l>=30 then return 1 end
    local prev=(l-1)^2*60
    return clamp((s.xp-prev)/(l*l*60-prev),0,1)
end
-- Small bounded slices preserve night/day transitions. Offline is capped and forgiving.
function E.tick(s,now,online)
    now=stamp(now)
    if online==nil then online=true end
    if now<=s.lastUpdate then return s end
    daily(s,now)
    local elapsed=math.min(now-s.lastUpdate,86400)
    local cursor=now-elapsed
    while cursor<now do
        local dt=math.min(300,now-cursor)
        local h=dt/3600
        local hour=tonumber(os.date('%H',math.floor(cursor+dt/2)))
        local night=hour>=23 or hour<7
        local a=s.stats
        local before={}
        if not online then for k,v in pairs(a) do before[k]=v end end
        gain(s,'hunger',-(s.sleeping and 2 or 4)*h)
        gain(s,'hygiene',-(s.sleeping and 1 or 2.4)*h)
        gain(s,'energy',(s.sleeping and 15 or -4.2)*h)
        gain(s,'joy',-(s.sleeping and .5 or 2)*h)
        if online then
            if not s.sleeping and night then
                gain(s,'energy',-4*h); gain(s,'joy',-3*h); gain(s,'bond',-1.5*h)
            end
            local deprived=a.hunger<20 or a.energy<15 or a.hygiene<15
            if deprived and not s.sleeping then gain(s,'bond',-.7*h); gain(s,'health',-2*h) end
            if a.hunger>45 and a.energy>40 and a.hygiene>45 then gain(s,'health',1.5*h) end
        else
            -- Returning after a break must never destroy the relationship or kill the pet.
            a.hunger=math.max(math.min(before.hunger,20),a.hunger)
            a.energy=math.max(math.min(before.energy,25),a.energy)
            a.hygiene=math.max(math.min(before.hygiene,20),a.hygiene)
            a.joy=math.max(math.min(before.joy,25),a.joy)
            a.bond=before.bond; a.health=before.health
        end
        cursor=cursor+dt
    end
    s.lastUpdate=now
    if s.stats.bond>=50 then achievement(s,'friend','Первое большое доверие: вы стали друзьями.',now) end
    if E.level(s)>=5 then achievement(s,'grown','Пятый уровень: столько совместных маленьких историй!',now) end
    return s
end
function E.restore(raw,now)
    now=stamp(now); raw=tableOr(raw)
    local s=E.new(now,raw.name,raw.sex)
    s.bornAt=math.floor(num(raw.bornAt,now,0,now))
    s.lastUpdate=math.floor(num(raw.lastUpdate,now,0,now))
    s.coins=math.floor(num(raw.coins,180,0,1000000)); s.xp=math.floor(num(raw.xp,0,0,54000))
    for k,v in pairs(s.stats) do s.stats[k]=num(tableOr(raw.stats)[k],v,0,100) end
    s.sleeping=raw.sleeping==true
    s.sleepStarted=math.floor(num(raw.sleepStarted,now,0,now))
    for _,kind in ipairs({'rooms','clothes'}) do
        for _,item in ipairs(C[kind]) do
            if tableOr(tableOr(raw.owned)[kind])[item.id]==true then s.owned[kind][item.id]=true end
        end
    end
    if s.owned.rooms[raw.room] then s.room=raw.room end
    if s.owned.clothes[raw.outfit] then s.outfit=raw.outfit end
    if C.find('themes',raw.theme) then s.theme=raw.theme end
    for _,food in ipairs(C.foods) do s.inventory[food.id]=math.floor(num(tableOr(raw.inventory)[food.id],s.inventory[food.id],0,999)) end
    for k,v in pairs(tableOr(raw.cooldowns)) do
        if type(k)=='string' and #k<64 and finite(v) then s.cooldowns[k]=num(v,now,0,now+86400) end
    end
    local d=tableOr(raw.daily)
    if d.date==day(now) then
        s.daily.earned=num(d.earned,0,0,180); s.daily.games=num(d.games,0,0,12)
        for _,k in ipairs({'feed','wash','pet','reward'}) do s.daily.care[k]=tableOr(d.care)[k]==true end
    end
    s.diary={}
    for _,entry in ipairs(tableOr(raw.diary)) do
        if #s.diary>=24 then break end
        if type(entry)=='table' and type(entry.text)=='string' and #entry.text<512 then
            table.insert(s.diary,{at=stamp(entry.at),text=entry.text})
        end
    end
    for k,v in pairs(tableOr(raw.achievements)) do
        if type(k)=='string' and #k<32 and finite(v) then s.achievements[k]=stamp(v) end
    end
    for _,k in ipairs({'overlay','gameReactions','quiet'}) do
        if type(tableOr(raw.settings)[k])=='boolean' then s.settings[k]=raw.settings[k] end
    end
    local j=tableOr(raw.job)
    local spec=C.find('jobs',j.id)
    if spec and finite(j.startedAt) and finite(j.finishAt) then
        local started=math.floor(clamp(j.startedAt,0,now))
        s.job={id=spec.id,startedAt=started,finishAt=math.min(started+spec.duration,math.floor(num(j.finishAt,now,started,now+spec.duration))),reward=spec.reward}
    end
    E.tick(s,now,false)
    return s
end
function E.mood(s)
    local a=s.stats
    if s.sleeping then return 'sleeping' end
    if a.energy<20 then return 'tired' end
    if a.hunger<28 then return 'hungry' end
    if a.bond<12 or a.joy<18 then return 'angry' end
    if a.hygiene<25 or a.joy<40 or a.health<40 then return 'sad' end
    return 'happy'
end
function E.thought(s,now)
    local a=s.stats
    if s.sleeping then return 'Мне снится наш уютный дом...' end
    if s.job then
        if stamp(now)>=s.job.finishAt then return 'Моё дело закончено! Можно забрать награду.' end
        return 'У меня маленькое полезное дело.'
    end
    if a.health<40 then return 'Мне нужен отдых и забота. Побудь рядом.' end
    if a.hunger<30 then return 'Животик урчит. Можно поесть?' end
    if a.energy<25 then return 'Глазки закрываются... Уложи меня спать.' end
    if a.hygiene<30 then return 'Кажется, мне пора умыться.' end
    if a.bond<15 then return 'Давай побудем рядом. Мне не хватает тебя.' end
    if a.joy<35 then return 'Может, сыграем во что-нибудь вместе?' end
    local h=tonumber(os.date('%H',stamp(now)))
    if h>=23 or h<7 then return 'За окном ночь. Пора в кроватку.' end
    if a.bond>65 then return 'Рядом с тобой я дома.' end
    return 'У меня всё хорошо. Побудем вместе?'
end
local function result(s,text,now)
    log(s,text,now)
    return true,text
end
function E.act(s,action,arg,now)
    now=stamp(now); E.tick(s,now,true); daily(s,now)
    local a=s.stats
    if action=='theme' then
        if not C.find('themes',arg) then return false,'Такой темы нет.' end
        s.theme=arg; return true,'Тема изменена.'
    elseif action=='room' then
        if not s.owned.rooms[arg] then return false,'Сначала откройте эту комнату в магазине.' end
        s.room=arg; return true,'Устроимся поуютнее.'
    elseif action=='outfit' then
        if not s.owned.clothes[arg] then return false,'Сначала купите этот наряд.' end
        s.outfit=arg; return true,'Вот это наряд!'
    elseif action=='buy' then
        if type(arg)~='table' then return false,'Выберите покупку.' end
        local plural=({food='foods',room='rooms',clothes='clothes'})[arg.kind]
        local item=C.find(plural,arg.id)
        if not item then return false,'Такого товара нет.' end
        if E.level(s)<item.level then return false,'Откроется на уровне '..item.level..'.' end
        if arg.kind~='food' and s.owned[plural][item.id] then return false,'У вас это уже есть.' end
        if s.coins<item.price then return false,'Пока не хватает монет.' end
        if arg.kind=='food' and s.inventory[item.id]>=999 then return false,'Кладовая уже полная.' end
        s.coins=s.coins-item.price
        if arg.kind=='food' then s.inventory[item.id]=s.inventory[item.id]+1 else s.owned[plural][item.id]=true end
        return result(s,'Покупка: '..item.name..'.',now)
    elseif action=='collect' then
        if not s.job then return false,'Сейчас нет законченной работы.' end
        if now<s.job.finishAt then return false,'Питомец ещё занят. Осталось '..math.ceil((s.job.finishAt-now)/60)..' мин.' end
        local reward=math.min(s.job.reward,math.max(0,180-s.daily.earned))
        s.daily.earned=s.daily.earned+reward; s.coins=s.coins+reward; addXp(s,8); gain(s,'joy',4)
        s.job=nil
        return result(s,'Дело закончено! +'..reward..' монет.',now)
    elseif action=='wake' then
        if not s.sleeping then return false,'Питомец уже проснулся.' end
        s.sleeping=false
        if (s.sleepStarted or now)+3600<=now then gain(s,'joy',4); gain(s,'bond',1); achievement(s,'sleep','Первая спокойная ночь: сон тоже забота.',now) end
        return result(s,'Доброе утро, '..s.name..'!',now)
    end
    local ok,msg=awake(s); if not ok then return false,msg end
    if action=='sleep' then
        s.sleeping=true; s.sleepStarted=now
        return result(s,'Тихий свет, мягкая подушка. Спокойной ночи!',now)
    elseif action=='feed' then
        local food=C.find('foods',arg)
        if not food then return false,'Выберите еду.' end
        if a.hunger>90 then return false,'Питомец уже сыт. Не будем перекармливать.' end
        if s.inventory[food.id]<1 then return false,'Эта еда закончилась. Загляните в магазин.' end
        ok,msg=cooled(s,'feed',now,300); if not ok then return false,msg end
        s.inventory[food.id]=s.inventory[food.id]-1
        gain(s,'hunger',food.hunger); gain(s,'joy',food.joy); gain(s,'health',food.health); gain(s,'bond',.8); addXp(s,4)
        care(s,'feed',now)
        return result(s,'Вкусно! '..food.name..' очень кстати.',now)
    elseif action=='wash' then
        if a.hygiene>90 then return false,'Шёрстка уже чистая и пушистая.' end
        ok,msg=cooled(s,'wash',now,900); if not ok then return false,msg end
        gain(s,'hygiene',35); gain(s,'joy',4); gain(s,'bond',.8); addXp(s,4); care(s,'wash',now)
        return result(s,'Чистые лапки, мягкая шёрстка. Спасибо!',now)
    elseif action=='pet' then
        ok,msg=cooled(s,'pet',now,600); if not ok then return false,msg end
        gain(s,'bond',1.2); gain(s,'joy',7); addXp(s,3); care(s,'pet',now)
        return result(s,'Тёплые ладони. Кажется, мы стали чуть ближе.',now)
    elseif action=='play' then
        if a.energy<20 or a.hunger<20 then return false,'Сначала еда и отдых, потом игры.' end
        ok,msg=cooled(s,'play',now,1200); if not ok then return false,msg end
        gain(s,'joy',16); gain(s,'energy',-5); gain(s,'hunger',-3); gain(s,'bond',.8); addXp(s,4)
        return result(s,'Пять минут дурачества — и мир светлее.',now)
    elseif action=='work' then
        local j=C.find('jobs',arg)
        if not j then return false,'Выберите занятие.' end
        if E.level(s)<j.level then return false,'Нужен уровень '..j.level..'.' end
        if s.daily.earned>=180 then return false,'На сегодня достаточно работы. Пора отдыхать.' end
        if a.energy<35 or a.hunger<30 then return false,'Для дела нужны силы: сначала поесть и отдохнуть.' end
        gain(s,'energy',-8); gain(s,'hunger',-4); gain(s,'joy',-3)
        s.job={id=j.id,startedAt=now,finishAt=now+j.duration,reward=j.reward}
        return result(s,'Маленькое дело: '..j.name..'.',now)
    elseif action=='game' then
        if type(arg)~='table' or not C.find('games',arg.id) or not finite(arg.score) then return false,'Результат игры не распознан.' end
        if a.energy<15 or a.hunger<15 then return false,'Игры подождут: питомцу нужен отдых и еда.' end
        if s.daily.games>=12 then return false,'Сегодня уже было много игр. Отдохнём вместе.' end
        ok,msg=cooled(s,'game',now,120); if not ok then return false,msg end
        local score=clamp(arg.score,0,100)
        local reward=math.floor(3+score*.09)
        s.coins=s.coins+reward; s.daily.games=s.daily.games+1; addXp(s,math.floor(2+score*.04))
        gain(s,'joy',5+score*.05); gain(s,'energy',-3); gain(s,'hunger',-2); gain(s,'bond',.5)
        achievement(s,'first_game','Первая совместная игра. Начало коллекции воспоминаний.',now)
        return result(s,'Спасибо за игру! +'..reward..' монет.',now)
    end
    return false,'Неизвестное действие.'
end
function E.gameEvent(s,event,now)
    if not s.settings.gameReactions then return false end
    now=stamp(now); E.tick(s,now,true)
    local duration=({damage=180,death=300,spawn=120})[event]
    if not duration or s.sleeping or remaining(s,'event:'..event,now)>0 then return false end
    s.cooldowns['event:'..event]=now+duration
    if event=='damage' then
        gain(s,'joy',-2)
        log(s,'Ты в порядке? Я немного волнуюсь за тебя.',now)
        return true,'Ты в порядке? Береги себя.'
    elseif event=='death' then
        -- A serious event can follow a recent hit or spawn. Its aftermath should
        -- not immediately produce a second stream of minor damage reactions.
        s.cooldowns['event:damage']=math.max(s.cooldowns['event:damage'] or 0,now+180)
        gain(s,'joy',-4)
        log(s,'Давай передохнём. Я рядом.',now)
        return true,'Давай передохнём. Я рядом.'
    elseif event=='spawn' then
        return true,'С возвращением! Как хорошо, что ты рядом.'
    end
    return false
end
function E.export(s)
    local function copy(v)
        if type(v)~='table' then return v end
        local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t
    end
    return copy(s)
end
return E
