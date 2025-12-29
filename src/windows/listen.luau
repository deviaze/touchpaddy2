local process = require("@std/process")
local str = require("@std/str")
local time = require("@std/time")
if not channel then
    error("must be in child thread")
end

while time.wait(0.15) do
    -- search all currently open windows, sending back missing ones to 
    -- parent thread (to add to tracked windows)
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
