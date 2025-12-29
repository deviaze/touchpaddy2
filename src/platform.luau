local yad = require("@libraries/yad")
local colors = require("@std/colors")
local env = require("@std/env")
local process = require("@std/process")

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

return platform :: Platform
