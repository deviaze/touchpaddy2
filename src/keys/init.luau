local process = require("@std/process")

local linux_keys = require("@self/linux")
local platform = require("./platform")

local keys = {}

function keys.send(codes: string): boolean
    if platform.os == "Linux" then
        local keys_ups_and_downs = linux_keys.parse(codes)
        local result = process.shell(`ydotool key {keys_ups_and_downs}`)
        if result.ok then
            return true
        else
            warn(`can't send keystrokes due to err: {result.err}`)
        end
    end
    return false
end

return keys
