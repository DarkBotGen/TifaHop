-- TifaHop: report startup failures even if the panel cannot be created.
local ok, err = xpcall(function()
    local source = game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/TifaHop/main/client.luau?t=" .. tostring(os.time()))
    getgenv().vh_embedded_source = source
    local run, compileError = loadstring(source)
    assert(run, compileError)
    run()
end, debug.traceback)
if not ok then
    warn('[TifaHop] ' .. tostring(err))
    pcall(function() game:GetService('StarterGui'):SetCore('SendNotification', {Title='TifaHop startup error', Text=tostring(err):sub(1,180), Duration=15}) end)
end
