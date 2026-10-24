-- Petarz UI. UTF-8 everywhere; only the adapter converts outgoing SA-MP chat.
local UI = {}
local palettes = {
    midnight = {bg={0.055,0.072,0.105},panel={0.085,0.11,0.15},card={0.12,0.15,0.20},text={0.94,0.95,0.98},muted={0.59,0.65,0.74},accent={1,0.66,0.37},room={0.16,0.22,0.29}},
    cream = {bg={0.97,0.95,0.91},panel={0.93,0.90,0.84},card={1,0.985,0.96},text={0.20,0.23,0.24},muted={0.43,0.45,0.44},accent={0.76,0.36,0.18},room={0.79,0.83,0.73}},
    forest = {bg={0.055,0.10,0.095},panel={0.08,0.15,0.13},card={0.12,0.21,0.18},text={0.91,0.97,0.93},muted={0.56,0.71,0.62},accent={0.68,0.86,0.48},room={0.16,0.29,0.24}}
}
local tabs = {{'home','Дом'},{'food','Кухня'},{'wardrobe','Гардероб'},{'rooms','Комнаты'},{'games','Мини-игры'},{'work','Занятия'},{'diary','Дневник'},{'settings','Настройки'}}
local moodNames = {happy='В хорошем настроении',hungry='Пора подкрепиться',sad='Нужна забота',sleeping='Видит тёплые сны',tired='Хочет отдохнуть',angry='Сегодня не выспался'}
local function mix(a,b,t) return a+(b-a)*t end
local function vec(I,c,a) return I.ImVec4(c[1],c[2],c[3],a or 1) end
local function u32(I,c,a) return I.GetColorU32Vec4(vec(I,c,a)) end
local function txt(I,s) I.TextUnformatted(tostring(s)) end
local function wrap(I,s) I.PushTextWrapPos(0); txt(I,s); I.PopTextWrapPos() end
local function muted(I,s,p) I.PushStyleColor(I.Col.Text,vec(I,p.muted)); wrap(I,s); I.PopStyleColor() end
local function gap(I,n) I.Dummy(I.ImVec2(0,n or 6)) end
local function title(I,u,s) I.PushFont(u.fontTitle); txt(I,s); I.PopFont() end
local function line(I) gap(I,3); I.Separator(); gap(I,6) end
local function button(I,label,w,h) return I.Button(label,I.ImVec2(w or -1,h or 34)) end
local function pct(v) return tostring(math.floor(v+0.5))..' / 100' end
local function ceilMinutes(seconds) return math.max(1,math.ceil(seconds/60)) end

function UI.new(I,Engine,Catalog,Games,resource,act,save)
    return {I=I,E=Engine,C=Catalog,G=Games,resource=resource,act=act,save=save,open=I.new.bool(false),tab='home',gender='boy',name=I.new.char[65](),game=Games.new(),toast='',toastUntil=0,openedAt=0,scale=1,fontsReady=false,palette=nil}
end
function UI.notify(u,message) u.toast=tostring(message); u.toastUntil=os.clock()+6 end
function UI.initialize(u)
    local I=u.I
    local io=I.GetIO(); io.IniFilename=nil
    local config=I.ImFontConfig(); config.OversampleH=2; config.OversampleV=2
    local path=u.resource..'NotoSans-Regular.ttf'
    local builder=I.ImFontGlyphRangesBuilder()
    builder:AddRanges(io.Fonts:GetGlyphRangesCyrillic())
    builder:AddText('‚„…†‡€‰‹‘’“”•–—™›№')
    u.fontRanges=I.ImVector_ImWchar()
    builder:BuildRanges(u.fontRanges)
    local ranges=u.fontRanges[0].Data
    u.font=io.Fonts:AddFontFromFileTTF(path,16,config,ranges)
    u.fontTitle=io.Fonts:AddFontFromFileTTF(path,25,config,ranges)
    u.fontSmall=io.Fonts:AddFontFromFileTTF(path,13,config,ranges)
    assert(u.font and u.fontTitle and u.fontSmall,'Petarz: NotoSans-Regular.ttf not found')
    io.FontDefault=u.font
    local ok,texture=pcall(I.CreateTextureFromFile,u.resource..'pet_atlas.png')
    if ok then u.texture=texture end
    u.outfitTextures={}
    for _,outfit in ipairs({'scarf','raincoat'}) do
        local loaded,value=pcall(I.CreateTextureFromFile,u.resource..'pet_'..outfit..'.png')
        if loaded then u.outfitTextures[outfit]=value end
    end
    u.fontsReady=true
