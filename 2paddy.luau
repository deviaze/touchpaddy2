--!optimize 2
--!nolint LocalShadow
--!strict
local process = require("@std/process")
local thread = require("@std/thread")
-- START /home/deviaze/Repositories/2paddy/src/platform.luau
-- START /home/deviaze/Repositories/2paddy/libraries/yad.luau

export type DialogOptions = {
    Title: string?,
    Text: string?,
    Buttons: {
        {
            ButtonText: string,
            ButtonResponse: string,
        }
    }?,
    List: {
        ListType: "Checklist" | "Tree" | "Radiolist" | "None" ?,
        Columns: { string },
        Entries: { { string } },
        Options: {
            Editable: boolean?,
            EditableColumns: { number }?,
            DoubleClickAction: string?,
        }?,
    }?,
    Size: {
        Width: number,
        Height: number,
    }?,
}

local function prompt(options: DialogOptions)
    local spawn_command = ""
    if options.Title then
        spawn_command ..= ` --title="{options.Title}" `
    end
    if options.Text then
        spawn_command ..= ` --text="{options.Text}" `
    end

    if options.Size then
        spawn_command ..= ` --width={options.Size.Width} --height={options.Size.Height}`
    end

    if options.List then
        local list_info = options.List
        spawn_command ..= ` --list {
            if list_info.ListType == "Checklist" then
                "--checklist"
            elseif list_info.ListType == "Tree" then
                "--tree"
            elseif list_info.ListType == "Radiolist" then
                "--radiolist"
            else "--multiple"
        }`

        local list_options = list_info.Options
        if list_options then
            if list_options.Editable then
                spawn_command ..= " --editable"
            end
            if list_options.EditableColumns then
                local cols = table.concat(list_options.EditableColumns, ",")
                spawn_command ..= ` --editable-cols="{cols}"`
            end
            if list_options.DoubleClickAction then
                spawn_command ..= ` --dclick-action={list_options.DoubleClickAction}`
            end
        end

        local column_count = 0
        for _, column_name in list_info.Columns do
            spawn_command ..= ` --column="{column_name}"`
            column_count += 1
        end
        for index, entry in list_info.Entries do
            if #entry ~= column_count then
                error(`yad gui wrapper: entry {index} provided with invalid column count.\n Got {#entry} columns, expected {column_count} `)
            else
                for column_index, column_text in entry do
                    entry[column_index] = `"{column_text}"`
                end
                spawn_command ..= ` {table.concat(entry, " ")} `
            end
        end
    end

    if options.Buttons then
        for _, button in options.Buttons do
            spawn_command ..= ` --button="{button.ButtonText}":"echo {button.ButtonResponse}"`
        end
    end

    local child = process.spawn {
        program = `yad {spawn_command}`,
        shell = "sh",
    }

    local button_response: string?
    repeat
        button_response = child.stdout:read(200)
    until button_response

    assert(button_response ~= nil, "can't be nil here")

    button_response = string.gsub(button_response, "%s", "")

    if child:alive() then
        child:kill()
    end

    return button_response
end

local resolved_require_yad = {
    prompt = prompt,
}
local yad = resolved_require_yad
local colors = require("@std/colors")
local env = require("@std/env")

export type Platform = {
    os: "Linux" | "MacOS" | "Windows",
    desktop_environment: "KDE" | "Gnome" | string,
    session: "X11" | "Wayland" | "Other",
    check_dependencies: (self: Platform) -> (),
}

local platform = {}

if env.os == "Linux" then
    local xdg_desktop_result = process.shell("echo $XDG_CURRENT_DESKTOP")
    local xdg_session_result = process.shell("echo $XDG_SESSION_TYPE")

    if xdg_desktop_result.ok and xdg_session_result.ok then
        platform.os = "Linux"
        platform.desktop_environment =
            if xdg_desktop_result.out:match("KDE") then
                "KDE"
            elseif xdg_desktop_result.out:match("GNOME") then
                "GNOME"
            else
                "Other"
        platform.session =
            if xdg_session_result.out:match("x11") then
                "X11"
            elseif xdg_session_result.out:match("wayland") then
                "Wayland"
            else
                "Other"
    end
else
    error('other os not supported yet, only linux supported')
end

