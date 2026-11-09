local cmd = require("cmd")
local json = require("json")
local function quote(value)
    return "'" .. value:gsub("'", "'\"'\"'") .. "'"
end
function PLUGIN:MiseEnv(ctx)
    if os.getenv("NUSAGE_GRAPH_ACTIVE") == "1" then return {} end
    local root = ctx.config_root
    local result = json.decode(cmd.exec("NUSAGE_GRAPH_ACTIVE=1 mise --cd " .. quote(root) .. " run --force --no-deps --raw //graph:assemble " .. quote(root)))
    if result.changed then error("project graph changed; run the command again") end
    return {env = {NUSAGE_GRAPH_NU = result.nu}, cacheable = true, watch_files = result.watch_files}
end
