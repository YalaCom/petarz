-- LuaJIT UI flow tests with a narrow mimgui driver. Real Direct3D remains manual.
package.path='./moonloader/lib/?.lua;'..package.path
local ffi=require 'ffi'
local UI=require 'petarz.ui'
local E=require 'petarz.engine'
local C=require 'petarz.catalog'
local G=require 'petarz.games'
local n,clicks,images,texts,rects=0,{},{},{},{}
local function check(ok,why) n=n+1; assert(ok,why) end
local function enum()
    local nextValue=0
    return setmetatable({},{__index=function(t,k) nextValue=nextValue+1; rawset(t,k,nextValue); return nextValue end})
end
local I={Col=enum(),Cond=enum(),WindowFlags=enum()}
I.new={bool=function(v) return {[0]=v} end,char=setmetatable({},{__index=function(_,len) return function() return ffi.new('char[?]',len) end end})}
I.ImVec2=function(x,y) return {x=x,y=y} end
I.ImVec4=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end
local style={Colors={}}
I.GetStyle=function() return style end
local io={DeltaTime=1/60,Fonts={}}
io.Fonts.GetGlyphRangesCyrillic=function() return {} end
io.Fonts.AddFontFromFileTTF=function(_,path,size,config,ranges) check(ranges~=nil,'font glyph ranges retained'); return {size=size} end
I.GetIO=function() return io end
I.ImFontConfig=function() return {} end
I.ImVector_ImWchar=function() return {[0]={Data={}}} end
I.ImFontGlyphRangesBuilder=function()
    return {AddRanges=function() end,AddText=function(_,s) check(s:find('—',1,true) and s:find('•',1,true),'punctuation ranges included') end,BuildRanges=function() end}
end
I.CreateTextureFromFile=function(path) return {path=path} end
I.GetContentRegionAvail=function() return {x=650,y=500} end
local cursor={x=20,y=20}
I.GetCursorScreenPos=function() return cursor end
I.SetCursorScreenPos=function(p) cursor=p end
I.GetCursorPosX=function() return cursor.x end
I.GetWindowPos=function() return {x=0,y=0} end
I.GetColorU32Vec4=function(v) return v end
local dl={
    AddImage=function(_,texture,p0,p1,uv0,uv1) images[#images+1]={texture=texture,uv0=uv0,uv1=uv1} end,
    AddRectFilled=function(_,p0,p1,col) rects[#rects+1]=col end,
    AddCircleFilled=function() end,AddLine=function() end,AddText=function() end
}
I.GetWindowDrawList=function() return dl end
I.TextUnformatted=function(s) texts[#texts+1]=s end
I.Button=function(label) local v=clicks[label]; clicks[label]=nil; return v==true end
I.Selectable=I.Button
I.Checkbox=function() return false end
I.Begin=function() return true end
I.BeginChild=function() return true end
for _,method in ipairs({'End','EndChild','SetNextWindowSize','SetNextWindowPos','SetWindowFontScale','PushFont','PopFont','PushStyleColor','PopStyleColor','PushTextWrapPos','PopTextWrapPos','Dummy','SameLine','ProgressBar','BeginGroup','EndGroup','Separator','SetNextItemWidth','InputText','PushIDStr','PopID','Spacing'}) do I[method]=function() end end
local screenW,screenH=1920,1080
getScreenResolution=function() return screenW,screenH end
local s=E.new(os.time(),'Персик','boy')
local saved,actions,adoptions=0,0,0
local u
local function save() saved=saved+1; return true end
local function act(a,arg) actions=actions+1; return E.act(s,a,arg,os.time()) end
u=UI.new(I,E,C,G,'resources/',act,save)
UI.initialize(u)
check(u.fontsReady and u.texture~=nil,'font and texture initialization')
UI.toggle(u); check(u.open[0],'open menu')
local function adopt(name,sex) adoptions=adoptions+1; check(name=='Лисёнок' and sex=='girl','adoption preserves Russian identity') end
UI.draw(u,nil,adopt)
ffi.copy(u.name,'Лисёнок'); u.gender='girl'; clicks['Начать дружбу']=true
UI.draw(u,nil,adopt); check(adoptions==1,'valid adoption accepted')
ffi.fill(u.name,65); ffi.copy(u.name,'---'); clicks['Начать дружбу']=true
UI.draw(u,nil,adopt); check(adoptions==1,'invalid adoption rejected')
for _,tab in ipairs({'home','food','wardrobe','rooms','games','work','diary','settings'}) do
    u.tab=tab; UI.draw(u,s,adopt)
    check(style.Alpha==1,'style alpha restored after '..tab)
end
local outfitCells={none=0,scarf=3,raincoat=4}
u.tab='home'
for outfit,cell in pairs(outfitCells) do
    s.outfit=outfit; UI.draw(u,s,adopt)
    local im=images[#images]
    check(im.uv0.x==cell%3/3 and im.uv0.y==math.floor(cell/3)/2,'outfit atlas coordinates '..outfit)
end
s.outfit='scarf'; s.sleeping=true; UI.draw(u,s,adopt)
check(images[#images].uv0.x==2/3 and images[#images].uv0.y==0,'sleep uses painted sleeping frame')
check(images[#images].texture.path:match('pet_scarf.png$') or images[#images].texture.path:match('pet_raincoat.png$'),'sleep keeps equipped outfit texture')
s.sleeping=false; s.stats.hunger=10; UI.draw(u,s,adopt)
check(images[#images].uv0.x==1/3,'need selects emotional frame')
check(images[#images].texture.path:match('pet_scarf.png$'),'sad mood keeps equipped scarf')
s.stats.hunger=80
-- Every room has its own scene color, independently of UI theme.
local colors={}
for _,room in ipairs(C.rooms) do s.room=room.id; rects={}; UI.draw(u,s,adopt); colors[room.id]=rects[1] end
check(colors.bedroom~=colors.garden and colors.kitchen~=colors.studio,'room scenes differ')
clicks['Погладить']=true; UI.draw(u,s,adopt); check(actions==1,'care click reaches engine')
u.tab='settings'; clicks['Сохранить сейчас']=true; UI.draw(u,s,adopt); check(saved==1 and u.toast=='Прогресс сохранён.','save reports confirmed success')
u.save=function() UI.notify(u,'Ошибка диска'); return false end
clicks['Сохранить сейчас']=true; UI.draw(u,s,adopt); check(u.toast=='Ошибка диска','save error not replaced with false success')
u.save=save; u.tab='games'; u.game.mode='play'; u.game.active={id='memory'}
clicks['Дом##home']=true; UI.draw(u,s,adopt); check(u.tab=='home' and u.game.mode=='menu','leaving games cancels run')
u.bubble='Животик урчит. Можно поесть?'; u.bubbleUntil=os.clock()+10
UI.overlay(u,s); check(images[#images]~=nil,'overlay renders painted pet')
u.tab='home'; screenW,screenH=800,600; UI.draw(u,s,adopt)
check(style.Alpha==1,'small display draws without leaking style')
clicks['Закрыть']=true; UI.draw(u,s,adopt); check(not u.open[0] and saved==2,'close button saves and releases menu')
print('ui_spec: '..n..' checks passed (UI driver, not Direct3D).')
