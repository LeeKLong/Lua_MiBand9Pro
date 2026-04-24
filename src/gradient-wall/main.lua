local lvgl = require("lvgl")
local math = require("math")
local topic = require("topic")

-- 防御性加载
local activity, vibrator = nil, nil
pcall(function() activity = require("activity") end)
pcall(function() vibrator = require("vibrator") end)

-- 配置参数
local CONFIG = {
    IMAGE_PATH = SCRIPT_PATH or "/",
    SENSOR_FREQUENCY = 50, -- 50Hz 足够捕捉抬腕动作
    
    IMAGE_LIST = {
        "1.bin",
        "2.bin",
        "3.bin",
        "4.bin",
        "5.bin",
        "6.bin",
        "7.bin",
        "8.bin",
        "9.bin",
    },
    
    G_THRESHOLD_ON = 5.0, 
    G_THRESHOLD_OFF = 2.0,
    FADE_DURATION = 300, -- 渐变时长 (ms)
    ANIM_FPS = 60,       -- 动画帧率
    COOLDOWN_MS = 600,   -- 两次触发间的冷却时间 (ms)
    FILTER_ALPHA = 0.3,   -- 传感器低通滤波系数 (0~1, 越小越平滑)
}

local function entry()
    local picCount = #CONFIG.IMAGE_LIST
    local IMAGE_PATHS = {}
    for i = 1, picCount do
        IMAGE_PATHS[i] = CONFIG.IMAGE_PATH .. CONFIG.IMAGE_LIST[i]
    end
    
    -- 1. 状态管理
    local state = {
        curIdx = 1,
        nextIdx = 2,
        isArmUp = false,
        isPaused = false,
        lastTrigger = 0,
        filtX = 0,
        filtY = 0,
    }

    -- 2. UI 构建
    local root = lvgl.Object(nil, {
        w = lvgl.HOR_RES(), h = lvgl.VER_RES(),
        bg_opa = 0, border_width = 0, pad_all = 0
    })
    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    local bgBottom = lvgl.Image(root, {
        src = IMAGE_PATHS[state.curIdx],
        align = lvgl.ALIGN.CENTER
    })

    local bgTop = lvgl.Image(root, {
        src = IMAGE_PATHS[state.nextIdx],
        align = lvgl.ALIGN.CENTER,
        opa = 0
    })
    bgTop:add_flag(lvgl.FLAG.CLICKABLE)
    bgTop:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    -- 3. 动画控制
    local isAnimating = false

    local function finishTransition()
        isAnimating = false
        state.curIdx = state.nextIdx
        state.nextIdx = (state.curIdx % picCount) + 1
        bgBottom:set({ src = IMAGE_PATHS[state.curIdx] })
        bgTop:set({ src = IMAGE_PATHS[state.nextIdx], opa = 0 })
    end

    local fadeAnim = bgTop:Anim{
        start_value = 0,
        end_value = 255,
        duration = CONFIG.FADE_DURATION,
        path = "ease_in_out",
        exec_cb = function(obj, v) obj:set({ opa = v }) end,
        done_cb = finishTransition
    }

    local function startTransition()
        local now = (os.clock() or 0) * 1000
        if isAnimating or state.isPaused or (now - state.lastTrigger < CONFIG.COOLDOWN_MS) then 
            return 
        end
        state.lastTrigger = now
        isAnimating = true
        fadeAnim:start()
    end

    bgTop:onClicked(startTransition)

    -- 4. 传感器逻辑
    local alpha = CONFIG.FILTER_ALPHA
    local invAlpha = 1 - alpha
    local thOn = CONFIG.G_THRESHOLD_ON
    local thOff = CONFIG.G_THRESHOLD_OFF

    local function updateSensor(acc)
        if state.isPaused or isAnimating then return end
        
        -- 低通滤波处理噪声 (移除 or 0，提高计算效率)
        state.filtX = state.filtX * invAlpha + acc.x * alpha
        state.filtY = state.filtY * invAlpha + acc.y * alpha
        
        local x, y = state.filtX, state.filtY

        if x > thOn or x < -thOn or y > thOn or y < -thOn then
            if not state.isArmUp then
                state.isArmUp = true
                startTransition()
            end
        elseif x < thOff and x > -thOff and y < thOff and y > -thOff then
            state.isArmUp = false
        end
    end

    -- 5. 生命周期管理
    local sensorSub = nil
    
    local function screenOFFCb()
        if sensorSub then sensorSub:unsubscribe() sensorSub = nil end
        if isAnimating then fadeAnim:stop() isAnimating = false end
        state.isPaused = true
    end

    local function screenONCb(isWakeup)
        state.isPaused = false
        if isWakeup then
            startTransition()
        end
        
            if not sensorSub then
                sensorSub = topic.subscribe("sensor_accel", 0, function(_, status, value)
                    if status == 0 and value and value[1] then
                        updateSensor(value[1])
                    end
                end)
                if sensorSub then sensorSub:frequency(15) end
            end
        end

    -- 定时检测编辑模式
    local editParams = {appID = activity and activity.APPID.WATCHFACE or 0, pageID = 2}
    local checkTimer = lvgl.Timer({
        period = 1000,
        cb = function()
            if not activity then return end
            local editing = activity.isShown(editParams)
            if editing then
                if not state.isPaused then screenOFFCb() end
            else
                if state.isPaused then screenONCb(false) end
            end
        end
    })

    screenONCb(true) -- 初始启动
    return function() screenONCb(true) end, screenOFFCb
end

local on, off = entry()
function ScreenStateChangedCB(pre, now, reason)
    if pre ~= "ON" and now == "ON" then 
        if on then on() end
    elseif pre == "ON" and now ~= "ON" then 
        if off then off() end 
    end
end