function platform.check_dependencies(info: Platform)
    if info.os == "Linux" and info.desktop_environment == "KDE" then
        type DependencyInfo = {
            command: string,
            because: string,
            install: string
        }
        local Dependency = {}
        function Dependency.new(command: string, because: string, install: string): DependencyInfo
            return {
                command = command,
                because = because,
                install = install
            }
        end
        function Dependency.to_column(self: DependencyInfo): { string }
            return { self.command, self.because, self.install }
        end

        local dependencies: { DependencyInfo } = {
            Dependency.new("yad", "shows guis", "yad from system package manager (repo: https://github.com/v1cont/yad)"),
            Dependency.new("screen", "allows us to run touchpaddy in the background", "install screen from package manager"),
            Dependency.new("kdotool", "KDE: kdotools lets us move, open/close, and tab through windows", "https://github.com/jinliu/kdotool or package manager?"),
            Dependency.new("ydotool", "X11/Wayland: lets us send keystrokes to control windows", "https://github.com/ReimuNotMoe/ydotool or package manager"),
            Dependency.new("libinput", "We need to track all keystrokes to detect gestures", "need libinput-tools from arch/apt")
        }

        local yad_missing = false
        local dependencies_failed: { DependencyInfo } = {}
        for _, dependency in dependencies do
            local result = process.shell(`{dependency.command} --help`)
            if not result.ok then
                table.insert(dependencies_failed, dependency)
                if dependency.command == "yad" then
                    yad_missing = true
                end
            end
        end

        if #dependencies_failed > 0 then
            if yad_missing then
                warn("Missing dependencies!")
                for index, dep in dependencies_failed do
                    print(index)
                    print(`  {colors.bold.yellow(dep.command)}`)
                    print(`  Reason: {dep.because}`)
                    print(`  Install: {dep.install}`)
                end
            else
                local columns = {
                    "Command", "Reason", "Install"
                }
                yad.prompt({
                    Title = "touchpaddy - dependencies not found",
                    Text = "We need the following programs !!\nPlease install them (package manager or PATH is ok!) and relaunch touchpaddy:",
                    List = {
                        ListType = "None",
                        Columns = columns,
                        Entries = (function()
                            local r = {}
                            for _, dep in dependencies_failed do
                                table.insert(r, Dependency.to_column(dep))
                            end
                            return r
                        end)(),
                        Options = {
                            Editable = true, -- allow copy/paste
                            EditableColumns = { 3 },
                        }
                    },
                    Buttons = {
                        {
                            ButtonText = "Ok",
                            ButtonResponse = "",
                        }
                    },
                    Size = {
                        Width = 1260,
                        Height = 200
                    }
                })
            end
            process.exit(1)
        end

        process.spawn {
            program = "ydotoold"
        }
    else
        warn("dependencies not checked for current os")
    end
end

local resolved_require_platform = platform :: Platform
local platform = resolved_require_platform
-- START /home/deviaze/Repositories/2paddy/src/events.luau
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

local resolved_require_events = events
local events = resolved_require_events
-- START /home/deviaze/Repositories/2paddy/src/windows/init.luau
-- START /home/deviaze/Repositories/2paddy/src/keys/init.luau

-- START /home/deviaze/Repositories/2paddy/src/keys/linux.luau

local keys = {}
local keycodes = {}