end
function UI.toggle(u)
    u.open[0]=not u.open[0]
    if u.open[0] then u.openedAt=os.clock() end
end
local function palette(u,id)
    local target=palettes[id] or palettes.midnight
    if not u.palette then u.palette={}; for k,v in pairs(target) do u.palette[k]={v[1],v[2],v[3]} end end
    local dt=math.min(u.I.GetIO().DeltaTime,0.1)
    for k,v in pairs(target) do for n=1,3 do u.palette[k][n]=mix(u.palette[k][n],v[n],math.min(1,dt*9)) end end
    return u.palette
end
local function styles(I,p,alpha)
    local s=I.GetStyle()
    s.WindowRounding=16; s.ChildRounding=12; s.FrameRounding=8; s.GrabRounding=8; s.ScrollbarRounding=8
    s.WindowBorderSize=0; s.ChildBorderSize=0; s.FrameBorderSize=0
    s.WindowPadding=I.ImVec2(16,16); s.FramePadding=I.ImVec2(12,8); s.ItemSpacing=I.ImVec2(9,8)
    s.ScrollbarSize=7; s.Alpha=alpha
    s.Colors[I.Col.WindowBg]=vec(I,p.bg); s.Colors[I.Col.ChildBg]=vec(I,p.panel)
    s.Colors[I.Col.Text]=vec(I,p.text); s.Colors[I.Col.TextDisabled]=vec(I,p.muted)
    s.Colors[I.Col.FrameBg]=vec(I,p.card); s.Colors[I.Col.FrameBgHovered]=vec(I,p.room); s.Colors[I.Col.FrameBgActive]=vec(I,p.room)
    s.Colors[I.Col.Button]=vec(I,p.card); s.Colors[I.Col.ButtonHovered]=vec(I,p.room); s.Colors[I.Col.ButtonActive]=vec(I,p.accent,0.5)
    s.Colors[I.Col.Header]=vec(I,p.accent,0.25); s.Colors[I.Col.HeaderHovered]=vec(I,p.accent,0.35); s.Colors[I.Col.HeaderActive]=vec(I,p.accent,0.45)
    s.Colors[I.Col.CheckMark]=vec(I,p.accent); s.Colors[I.Col.SliderGrab]=vec(I,p.accent)
    s.Colors[I.Col.PlotHistogram]=vec(I,p.accent); s.Colors[I.Col.Border]=vec(I,p.muted,0.15)
    s.Colors[I.Col.Separator]=vec(I,p.muted,0.18)
end
local function pet(u,s,x,y,size,overlay)
    local I=u.I; local dl=I.GetWindowDrawList(); local mood=u.E.mood(s)
    local cell=0
    if mood=='sleeping' then cell=2 elseif mood~='happy' then cell=1
    elseif s.outfit=='scarf' then cell=3 elseif s.outfit=='raincoat' then cell=4 end
    if u.shockUntil and os.clock()<u.shockUntil and not s.sleeping then cell=5 end
    local bob=math.sin(os.clock()*(s.sleeping and 1.3 or 2.2))*2
    local breathe=math.sin(os.clock()*1.6)*1.5
    local texture=u.outfitTextures and u.outfitTextures[s.outfit] or u.texture
    if texture then
        local col,row=cell%3,math.floor(cell/3)
        dl:AddImage(texture,I.ImVec2(x,y+bob-breathe),I.ImVec2(x+size,y+size+bob),I.ImVec2(col/3,row/2),I.ImVec2((col+1)/3,(row+1)/2))
    else
        dl:AddText(I.ImVec2(x,y+size/2),u32(I,{1,0.45,0.35}),'Нет pet_atlas.png. Проверьте установку.')
    end
