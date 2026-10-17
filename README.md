# TifaHop

Bee Swarm Simulator Vicious Bee searcher/main client with a LAN relay.
Discord: discord.gg/tifahop

```lua
getgenv().delay = "0" -- Seconds before server hopping
getgenv().minlvl = "1" -- Minimum Vicious level (1-12)
getgenv().maxlvl = "12" -- Maximum Vicious level (1-12)
getgenv().onlygifted = false
getgenv().mainwait = true
getgenv().hook = "" -- Optional Discord webhook
getgenv().uid = "" -- Optional Discord user ID
loadstring(game:HttpGet("https://raw.githubusercontent.com/DarkBotGen/TifaHop/main/main.lua"))()
```

The launcher above reuses the private connection saved in the executor
workspace. For initial setup, provide `getgenv().relay` (LAN URL),
`getgenv().relaytoken` (your relay token), `getgenv().room`, and
`getgenv().role` (`main` or `searcher`). Private ready-to-paste launchers can
provide these automatically; do not commit them to this repository.
The client saves the connection per Roblox account when writefile is available.
Without executor file support, supply connection settings on each execution.

Run `python relay.py` on the LAN host. This generates a private relay-token.txt.
Allow TCP 8787 from your local network and keep the host running. All clients
must reach the host; a GitHub loader does not replace the relay.

Settings beside Info saves shared room settings to the relay and account
workspace config. Running clients poll changes every three seconds.
Body labels and buttons use definitions copied from the user-supplied Atlas
source. The panel scales down for small windows and caps at 360x394 by default
on desktop; manual corner resizing remains available. Right Shift toggles it.

Searchers report live Vicious monsters and attempt dormant-thorn activation.
Mains join reported servers and follow targets; existing bees supply damage.
Observed defeats are not verified kill credit. Stingers count positive
inventory changes. Full Atlas gate access, dodge, and token systems are not
included. Live gameplay and executor-specific behavior remain unverified.

Requires executor HTTP requests and queue_on_teleport for automatic continuation.
No Roblox credentials are used. Settings/token files belong on your own trusted
LAN; the relay is not an internet hosting service.