function keys.parse(keys: string): string
    local result = ""
    local stripped_whitespace = string.gsub(keys, "%s", "")

    local split_by_commas = string.split(stripped_whitespace, ",")
    for _, action in split_by_commas do
        local keydowns = ""
        local keyups = ""
        local combinations = string.split(action, "+")
        for _, key in combinations do
            if #combinations > 1 and string.match(key, ":") then
                error("can't have : in a + combo")
            else
                local keycode = (keycodes[key] or keycodes[string.upper(key)] or keycodes["NUM" .. key]) :: number?
                if keycode then
                    keydowns ..= (if #keydowns > 0 then " " else "") .. `{keycode}:1`
                    keyups ..= (if #keyups > 0 then " " else "") .. `{keycode}:0`
                else
                    print(`{key} not keycode?`)
                end
            end
        end
        result ..= (if #result > 0 then " " else "") .. keydowns .. " " .. keyups
    end

    return result
end

local tests: {{[string]: string}} = {
    {["Ctrl"] = "29:1 29:0"},
    {["Alt+Tab"] = "56:1 15:1 56:0 15:0"},
    {["Alt, Tab"] = "56:1 56:0 15:1 15:0"},
    {["Ctrl + C"] = "29:1 46:1 29:0 46:0"},
    {["Ctrl+F9"] = "29:1 67:1 29:0 67:0"},
    {["Ctrl+F9, Alt"] = "29:1 67:1 29:0 67:0 56:1 56:0"},
    {["Meta + PageUp"] = "125:1 104:1 125:0 104:0"},
    {["Meta + 1"] = "125:1 2:1 125:0 2:0"},
}

keycodes = {
    RESERVED = 0,
    Esc = 1,
    ESC = 1,
    NUM1 = 2,
    NUM2 = 3,
    NUM3 = 4,
    NUM4 = 5,
    NUM5 = 6,
    NUM6 = 7,
    NUM7 = 8,
    NUM8 = 9,
    NUM9 = 10,
    NUM0 = 11,
    KEY_1 = 2,
    KEY_2 = 3,
    KEY_3 = 4,
    KEY_4 = 5,
    KEY_5 = 6,
    KEY_6 = 7,
    KEY_7 = 8,
    KEY_8 = 9,
    KEY_9 = 10,
    KEY_0 = 11,
    MINUS = 12,
    EQUAL = 13,
    Backspace = 14,
    BACKSPACE = 14,
    Tab = 15,
    TAB = 15,
    Q = 16,
    W = 17,
    E = 18,
    R = 19,
    T = 20,
    Y = 21,
    U = 22,
    I = 23,
    O = 24,
    P = 25,
    LEFTBRACE = 26,
    RIGHTBRACE = 27,
    ENTER = 28,
    Ctrl = 29,
    LEFTCTRL = 29,
    A = 30,
    S = 31,
    D = 32,
    F = 33,
    G = 34,
    H = 35,
    J = 36,
    K = 37,
    L = 38,
    SEMICOLON = 39,
    APOSTROPHE = 40,
    GRAVE = 41,
    Shift = 42,
    LEFTSHIFT = 42,
    BACKSLASH = 43,
    Z = 44,
    X = 45,
    C = 46,
    V = 47,
    B = 48,
    N = 49,
    M = 50,
    COMMA = 51,
    DOT = 52,
    SLASH = 53,
    RIGHTSHIFT = 54,
    KPASTERISK = 55,
    Alt = 56,
    LEFTALT = 56,
    SPACE = 57,
    CAPSLOCK = 58,
    F1 = 59,
    F2 = 60,
    F3 = 61,
    F4 = 62,
    F5 = 63,
    F6 = 64,
    F7 = 65,
    F8 = 66,
    F9 = 67,
    F10 = 68,
    LOCK = 69,
    SCROLLLOCK = 70,
    KP7 = 71,
    KP8 = 72,
    KP9 = 73,
    KPMINUS = 74,
    KP4 = 75,
    KP5 = 76,
    KP6 = 77,
    KPPLUS = 78,
    KP1 = 79,
    KP2 = 80,
    KP3 = 81,
    KP0 = 82,
    KPDOT = 83,
    ZENKAKUHANKAKU = 85,
    KEY_102ND = 86,
    F11 = 87,
    F12 = 88,
    RO = 89,
    KATAKANA = 90,
    HIRAGANA = 91,
    HENKAN = 92,
    KATAKANAHIRAGANA = 93,
    MUHENKAN = 94,
    KPJPCOMMA = 95,
    KPENTER = 96,
    RIGHTCTRL = 97,
    KPSLASH = 98,
    SYSRQ = 99,
    RIGHTALT = 100,
    LINEFEED = 101,
    HOME = 102,
    UP = 103,
    PAGEUP = 104,

    Left = 105,
    Right = 106,
    Up = 103,
    Down = 108,

    LEFT = 105,
    RIGHT = 106,
    END = 107,
    DOWN = 108,
    PAGEDOWN = 109,
    INSERT = 110,
    Delete = 111,
    DELETE = 111,
    MACRO = 112,
    MUTE = 113,
    VOLUMEDOWN = 114,
    VOLUMEUP = 115,
    POWER = 116,
    KPEQUAL = 117,
    KPPLUSMINUS = 118,
    PAUSE = 119,
    SCALE = 120,
    KPCOMMA = 121,
    HANGEUL = 122,
    HANJA = 123,
    YEN = 124,
    Win = 125,
    Meta = 125,
    Super = 125,
    LEFTMETA = 125,
    RIGHTMETA = 126,
    COMPOSE = 127,
    STOP = 128,
    AGAIN = 129,
    PROPS = 130,
    UNDO = 131,
    FRONT = 132,
    COPY = 133,
    OPEN = 134,
    PASTE = 135,
    FIND = 136,
    CUT = 137,
    HELP = 138,
    MENU = 139,
    CALC = 140,
    SETUP = 141,
    SLEEP = 142,
    WAKEUP = 143,
    FILE = 144,
    SENDFILE = 145,
    DELETEFILE = 146,
    XFER = 147,
    PROG1 = 148,
    PROG2 = 149,
    WWW = 150,
    MSDOS = 151,
    COFFEE = 152,
    ROTATE_DISPLAY = 153,
    CYCLEWINDOWS = 154,
    MAIL = 155,
    BOOKMARKS = 156,
    COMPUTER = 157,
    BACK = 158,
    FORWARD = 159,
    CLOSECD = 160,
    EJECTCD = 161,
    EJECTCLOSECD = 162,
    NEXTSONG = 163,
    PLAYPAUSE = 164,
    PREVIOUSSONG = 165,
    STOPCD = 166,
    RECORD = 167,
    REWIND = 168,
    PHONE = 169,
    ISO = 170,
    CONFIG = 171,
    HOMEPAGE = 172,
    REFRESH = 173,
    EXIT = 174,
    MOVE = 175,
    EDIT = 176,
    SCROLLUP = 177,
    SCROLLDOWN = 178,
    KPLEFTPAREN = 179,
    KPRIGHTPAREN = 180,
    NEW = 181,
    REDO = 182,
    F13 = 183,
    F14 = 184,
    F15 = 185,
    F16 = 186,
    F17 = 187,
    F18 = 188,
    F19 = 189,
    F20 = 190,
    F21 = 191,
    F22 = 192,
    F23 = 193,
    F24 = 194,
    PLAYCD = 200,
    PAUSECD = 201,
    PROG3 = 202,
    PROG4 = 203,
    ALL_APPLICATIONS = 204,
    SUSPEND = 205,
    CLOSE = 206,
    PLAY = 207,
    FASTFORWARD = 208,
    BASSBOOST = 209,
    PRINT = 210,
    HP = 211,
    CAMERA = 212,
    SOUND = 213,
    QUESTION = 214,
    EMAIL = 215,
    CHAT = 216,
    SEARCH = 217,
    CONNECT = 218,
    FINANCE = 219,
    SPORT = 220,
    SHOP = 221,
    ALTERASE = 222,
    CANCEL = 223,
    BRIGHTNESSDOWN = 224,
    BRIGHTNESSUP = 225,
    MEDIA = 226,
    SWITCHVIDEOMODE = 227,
    KBDILLUMTOGGLE = 228,
    KBDILLUMDOWN = 229,
    KBDILLUMUP = 230,
    SEND = 231,
    REPLY = 232,
    FORWARDMAIL = 233,
    SAVE = 234,
    DOCUMENTS = 235,
    BATTERY = 236,
    BLUETOOTH = 237,
    WLAN = 238,
    UWB = 239,
    UNKNOWN = 240,
    VIDEO_NEXT = 241,
    VIDEO_PREV = 242,
    BRIGHTNESS_CYCLE = 243,
    BRIGHTNESS_AUTO = 244,
    DISPLAY_OFF = 245,
    WWAN = 246,
    RFKILL = 247,
    MICMUTE = 248,
}

keys.Keycodes = keycodes

local resolved_require_keys = keys
local linux_keys = resolved_require_keys
local platform = resolved_require_platform

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

local resolved_require_keys = keys
local keys = resolved_require_keys
local platform = resolved_require_platform

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
        src = [=====[
local process = require("@std/process")
local str = require("@std/str")
local time = require("@std/time")
if not channel then
    error("must be in child thread")
end

while time.wait(0.15) do
    local search_result = process.shell("kdotool search ''")
    if not search_result.ok then
        warn(`kwin not happy?: {search_result.err}`)
        continue
    elseif search_result.ok and #search_result.stdout == 0 then
        warn("search empty")
        continue
    end

    local window_ids: { string } = str.split(search_result:unwrap(), "\n")
    for _, window_id in window_ids do
        local window_name = process.shell(`kdotool getwindowname {window_id}`)
        window_name = if window_name.ok then window_name:unwrap() else nil
        local window_class_name = process.shell(`kdotool getwindowclassname {window_id}`)
        window_class_name = if window_class_name.ok then window_class_name:unwrap() else nil

        if window_name and window_class_name then
            channel:send({
                event = "WindowFound",
                data = {
                    id = window_id,
                    name = window_name,
                    class_name = window_class_name,
                    last_access = os.clock()
                }
            })
        end
    end

    local result = process.shell("kdotool getactivewindow")
    if result.ok then
        local window_id = string.match(result.out, "({[%w%-]+})")
        channel:send({
            event = "NewActive",
            data = window_id,
        })
    end

end
]=====]
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

local resolved_require_windows = windows
local windows = resolved_require_windows

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