end
local function room(u,s,width,height)
    local I=u.I; local p=u.palette; local dl=I.GetWindowDrawList(); local pos=I.GetCursorScreenPos()
    local x,y=pos.x,pos.y
    local roomColors={bedroom=p.room,kitchen={0.47,0.39,0.27},garden={0.10,0.23,0.23},studio={0.26,0.23,0.36}}
    dl:AddRectFilled(I.ImVec2(x,y),I.ImVec2(x+width,y+height),u32(I,roomColors[s.room] or p.room),14)
    -- Architecture belongs to the room; the pet itself is a painted PNG texture.
    dl:AddRectFilled(I.ImVec2(x,y+height*0.79),I.ImVec2(x+width,y+height),u32(I,p.panel,0.45),12)
    dl:AddCircleFilled(I.ImVec2(x+width*0.83,y+height*0.27),height*0.32,u32(I,p.accent,0.07),48)
    dl:AddRectFilled(I.ImVec2(x+24,y+24),I.ImVec2(x+106,y+94),u32(I,p.bg,0.35),10)
    dl:AddLine(I.ImVec2(x+65,y+25),I.ImVec2(x+65,y+93),u32(I,p.muted,0.25),2)
    dl:AddLine(I.ImVec2(x+25,y+59),I.ImVec2(x+105,y+59),u32(I,p.muted,0.25),2)
    if s.room=='garden' then
        for n=1,12 do
            local px=x+width*(0.35+n*0.047); local py=y+20+math.sin(n*2.1)*14
            dl:AddCircleFilled(I.ImVec2(px,py),2,u32(I,{1,0.86,0.52},0.5+math.sin(os.clock()+n)*0.25),8)
        end
        dl:AddCircleFilled(I.ImVec2(x+72,y+58),20,u32(I,{0.89,0.92,0.76}),32)
    elseif s.room=='kitchen' then
        dl:AddRectFilled(I.ImVec2(x+width*0.39,y+38),I.ImVec2(x+width*0.64,y+44),u32(I,p.accent,0.6),3)
        for n=1,3 do dl:AddCircleFilled(I.ImVec2(x+width*0.40+n*20,y+29),8,u32(I,{0.85,0.91,0.73},0.75),16) end
    elseif s.room=='studio' then
        for n=1,3 do dl:AddRectFilled(I.ImVec2(x+width*0.32+n*24,y+25+n*6),I.ImVec2(x+width*0.32+n*24+17,y+72+n*6),u32(I,{0.8,0.55+n*0.08,0.49},0.7),3) end
    end
    local roomSpec=u.C.find('rooms',s.room)
    dl:AddText(I.ImVec2(x+125,y+25),u32(I,{0.94,0.94,0.90}),roomSpec and roomSpec.name or 'Дом')
    local size=math.min(height*1.02,width*0.53)
    pet(u,s,x+width-size-8,y+height-size-2,size)
    I.SetCursorScreenPos(I.ImVec2(x+22,y+112))
    I.PushTextWrapPos(I.GetCursorPosX()+width*0.43)
    I.PushFont(u.fontTitle); txt(I,s.sleeping and 'Тихий час' or 'Рядом с тобой'); I.PopFont()
    txt(I,moodNames[u.E.mood(s)] or 'Дома хорошо')
    I.PopTextWrapPos()
    I.SetCursorScreenPos(I.ImVec2(x+22,y+height-48))
    if button(I,s.sleeping and 'Разбудить' or 'Погладить',145,32) then u.act(s.sleeping and 'wake' or 'pet') end
    I.SetCursorScreenPos(I.ImVec2(x,y+height+10))
end
local function need(I,label,value,p,width)
    I.BeginGroup(); txt(I,label); I.SameLine(); I.PushStyleColor(I.Col.Text,vec(I,p.muted)); txt(I,tostring(math.floor(value))..'%'); I.PopStyleColor()
    if value<25 then I.PushStyleColor(I.Col.PlotHistogram,I.ImVec4(0.91,0.45,0.35,1)) end
    I.ProgressBar(value/100,I.ImVec2(width,7),'')
    if value<25 then I.PopStyleColor() end
    I.EndGroup()
end
local function home(u,s,w)
    local I=u.I; local p=u.palette
    room(u,s,w,235*u.scale)
    local nw=(w-28)/3
    need(I,'Сытость',s.stats.hunger,p,nw); I.SameLine(); need(I,'Энергия',s.stats.energy,p,nw); I.SameLine(); need(I,'Чистота',s.stats.hygiene,p,nw)
    gap(I,2)
    need(I,'Радость',s.stats.joy,p,nw); I.SameLine(); need(I,'Доверие',s.stats.bond,p,nw); I.SameLine(); need(I,'Здоровье',s.stats.health,p,nw)
    gap(I,10)
    local bw=(w-18)/3
    if button(I,'Покормить',bw) then u.tab='food' end; I.SameLine()
    if button(I,'Искупать',bw) then u.act('wash') end; I.SameLine()
    if button(I,s.sleeping and 'Проснуться' or 'Уложить спать',bw) then u.act(s.sleeping and 'wake' or 'sleep') end
    gap(I,4); muted(I,u.E.thought(s,os.time()),p)
