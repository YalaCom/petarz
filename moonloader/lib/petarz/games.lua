-- Petarz: three local mini-games. UTF-8 source, Lua 5.1 / LuaJIT.
-- API: session = G.new(); G.draw(imgui, session, monotonicSeconds,
--   function(id, score) return accepted, message end, contentWidth).
-- onReward fires ONCE per finished run; score is an integer from 0 to 100.
-- IDs: memory, rhythm, pattern. The engine owns reward/cooldown validation.
-- G.cancel(session) abandons a run without issuing a reward. Call on menu close.
local G = {}

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end
local function text(ui, value) ui.TextUnformatted(tostring(value)) end
local function wrapped(ui, value)
    ui.PushTextWrapPos(0)
    text(ui, value)
    ui.PopTextWrapPos()
end
local function button(ui, label, width, height)
    return ui.Button(label, ui.ImVec2(width or 0, height or 0))
end
local function color(ui, r, g, b, a)
    return ui.ImVec4(r, g, b, a or 1)
end
local function tile(ui, label, w, h, tint, lit)
    local scale = lit and 1.15 or 0.58
    ui.PushStyleColor(ui.Col.Button, color(ui,
        clamp(tint[1] * scale, 0, 1), clamp(tint[2] * scale, 0, 1), clamp(tint[3] * scale, 0, 1)))
    ui.PushStyleColor(ui.Col.ButtonHovered, color(ui, tint[1], tint[2], tint[3]))
    ui.PushStyleColor(ui.Col.ButtonActive, color(ui,
        clamp(tint[1] * 1.15, 0, 1), clamp(tint[2] * 1.15, 0, 1), clamp(tint[3] * 1.15, 0, 1)))
    local clicked = button(ui, label, w, h)
    ui.PopStyleColor(3)
    return clicked
end

local names = { memory = 'Парочки', rhythm = 'Поймай ритм', pattern = 'Повтори узор' }

function G.new()
    return { mode = 'menu', active = nil, result = nil }
end

function G.cancel(s)
    s.mode, s.active, s.result = 'menu', nil, nil
end

local function finish(s, score, detail, onReward)
    if s.mode ~= 'play' or not s.active then return end
    local id = s.active.id
    score = clamp(math.floor(score + 0.5), 0, 100)
    -- Set result before invoking external code: a callback cannot double-award.
    s.mode = 'result'
    s.result = { id = id, score = score, detail = detail }
    if type(onReward) == 'function' then
        local called, accepted, message = pcall(onReward, id, score)
        if not called then
            s.result.reward = 'Результат сохранён в этой игре. Начисление недоступно.'
        elseif type(message) == 'string' then
            s.result.reward = message
        elseif accepted == false then
            s.result.reward = 'Сегодня награда пока недоступна. Можно играть для удовольствия.'
        else
            s.result.reward = 'Результат передан питомцу.'
        end
    end
end

local function start(s, id, now)
    s.mode, s.result = 'play', nil
    local a = { id = id, started = now }
    if id == 'memory' then
        a.deck, a.found, a.open, a.moves, a.pairs = {}, {}, {}, 0, 0
        for i = 1, 12 do a.deck[i] = math.ceil(i / 2) end
        for i = #a.deck, 2, -1 do
            local j = math.random(i)
            a.deck[i], a.deck[j] = a.deck[j], a.deck[i]
        end
    elseif id == 'rhythm' then
        a.round, a.total, a.roundAt, a.lastScore = 1, 0, now, nil
    else
        a.sequence = {}
        for i = 1, 6 do a.sequence[i] = math.random(4) end
        a.round, a.lives, a.input = 1, 3, 1
        a.phase, a.phaseAt = 'show', now + 0.65
    end
    s.active = a
end

local memoryLabels = { 'Мяч', 'Бант', 'Рыба', 'Луна', 'Кекс', 'Ключ' }

