local process = require("@std/process")
local thread = require("@std/thread")
local keys = require("./keys")
local platform = require("./platform")

type WindowInfo = {
    id: string,
    name: string?,
    class_name: string?,
    last_access: number,
}

local windows = {
    tracked = {} :: { [string]: WindowInfo },
    order = {} :: { string },
    last_active_id = "" :: string,
}

function windows.active_id(): string?
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        local result = process.shell("kdotool getactivewindow")
        if result.ok then
            local window_id = string.match(result.out, "({[%w%-]+})")
            return window_id
        end
    end
    return nil
end

function windows.switch(direction: "Left" | "Right", count: number?)
    count = count or 1
    if platform.os == "Linux" then
        keys.send("Alt" .. string.rep("+Tab", count))
    else
        keys.send("Alt+Shift" .. string.rep("+Tab", count))
    end
end

function windows.info(pattern: string): WindowInfo?
    -- first check tracked
    for id, info in windows.tracked do
        if 
            info.id == pattern
            or info.name and info.name == pattern
            or info.class_name and info.class_name == pattern
            or info.name and string.match(info.name, pattern)
            or info.class_name and string.match(info.class_name, pattern)
        then
            return info
        end
    end

    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        -- local result = {}
        local window_name: string?
        local name_result = process.shell(`kdotool getwindowname {pattern}`)
        if name_result.ok then
            window_name = name_result:unwrap():gsub("\n", "")
        end

        local class_name: string?
        local class_name_result = process.shell(`kdotool getwindowclassname {pattern}`)
        if class_name_result.ok then
            class_name = class_name_result:unwrap():gsub("\n", "")
        end

        if window_name and class_name then
            local result: WindowInfo =  {
                id = pattern,
                name = window_name,
                class_name = class_name,
                last_access = os.clock()
            }
            windows.tracked[pattern] = result
            return result
        end
    end

    return nil
end

function windows.last(): WindowInfo?
    local window_id = windows.last_active_id
    for _, active in windows.tracked do
        if active.id == window_id then
            return active
        end
    end
    return nil
end

function windows.activate(window: WindowInfo): boolean
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        local result = process.shell(`kdotool windowactivate {window.id}`)
        return result.ok
    end
    return false
end

function windows.minimize(window: WindowInfo)
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        local result = process.shell(`kdotool windowminimize {window.id}`)
        return result.ok
    end
    return false
end

function windows.maximize_active()
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        keys.send("Meta+PageUp")
    end
end

function windows.move_to(window: WindowInfo, position: vector): boolean
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        local command = "kdtool windowmove " .. window.id

        local x = position.x // 1
        local y = position.y // 1

        if x <= 1 or y <= 1 then
            x *= 100
            y *= 100

            -- kdotool's rust code can handle percentages and strips the trailing %
            command ..= ` {x}% {y}%`
        else
            command ..= ` {x} {y}`
        end

        local result = process.shell(command)
        if result.ok then
            return true
        else
            warn(`can't move window {window.name} (id: {window.id}) due to err: {result.err}`)
        end
    end

    return false
end

function windows.move_relative(window: WindowInfo, delta: vector)
    local x = delta.x // 1
    local y = delta.y // 1

    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        -- local result = process.shell(`kdotool windowmove --relative {window.id} {x} {y}`)
        -- if result.ok then
        --     return true
        -- else
        --     warn(`can't move window {window.name} (id: {window.id}) due to err: {result.err}`)
        -- end
        process.spawn {
            program = `kdotool windowmove --relative {window.id} {x} {y}`,
            shell = "sh",
        }
    end

    return false
end

function windows.resize(window: WindowInfo, size: vector)
    if platform.os == "Linux" and platform.desktop_environment == "KDE" then
        local result = process.shell(`kdotool windowsize {window.id} {size.x} {size.y}`)
        if result.ok then
            return true
        else
            warn(`can't resize window {window.name} (id: {window.id}) due to err: {result.err}`)
        end
    end

    return false
end

function windows.snap(window: WindowInfo, side: "Left" | "Right")
    if platform.os == "Linux" then
        keys.send(`Meta+{side}`)
    end
end

function windows.listener(): thread
    local handle = thread.spawn {
        path = "./listen.luau"
    }
    return coroutine.create(function()
        while true do
            coroutine.yield()
            local resp = handle:read() :: { event: string, data: unknown }?
            if not resp then
                continue
            end
            if resp.event == "WindowFound" then
                local window_info = resp.data :: WindowInfo
                windows.tracked[window_info.id] = window_info
            elseif resp.event == "NewActive" then
                local window_id = resp.data :: string
                windows.last_active_id = window_id
            end
        end
    end)
end

return windows