end
local function listCard(u,id,name,description,right,callback)
    local I=u.I; local p=u.palette
    I.PushIDStr(id); txt(I,name); muted(I,description,p)
    if button(I,right,-1,32) then callback() end
    line(I); I.PopID()
end
local function food(u,s)
    local I=u.I
    title(I,u,'Кухня'); muted(I,'Порции из запасов. Еда помогает, когда питомец голоден.',u.palette); line(I)
    for _,f in ipairs(u.C.foods) do
        local id=f.id
        listCard(u,'food-'..id,f.name,'В запасе: '..tostring(s.inventory[id] or 0)..'   |   '..(f.description or ''),'Угостить',function() u.act('feed',id) end)
        if button(I,'Купить порцию за '..f.price..' монет##'..id) then u.act('buy',{kind='food',id=id}) end
        gap(I,10)
    end
end
local function wardrobe(u,s)
    local I=u.I; title(I,u,'Гардероб'); muted(I,'Одежда меняет рисованный образ. Пол питомца не ограничивает выбор.',u.palette); line(I)
    for _,c in ipairs(u.C.clothes) do
        local owned=s.owned.clothes[c.id]; local id=c.id
        local label=s.outfit==id and 'Уже надето' or (owned and 'Надеть' or ('Купить: '..c.price..' монет'))
        listCard(u,'cloth-'..id,c.name,(c.description or '')..'   |   Уровень '..(c.level or 1),label,function() if s.outfit~=id then u.act(owned and 'outfit' or 'buy',owned and id or {kind='clothes',id=id}) end end)
    end
end
local function rooms(u,s)
    local I=u.I; title(I,u,'Твои маленькие миры'); muted(I,'Комнаты открываются за заботу и местные монеты.',u.palette); line(I)
    for _,r in ipairs(u.C.rooms) do
        local owned=s.owned.rooms[r.id]; local id=r.id
        local label=s.room==id and 'Ты здесь' or (owned and 'Перейти' or ('Открыть: '..r.price..' монет'))
        listCard(u,'room-'..id,r.name,(r.description or '')..'   |   Уровень '..(r.level or 1),label,function() if s.room~=id then u.act(owned and 'room' or 'buy',owned and id or {kind='room',id=id}) end end)
    end
end
local function work(u,s)
    local I=u.I; title(I,u,'Маленькие большие дела'); muted(I,'Это занятия питомца. Они не управляют персонажем и не зарабатывают деньги Arizona RP.',u.palette); line(I)
    if s.job then
        local remaining=(s.job.finishAt or s.job.endsAt or 0)-os.time()
        if remaining>0 then txt(I,'Питомец занят. Осталось около '..ceilMinutes(remaining)..' мин.') else txt(I,'Занятие закончено.') end
        if button(I,'Забрать результат') then u.act('collect') end; line(I)
    end
    for _,j in ipairs(u.C.jobs) do
        local id=j.id
        listCard(u,'job-'..id,j.name,(j.description or '')..'   |   Уровень '..(j.level or 1),'Начать занятие',function() u.act('work',id) end)
    end