local function drawMemory(ui, s, now, onReward, width)
    local a = s.active
    local elapsed = math.max(0, now - a.started)
    if a.hideAt and now >= a.hideAt then
        a.open, a.hideAt = {}, nil
    end
    if elapsed >= 120 then
        finish(s, a.pairs / 6 * 50,
            'Время вышло. Найдено пар: ' .. a.pairs .. ' из 6.', onReward)
        return
    end
    wrapped(ui, 'Открой две одинаковые карточки. Всего шесть пар и две минуты. Запоминай расположение, а не спеши.')
    text(ui, ('Пары: %d / 6     Ходы: %d     Осталось: %d с'):format(a.pairs, a.moves, math.ceil(120 - elapsed)))
    ui.Spacing()
    local gap, cell = 8, math.max(70, math.floor((width - 24) / 4))
    local function isOpen(i)
        return a.found[i] or a.open[1] == i or a.open[2] == i
    end
    for row = 0, 2 do
        for col = 1, 4 do
            local i = row * 4 + col
            local face = isOpen(i) and memoryLabels[a.deck[i]] or '?'
            local tint = a.found[i] and { 0.28, 0.66, 0.52 } or { 0.38, 0.46, 0.68 }
            local clicked = tile(ui, face .. '##pet_memory_' .. i, cell, 56, tint, isOpen(i))
            if clicked and not a.found[i] and not isOpen(i) and not a.hideAt and #a.open < 2 then
                a.open[#a.open + 1] = i
                if #a.open == 2 then
                    a.moves = a.moves + 1
                    if a.deck[a.open[1]] == a.deck[a.open[2]] then
                        a.found[a.open[1]], a.found[a.open[2]] = true, true
                        a.pairs, a.open = a.pairs + 1, {}
                    else
                        a.hideAt = now + 0.85
                    end
                end
            end
            if col < 4 then ui.SameLine(0, gap) end
        end
    end
    if a.pairs == 6 then
        local score = clamp(100 - math.max(0, a.moves - 6) * 4 - math.max(0, elapsed - 18) * 0.35, 20, 100)
        finish(s, score, 'Все пары найдены. Отличная тренировка памяти!', onReward)
    end
end

local function drawRhythm(ui, s, now, onReward, width)
    local a = s.active
    wrapped(ui, 'Нажимай «Поймать», когда светлая метка проходит середину полосы. Пять попыток; скорость постепенно растёт.')
    text(ui, ('Попытка: %d / 5     Набрано: %d'):format(math.min(a.round, 5), a.total))
    ui.Spacing()
    if a.nextAt and now >= a.nextAt then
        if a.round >= 5 then
            finish(s, a.total / 5, 'Пять попыток завершены. Питомец поймал твой ритм.', onReward)
            return
        end
        a.round, a.roundAt, a.nextAt = a.round + 1, now, nil
    end
    local period = 2.35 - a.round * 0.13
    local phase = ((now - a.roundAt) / period) % 2
    local position = phase <= 1 and phase or 2 - phase
    if a.nextAt then position = a.lastPosition end
    local p = ui.GetCursorScreenPos()
    local h = 44
    local draw = ui.GetWindowDrawList()
    local function rgba(r, g, b, alpha)
        return ui.GetColorU32Vec4(color(ui, r, g, b, alpha))
    end
    draw:AddRectFilled(p, ui.ImVec2(p.x + width, p.y + h), rgba(0.12, 0.16, 0.23, 1), 8)
    draw:AddRectFilled(ui.ImVec2(p.x + width * 0.42, p.y + 4),
        ui.ImVec2(p.x + width * 0.58, p.y + h - 4), rgba(0.25, 0.64, 0.47, 1), 5)
    draw:AddRectFilled(ui.ImVec2(p.x + position * (width - 8), p.y + 2),
        ui.ImVec2(p.x + position * (width - 8) + 8, p.y + h - 2), rgba(0.96, 0.89, 0.67, 1), 3)
    ui.Dummy(ui.ImVec2(width, h))
    ui.Spacing()
    if a.nextAt then
        text(ui, 'Точность: ' .. a.lastScore .. ' / 100')
        text(ui, 'Следующая попытка через мгновение...')
    elseif button(ui, 'Поймать##pet_rhythm_hit', width, 44) then
        local score = math.floor(clamp(1 - math.abs(position - 0.5) * 2, 0, 1) * 100 + 0.5)
        a.lastPosition, a.lastScore = position, score
        a.total, a.nextAt = a.total + score, now + 0.8
    end
    wrapped(ui, 'Зелёная область помогает прицелиться. Итог — средняя точность пяти нажатий.')
end

local patternLabels = { 'Лес', 'Небо', 'Солнце', 'Ягода' }
local patternColors = {
    { 0.26, 0.65, 0.45 }, { 0.28, 0.52, 0.79 },
    { 0.78, 0.60, 0.24 }, { 0.73, 0.34, 0.49 }
}

local function drawPattern(ui, s, now, onReward, width)
    local a = s.active
    local length = a.round + 1
    if a.phase == 'feedback' and now >= a.phaseAt then
        a.phase, a.phaseAt, a.input = 'show', now + 0.55, 1
    end
    local highlighted = 0
    if a.phase == 'show' then
        local elapsed = now - a.phaseAt
        if elapsed >= length * 0.65 then
            a.phase, a.input = 'input', 1
        elseif elapsed >= 0 then
            local index = math.floor(elapsed / 0.65) + 1
            if elapsed % 0.65 < 0.44 then highlighted = a.sequence[index] end
        end
    end
    wrapped(ui, 'Запомни порядок подсветки, затем повтори его нажатием на карточки. Пять уровней, три попытки на ошибку.')
    text(ui, ('Уровень: %d / 5     Попытки: %d     Длина узора: %d'):format(a.round, a.lives, length))
    if a.phase == 'show' then
        text(ui, 'Смотри и запоминай...')
    elseif a.phase == 'input' then
        text(ui, ('Твой ход: %d / %d'):format(a.input, length))
    else
        text(ui, a.feedback or 'Готовимся...')
    end
    ui.Spacing()
    local cell = math.floor((width - 8) / 2)
    local pressed
    for i = 1, 4 do
        if tile(ui, patternLabels[i] .. '##pet_pattern_' .. i, cell, 60,
            patternColors[i], highlighted == i) and a.phase == 'input' then
            pressed = i
        end
        if i % 2 == 1 then ui.SameLine(0, 8) end
    end
    if not pressed then return end
    if pressed ~= a.sequence[a.input] then
        a.lives = a.lives - 1
        if a.lives <= 0 then
            finish(s, (a.round - 1) * 20, 'Попытки закончились. Можно попробовать снова.', onReward)
        else
            a.phase, a.phaseAt, a.feedback = 'feedback', now + 1,
                'Ничего страшного. Ещё раз покажу этот узор.'
        end
    else
        a.input = a.input + 1
        if a.input > length then
            if a.round >= 5 then
                finish(s, 100, 'Все пять узоров повторены без подсказок!', onReward)
            else
                a.round, a.phase, a.phaseAt = a.round + 1, 'feedback', now + 0.9
                a.feedback = 'Верно! Добавляем ещё один шаг.'
            end
        end
    end
end

function G.draw(ui, s, now, onReward, availableWidth)
    now = tonumber(now) or os.clock()
    local width = math.max(300, tonumber(availableWidth) or 500)
    if s.mode == 'menu' then
        text(ui, 'Маленькие игры, большое доверие')
        wrapped(ui, 'Играй вместе с питомцем. Награды ограничены временем и дневным запасом, а повторные попытки остаются бесплатными.')
        ui.Spacing()
        if button(ui, 'Парочки##pet_game_memory', width, 40) then start(s, 'memory', now) end
        wrapped(ui, 'Шесть пар, две минуты. Внимание и память.')
        ui.Spacing()
        if button(ui, 'Поймай ритм##pet_game_rhythm', width, 40) then start(s, 'rhythm', now) end
        wrapped(ui, 'Пять точных нажатий. Реакция без спешки.')
        ui.Spacing()
        if button(ui, 'Повтори узор##pet_game_pattern', width, 40) then start(s, 'pattern', now) end
        wrapped(ui, 'Запоминай цветные последовательности от двух до шести шагов.')
    elseif s.mode == 'result' then
        text(ui, names[s.result.id] or 'Игра')
        text(ui, ('Результат: %d / 100'):format(s.result.score))
        wrapped(ui, s.result.detail)
        if s.result.reward then wrapped(ui, s.result.reward) end
        ui.Spacing()
        if button(ui, 'Играть ещё##pet_game_again', width, 40) then start(s, s.result.id, now) end
        if button(ui, 'К списку игр##pet_game_menu', width, 36) then G.cancel(s) end
    elseif s.active then
        text(ui, names[s.active.id] or 'Игра')
        ui.Separator()
        if s.active.id == 'memory' then drawMemory(ui, s, now, onReward, width)
        elseif s.active.id == 'rhythm' then drawRhythm(ui, s, now, onReward, width)
        else drawPattern(ui, s, now, onReward, width) end
        if s.mode == 'play' then
            ui.Spacing()
            if button(ui, 'Выйти из игры##pet_game_abandon', width, 30) then G.cancel(s) end
            wrapped(ui, 'При выходе незавершённый результат не засчитывается.')
        end
    else
        G.cancel(s)
    end
end

return G
