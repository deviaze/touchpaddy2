local format = require("@std/io/format")
local str = require("@std/str")

export type Event = {
    is: "POINTER_MOTION",
    delta_p: vector,
    delta_r: vector,
} | {
    is: "GESTURE_HOLD_BEGIN",
    fingers: number,
} | {
    is: "GESTURE_HOLD_END",
    fingers: number,
    cancelled: boolean,
} | {
    is: "GESTURE_SWIPE_BEGIN",
    fingers: number,
} | {
    is: "GESTURE_SWIPE_UPDATE",
    frame: number,
    fingers: number,
    delta: vector,
} | {
    is: "GESTURE_SWIPE_END"
} | {
    is: "KEY",
    code: string,
    state: "Press" | "Release"
} | {
    is: "POINTER_BUTTON",
    button: string,
    state: "Press" | "Release"
} | {
    is: "POINTER_SCROLL_FINGER",
    delta: vector,
} | {
    is: "DEVICE_ADDED",
    line: string,
} | {
    is: "OTHER",
    line: string,
}

local events = {}

local _EVENT_TYPES = {
    GESTURE_HOLD_BEGIN = true,
    GESTURE_HOLD_END = true,
    GESTURE_SWIPE_BEGIN = true,
    GESTURE_SWIPE_END = true,
    GESTURE_SWIPE_UPDATE = true,
    KEYBOARD_KEY = true,
    POINTER_BUTTON = true,
    POINTER_MOTION = true,
    POINTER_SCROLL_FINGER = true,
}

function events.parse(line: string): Event
    if string.match(line, "KEYBOARD_KEY") then
        local code = string.match(line, "KEY_([%w]+)")
        return {
            is = "KEY",
            code = code :: string,
            state = if string.match(line, "pressed") then "Press" else "Release",
        }
    elseif string.match(line, "GESTURE_HOLD_BEGIN") then
        local finger_count = string.match(line, "(%d)$")
        local fingers = finger_count and tonumber(finger_count)
        if fingers then
            return {
                is = "GESTURE_HOLD_BEGIN",
                fingers = fingers
            }
        end
    elseif string.match(line, "GESTURE_HOLD_END") then
        local cancelled = if string.match(line, "cancelled") then true else false
        if cancelled then
            line = str.trim(str.trimback(line, "cancelled"))
        end

        local finger_count = string.match(line, "(%d)$")
        local fingers = finger_count and tonumber(finger_count)
        if fingers then
            return {
                is = "GESTURE_HOLD_END",
                fingers = fingers,
                cancelled = cancelled,
            }
        end
    elseif string.match(line, "GESTURE_SWIPE_BEGIN") then
        local finger_count = string.match(line, "(%d)$")
        local fingers = finger_count and tonumber(finger_count)
        if fingers then
            return {
                is = "GESTURE_SWIPE_BEGIN",
                fingers = fingers
            }
        end
    elseif string.match(line, "GESTURE_SWIPE_UPDATE") then
        local splits = str.split(line, " ", "(", ")", "/", "\t")
        local frame, fingers, x, y
        if #splits == 9 then -- no frame
            frame = 0
            fingers = tonumber(splits[4])
            x = tonumber(splits[5])
            y = tonumber(splits[6])
        else
            frame = tonumber(splits[3])
            fingers = tonumber(splits[5])
            x = tonumber(splits[6])
            y = tonumber(splits[7])
        end

        if frame and fingers and x and y then
            return {
                is = "GESTURE_SWIPE_UPDATE",
                frame = frame,
                fingers = fingers,
                delta = vector.create(x, y),
            }
        end

        print(splits)
    elseif string.match(line, "GESTURE_SWIPE_END") then
        return {
            is = "GESTURE_SWIPE_END"
        }
    elseif string.match(line, "POINTER_MOTION") then
        local splits = str.split(line, " ", "(", ")", "/", "\t")
        local frame, x1, y1, x2, y2
        if #splits >= 8 then
            frame = tonumber(splits[3])
            x1 = tonumber(splits[5])
            y1 = tonumber(splits[6])
            x2 = tonumber(str.trimfront(splits[7], "%+"))
            y2 = tonumber(str.trimfront(splits[8], "%+"))
        elseif #splits == 7 then
            frame = 0
            x1 = tonumber(splits[4])
            y1 = tonumber(splits[5])
            x2 = tonumber(str.trimfront(splits[6], "%+"))
            y2 = tonumber(str.trimfront(splits[7], "%+"))
        else
            print(`splits not >= 8, got splits {format(splits)}`)
        end

        if frame and x1 and y1 and x2 and y2 then
            return {
                is = "POINTER_MOTION",
                delta_r = vector.create(x1, y1),
                delta_p = vector.create(x2, y2)
            }
        end
    elseif string.match(line, "POINTER_BUTTON") then
        local btn = string.match(line, "BTN_([%w]+)")
        if btn then
            return {
                is = "POINTER_BUTTON",
                button = btn,
                state = if string.match(line, "pressed") then "Press" else "Release"
            }
        end
    elseif string.match(line, "POINTER_SCROLL_FINGER") then
        local splits = str.split(line, "vert", "horiz", "/")
        local vert = tonumber(str.trim(splits[2]))
        local horiz = tonumber(str.trim(splits[4]))
        if vert and horiz then
            return {
                is = "POINTER_SCROLL_FINGER",
                delta = vector.create(horiz, vert)
            }
        end
    elseif string.match(line, "DEVICE_ADDED") then
        return {
            is = "DEVICE_ADDED",
            line = line,
        }
    end
    
    warn(`fallthrough {line}`)
    return {
        is = "OTHER",
        line = line,
    }
end

return events