end
local function diary(u,s)
    local I=u.I; title(I,u,'История вашей дружбы'); line(I)
    txt(I,'Вместе с '..os.date('%d.%m.%Y',s.bornAt)); txt(I,'Уровень '..u.E.level(s)); txt(I,'Доверие: '..pct(s.stats.bond)); txt(I,'Опыт: '..math.floor(s.xp))
    gap(I,12); wrap(I,'Забота важнее скорости. Обычная еда, сон и внимание постепенно укрепляют вашу связь. Питомец не умирает и не пропадает, даже если ты надолго уйдёшь.')
    line(I); txt(I,'Ритм дня'); wrap(I,'Ночью, с 23:00 до 07:00 по времени компьютера, питомцу нужен сон. Пока игра открыта, ночное бодрствование утомляет. Закрытая игра не отнимает любовь за пропущенный сон.')
    line(I); txt(I,'Дела на сегодня')
    local tips={s.stats.hunger<55 and 'Покорми питомца.' or 'Запас сытости хороший.',s.stats.hygiene<55 and 'Пора купаться.' or 'Питомец чистый.',s.stats.energy<35 and 'Дай питомцу выспаться.' or 'Сил хватит на новое занятие.',s.stats.bond<60 and 'Проведите немного времени вместе.' or 'Между вами крепнет доверие.'}
    for _,tip in ipairs(tips) do wrap(I,'- '..tip) end
    line(I); txt(I,'Последние события')
    for n=1,math.min(8,#s.diary) do local e=s.diary[n]; muted(I,os.date('%d.%m %H:%M',e.at)..'  '..e.text,u.palette) end
    line(I); muted(I,'Прогресс хранится только на этом компьютере. Перед переустановкой сохрани moonloader/config/petarz целиком.',u.palette)
end
local function settings(u,s)
    local I=u.I; title(I,u,'Как тебе уютнее'); line(I)
    txt(I,'Оформление')
    for _,t in ipairs({{'midnight','Полночь'},{'cream','Тёплый свет'},{'forest','Лес'}}) do
        if button(I,(s.theme==t[1] and '> ' or '')..t[2],-1) then u.act('theme',t[1]) end
    end
    line(I)
    local function check(label,key)
        local b=I.new.bool(s.settings[key]); if I.Checkbox(label,b) then s.settings[key]=b[0]; u.save() end
    end
    check('Питомец в углу экрана','overlay'); check('Тихий режим: без реплик в уголке','quiet'); check('Реакции на состояние персонажа','gameReactions')
    line(I); wrap(I,'/petarz — открыть и закрыть меню. Esc — закрыть меню. Питомец в уголке не перехватывает мышь и клавиши.')
    line(I); muted(I,'Petarz 1.0 • локальный компаньон\nБез голоса, телеметрии и сетевых запросов.\nНе является официальным продуктом Arizona RP.',u.palette)
    gap(I,8); if button(I,'Сохранить сейчас') and u.save() then UI.notify(u,'Прогресс сохранён.') end
end
local function creation(u,adopt)
    local I=u.I; local p=u.palette
    title(I,u,'Ваша история начинается здесь')
    muted(I,'Маленький друг. Большой мир. В твоём ритме.',p); gap(I,12)
    local sample={stats={hunger=80,energy=90,hygiene=85,joy=80,bond=25,health=100},outfit='none',sleeping=false}
    local pos=I.GetCursorScreenPos(); pet(u,sample,pos.x+I.GetContentRegionAvail().x/2-105,pos.y,210); I.Dummy(I.ImVec2(0,215))
    txt(I,'Как его зовут?'); I.SetNextItemWidth(-1); I.InputText('##name',u.name,65)
    muted(I,'От 2 до 16 букв. Можно по-русски, с пробелом или дефисом.',p)
    gap(I,4)
    if button(I,(u.gender=='boy' and '> ' or '')..'Мальчик',150) then u.gender='boy' end; I.SameLine()
    if button(I,(u.gender=='girl' and '> ' or '')..'Девочка',150) then u.gender='girl' end
    gap(I,12)
    if button(I,'Начать дружбу',-1,42) then
        local name=require('ffi').string(u.name)
        local ok,nameOrError=u.E.validateName(name)
        if ok then adopt(nameOrError,u.gender) else UI.notify(u,nameOrError) end
    end
    gap(I,6); muted(I,'Питомец не торопит. Не требует доната. Не исчезает, пока ты занят.',p)
end
function UI.draw(u,s,adopt)
    if not u.fontsReady then return end
    local I=u.I; local p=palette(u,s and s.theme or 'midnight'); local sx,sy=getScreenResolution()
    local width,height=math.min(1000,sx-24),math.min(720,sy-24)
    u.scale=math.min(1,height/720)
    local alpha=math.min(1,(os.clock()-u.openedAt)*6+0.08)
    styles(I,p,alpha)
    I.SetNextWindowSize(I.ImVec2(width,height),I.Cond.Always); I.SetNextWindowPos(I.ImVec2(sx/2,sy/2),I.Cond.Appearing,I.ImVec2(0.5,0.5))
    local flags=I.WindowFlags.NoTitleBar+I.WindowFlags.NoResize+I.WindowFlags.NoCollapse
    if I.Begin('Petarz##main',u.open,flags) then
        I.SetWindowFontScale(math.max(0.8,u.scale))
        I.BeginChild('navigation',I.ImVec2(165*u.scale,-1),true)
        title(I,u,'petarz'); muted(I,'Твой маленький мир',p); gap(I,24*u.scale)
        if s then
            for _,tab in ipairs(tabs) do
                if I.Selectable(tab[2]..'##'..tab[1],u.tab==tab[1],0,I.ImVec2(0,32*u.scale)) then
                    if u.tab=='games' and tab[1]~='games' then u.G.cancel(u.game) end
                    u.tab=tab[1]
                end
            end
            gap(I,16*u.scale)
            if button(I,s.settings.overlay and 'Убрать из угла' or 'Посадить в угол',-1,40*u.scale) then s.settings.overlay=not s.settings.overlay; u.save() end
            gap(I,5); muted(I,'Монеты питомца\n'..tostring(math.floor(s.coins)),p)
        else muted(I,'1. Выбери имя\n2. Познакомьтесь\n3. Растите вместе',p) end
        I.EndChild(); I.SameLine()
        I.BeginChild('content',I.ImVec2(0,-1),false)
        local w=I.GetContentRegionAvail().x
        I.BeginGroup()
        if s then
            title(I,u,s.name); muted(I,(s.sex=='girl' and 'Девочка' or 'Мальчик')..'   /   Уровень '..u.E.level(s),p)
        else title(I,u,'Добро пожаловать') end
        I.EndGroup(); I.SameLine(math.max(0,w-74))
        if button(I,'Закрыть',74,30) then u.open[0]=false; u.G.cancel(u.game); if s then u.save() end end
        if s then I.ProgressBar(u.E.progress(s),I.ImVec2(-1,4),'') end
        gap(I,8)
        -- Reserve a footer for local feedback; content scrolls on small displays.
        I.BeginChild('page',I.ImVec2(0,-58),false)
        if not s then creation(u,adopt)
        elseif u.tab=='home' then home(u,s,I.GetContentRegionAvail().x)
        elseif u.tab=='food' then food(u,s)
        elseif u.tab=='wardrobe' then wardrobe(u,s)
        elseif u.tab=='rooms' then rooms(u,s)
        elseif u.tab=='work' then work(u,s)
        elseif u.tab=='diary' then diary(u,s)
        elseif u.tab=='settings' then settings(u,s)
        elseif u.tab=='games' then
            title(I,u,'Время играть'); muted(I,'Небольшие игры для вас двоих. Награды имеют паузу и дневной предел.',p)
            if s.sleeping then wrap(I,'Питомец спит. Дайте ему отдохнуть или разбудите его дома.')
            elseif s.job then wrap(I,'Питомец занят делом. Забери результат во вкладке «Занятия», а потом играйте вместе.')
            else u.G.draw(I,u.game,os.clock(),function(id,score) return u.act('game',{id=id,score=score}) end,I.GetContentRegionAvail().x) end
        end
        I.EndChild(); gap(I,5)
        if os.clock()<u.toastUntil then muted(I,u.toast,p) elseif s then muted(I,'Всё сохраняется автоматически.   /petarz — меню',p) end
        I.EndChild()
    end
    I.End()
    I.GetStyle().Alpha=1
end
function UI.overlay(u,s)
    if not u.fontsReady or not s then return end
    local I=u.I; local sx,sy=getScreenResolution(); local p=palette(u,s.theme)
    styles(I,p,1)
    local scale=math.max(0.65,math.min(1,sy/900)); local width,height=270*scale,300*scale
    I.SetNextWindowPos(I.ImVec2(sx-width-18,sy-height-32),I.Cond.Always)
    I.SetNextWindowSize(I.ImVec2(width,height),I.Cond.Always)
    I.PushStyleColor(I.Col.WindowBg,I.ImVec4(0,0,0,0))
    local f=I.WindowFlags.NoTitleBar+I.WindowFlags.NoResize+I.WindowFlags.NoMove+I.WindowFlags.NoScrollbar+I.WindowFlags.NoInputs+I.WindowFlags.NoSavedSettings+I.WindowFlags.NoFocusOnAppearing
    if I.Begin('Petarz##companion',nil,f) then
        local pos=I.GetWindowPos(); local x,y=pos.x,pos.y
        pet(u,s,x+width*0.07,y+height*0.20,width*0.88,true)
        if not s.settings.quiet and u.bubble and os.clock()<u.bubbleUntil then
            local dl=I.GetWindowDrawList()
            dl:AddRectFilled(I.ImVec2(x+3,y+3),I.ImVec2(x+width-3,y+62*scale),u32(I,p.panel,0.95),12)
            I.SetCursorScreenPos(I.ImVec2(x+14,y+11)); I.SetWindowFontScale(scale)
            I.PushTextWrapPos(width-22); txt(I,u.bubble); I.PopTextWrapPos()
        end
    end
    I.End(); I.PopStyleColor()
end
return UI
