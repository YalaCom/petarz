-- Run from the repository root with LuaJIT 2.1: luajit tests/run.lua
for _,path in ipairs({'tests/engine_spec.lua','tests/store_spec.lua','tests/games_spec.lua','tests/ui_spec.lua','tests/adapter_spec.lua'}) do
    print('\n'..path)
    dofile(path)
end
print('\nAll automated checks passed. GTA/Direct3D validation is a separate manual step.')
