-- Run from repository root: luajit tests/games_spec.lua
-- A minimal immediate-mode UI driver exercises actual game state transitions.
-- Rendering itself still requires the Windows MoonLoader/mimgui client.
package.path = './moonloader/lib/?.lua;' .. package.path
local G = require 'petarz.games'
local checked, clicks = 0, {}
local function check(value, message)
    checked = checked + 1
    assert(value, message)
end
local function click(label) clicks[label] = true end
local ui = { Col = { Button = 1, ButtonHovered = 2, ButtonActive = 3 } }
for _, name in ipairs({
    'TextUnformatted', 'PushTextWrapPos', 'PopTextWrapPos', 'PushStyleColor',
    'PopStyleColor', 'Spacing', 'Separator', 'SameLine', 'Dummy'
}) do ui[name] = function() end end
ui.ImVec2 = function(x, y) return { x = x, y = y } end
ui.ImVec4 = function(...) return { ... } end
ui.GetColorU32Vec4 = function() return 0 end
ui.GetCursorScreenPos = function() return { x = 0, y = 0 } end
ui.GetWindowDrawList = function() return { AddRectFilled = function() end } end
ui.Button = function(label)
    local yes = clicks[label]
    clicks[label] = nil
    return yes or false
end

math.randomseed(7319)
local s, rewards = G.new(), {}
local function reward(id, score)
    check(score >= 0 and score <= 100 and score == math.floor(score), 'normalized score')
    rewards[#rewards + 1] = { id = id, score = score }
    return true, 'Тестовая награда'
end
local function draw(t) G.draw(ui, s, t, reward, 500) end

check(s.mode == 'menu' and s.active == nil, 'new session starts in menu')
click('Парочки##pet_game_memory'); draw(0)
check(s.active.id == 'memory', 'memory starts')
local locations, counts = {}, {}
for i, value in ipairs(s.active.deck) do
    locations[value] = locations[value] or {}
    locations[value][#locations[value] + 1] = i
    counts[value] = (counts[value] or 0) + 1
end
for value = 1, 6 do check(counts[value] == 2, 'each memory pair occurs twice') end
-- A mismatch stays visible briefly and cannot accept a third card.
local left, right = locations[1][1], locations[2][1]
click('?##pet_memory_' .. left); draw(1)
click('?##pet_memory_' .. right); draw(1.1)
local blocked = locations[3][1]
click('?##pet_memory_' .. blocked); draw(1.2)
check(#s.active.open == 2 and s.active.moves == 1, 'mismatch blocks additional choices')
draw(2.1)
check(#s.active.open == 0, 'mismatch closes after delay')
for value = 1, 6 do
    for _, i in ipairs(locations[value]) do click('?##pet_memory_' .. i); draw(value + 3) end
end
check(s.mode == 'result' and #rewards == 1 and rewards[1].id == 'memory', 'memory completes')
check(s.result.reward == 'Тестовая награда', 'callback feedback shown')
draw(15); check(#rewards == 1, 'memory reward is one-shot')
G.cancel(s)
click('Парочки##pet_game_memory'); draw(20)
draw(141)
check(s.mode == 'result' and #rewards == 2 and rewards[2].score == 0, 'memory timeout yields zero when no pairs')

G.cancel(s)
click('Поймай ритм##pet_game_rhythm'); draw(150)
for round = 1, 5 do
    local a = s.active
    local t = a.roundAt + (2.35 - round * 0.13) * 0.5
    click('Поймать##pet_rhythm_hit'); draw(t)
    local total = a.total
    click('Поймать##pet_rhythm_hit'); draw(t + 0.2)
    check(a.total == total, 'rhythm prevents repeated scoring during feedback')
    -- Button is not submitted during feedback, so discard the simulated click.
    clicks = {}
    draw(t + 0.9)
end
check(s.mode == 'result' and #rewards == 3 and s.result.score == 100, 'five centered rhythm hits score 100')
check(rewards[3].id == 'rhythm', 'rhythm callback id')
draw(170); check(#rewards == 3, 'rhythm reward is one-shot')

G.cancel(s)
click('Повтори узор##pet_game_pattern'); draw(180)
local labels = { 'Лес', 'Небо', 'Солнце', 'Ягода' }
local now = 180
local guard = 0
while s.mode == 'play' do
    guard = guard + 1
    assert(guard < 80, 'pattern state machine stalled')
    local a = s.active
    if a.phase == 'feedback' then
        now = a.phaseAt + 0.01; draw(now)
    elseif a.phase == 'show' then
        now = a.phaseAt + (a.round + 1) * 0.65 + 0.01; draw(now)
    else
        local i = a.sequence[a.input]
        click(labels[i] .. '##pet_pattern_' .. i)
        now = now + 0.01; draw(now)
    end
end
check(s.mode == 'result' and #rewards == 4 and s.result.score == 100, 'all five patterns complete')
check(rewards[4].id == 'pattern', 'pattern callback id')
draw(now + 1); check(#rewards == 4, 'pattern reward is one-shot')

G.cancel(s)
click('Повтори узор##pet_game_pattern'); draw(now + 2)
for attempt = 1, 3 do
    local a = s.active
    if a.phase == 'feedback' then draw(a.phaseAt + 0.01) end
    draw(a.phaseAt + (a.round + 1) * 0.65 + 0.01)
    local wrong = a.sequence[a.input] % 4 + 1
    click(labels[wrong] .. '##pet_pattern_' .. wrong)
    draw(a.phaseAt + (a.round + 1) * 0.65 + 0.02)
end
check(s.mode == 'result' and #rewards == 5 and s.result.score == 0, 'three pattern errors finish at zero')
G.cancel(s)
click('Повтори узор##pet_game_pattern'); draw(now + 20)
G.cancel(s)
check(s.mode == 'menu' and s.active == nil and #rewards == 5, 'abandonment issues no reward')

-- The callback may reject a reward or fail; completion must stay one-shot.
local function finishTimeout(callback)
    click('Парочки##pet_game_memory')
    G.draw(ui, s, 500, callback, 500)
    G.draw(ui, s, 621, callback, 500)
end
finishTimeout(function() return false, 'Дневной лимит' end)
check(s.result.reward == 'Дневной лимит', 'engine rejection message is retained')
G.cancel(s)
finishTimeout(function() error('simulated engine failure') end)
check(s.mode == 'result' and type(s.result.reward) == 'string', 'callback errors do not crash UI')
print('games_spec: ' .. checked .. ' checks passed')
