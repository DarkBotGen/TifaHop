-- TifaHop: public loader. Private LAN connection is saved per account in workspace.
local source = game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/TifaHop/main/client.luau")
getgenv().vh_embedded_source = source
loadstring(source)()
