local process = require("@std/process")
local thread = require("@std/thread")
local platform = require("./platform")
local events = require("./events")
local windows = require("./windows")

platform:check_dependencies()

local child = process.spawn {
    program = "sudo libinput debug-events --show-keycodes",
    shell = "sh"
}

local windows_listener = windows.listener()

local current_gesture = {
    start = nil :: number?,
    fingers = 0,
    frames = {}
}

local ctrl_down = false
local snapped_for_gesture = false

local window_switch = {
    count = 0,
    last_tick = math.huge,
}

while thread.sleep(5) do
    coroutine.resume(windows_listener)
    local line = child.stdout:read_to("\n", false, 0.05)
    if not line then
        local err = child.stderr:read(nil, 0.05)
        if err then
            error(err)
        end
        continue
    end

    local event = events.parse(line)
    if not event then
        continue
    end
    if event.is == "GESTURE_SWIPE_BEGIN" then
        current_gesture.start = os.clock()
        current_gesture.fingers = event.fingers
        snapped_for_gesture = false
    elseif event.is == "GESTURE_SWIPE_UPDATE" then
        table.insert(current_gesture.frames, event.delta)

        local recent_delta: vector = current_gesture.frames[1]
        for _, frame in current_gesture.frames do
            recent_delta += frame
        end
        
        local top = windows.last()
        if top and event.fingers == 3 then
            if ctrl_down then
                windows.move_relative(top, event.delta)
            end
            if event.frame > 12 and not snapped_for_gesture then
                if math.abs(recent_delta.x) > math.abs(recent_delta.y) then
                    if recent_delta.x < -50 then
                        windows.snap(top, "Left")
                    elseif recent_delta.x > 50 then
                        windows.snap(top, "Right")
                    end
                else
                    if recent_delta.y < -50 then
                        windows.maximize_active()
                    elseif recent_delta.y > 100 then
                        windows.minimize(top)
                    end
                end

                snapped_for_gesture = true
            end
        elseif top and event.fingers == 4 then
            if math.abs(recent_delta.x) > math.abs(recent_delta.y) then
                if window_switch.count == 0 then
                    window_switch.last_tick = os.clock()
                end
                if os.clock() - window_switch.last_tick > 0.1 then
                    window_switch.count += 1
                    if recent_delta.x < -40 then
                        windows.switch("Left", window_switch.count)
                    elseif recent_delta.y > 40 then
                        windows.switch("Right", window_switch.count)
                    end
                    window_switch.last_tick = os.clock()
                end
            end
        end
    elseif event.is == "GESTURE_SWIPE_END" then
        current_gesture.fingers = 0
        table.clear(current_gesture.frames)
    elseif event.is == "KEY" and event.code == "LEFTCTRL" then
        ctrl_down = event.state == "Down"
    end
end
