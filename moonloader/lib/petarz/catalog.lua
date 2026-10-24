-- UTF-8. Prices and rewards are fictional pet coins, never Arizona currency.
local C = {}
C.foods = {
    {id='apple', name='Сочное яблоко', price=8, level=1, hunger=16, joy=1, health=0, description='Лёгкий перекус между делами.'},
    {id='porridge', name='Тёплая каша', price=14, level=1, hunger=32, joy=2, health=1, description='Сытная домашняя еда.'},
    {id='treat', name='Ягодное печенье', price=18, level=2, hunger=12, joy=12, health=0, description='Небольшое лакомство для хорошего настроения.'},
    {id='soup', name='Овощной суп', price=24, level=4, hunger=42, joy=4, health=3, description='Забота в каждой ложке.'}
}
C.rooms = {
    {id='bedroom', name='Уютная спальня', price=0, level=1, description='Тихое место, где восстанавливаются силы.'},
    {id='kitchen', name='Солнечная кухня', price=160, level=2, description='Домашний уголок для маленького гурмана.'},
    {id='garden', name='Лунный сад', price=320, level=4, description='Свежий воздух и вечерние огоньки.'},
    {id='studio', name='Творческая студия', price=560, level=6, description='Место для мечтаний и новых увлечений.'}
}
C.clothes = {
    {id='none', name='Пушистый наряд', price=0, level=1, description='Естественная красота.'},
    {id='scarf', name='Уютный шарфик', price=120, level=2, description='Мягкий шарфик для маленького друга.'},
    {id='raincoat', name='Жёлтый дождевик', price=260, level=4, description='Для приключений в любую погоду.'}
}
C.jobs = {
    {id='flowers', name='Полить цветы', level=1, duration=600, reward=16, description='Десять минут спокойной заботы о саде.'},
    {id='letters', name='Разобрать открытки', level=3, duration=1200, reward=28, description='Двадцать минут: аккуратность и внимание.'},
    {id='studio', name='Помочь в мастерской', level=5, duration=1800, reward=40, description='Полчаса творчества и полезных дел.'}
}
C.themes = {
    {id='midnight', name='Полночь'},
    {id='cream', name='Персиковый рассвет'},
    {id='forest', name='Тихий лес'}
}
C.games = {
    {id='memory', name='Найди пару'},
    {id='pattern', name='Повтори узор'},
    {id='rhythm', name='Точный момент'}
}
function C.find(kind, id)
    for _, item in ipairs(C[kind] or {}) do
        if item.id == id then return item end
    end
end
return C
