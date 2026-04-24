local lvgl = require("lvgl")
local math = require("math")
local topic = require("topic")
local activity = require("activity")

-- 核心配置：支持 X 轴和 Y 轴移动
local CONFIG = {
    IMAGE_PATH = SCRIPT_PATH or "/",
    SENSOR_FREQUENCY = 60,
    
    -- 图层列表：speedX/speedY 为 0 则静止，正负值决定移动方向
    LAYERS = {
        { src = "1.bin", x = -44, y = -137, speedX = 4.0, speedY = 4.0 },
        { src = "2.bin", x = 26, y = 63, speedX = -2.0, speedY = -2.0 },
    }
}

local function entry()
    local root = lvgl.Object(nil, {
        w = lvgl.HOR_RES(), h = lvgl.VER_RES(),
        bg_opa = 0, border_width = 0, pad_all = 0
    })
    root:clear_flag(lvgl.FLAG.SCROLLABLE)

    -- 启用 Root 的点击冒泡，让长按手势直达系统
    root:add_flag(lvgl.FLAG.CLICKABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    local isPaused = false
    root:onClicked(function()
        isPaused = not isPaused
    end)

    -- 初始化图层对象
    local layerWidgets = {}
    for _, cfg in ipairs(CONFIG.LAYERS) do
        local img = lvgl.Image(root, {
            src = CONFIG.IMAGE_PATH .. cfg.src,
            x = cfg.x, y = cfg.y
        })
        -- 强制清除图片的可点击标志，防止拦截手势
        img:clear_flag(lvgl.FLAG.CLICKABLE)
        table.insert(layerWidgets, {
            widget = img,
            cfg = cfg,
            baseX = cfg.x, baseY = cfg.y,
            currX = cfg.x, currY = cfg.y
        })
    end

    -- 创建全屏遮罩层
    local fadeMask = lvgl.Object(root, {
        w = lvgl.HOR_RES(),
        h = lvgl.VER_RES(),
        bg_color = 0x000000,
        bg_opa = 255,
        border_width = 0,
        pad_all = 0
    })
    fadeMask:clear_flag(lvgl.FLAG.CLICKABLE)
    fadeMask:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    local fadeAnim = lvgl.Anim(fadeMask, {
        start_value = 255,
        end_value   = 0,
        duration    = 300,
        path        = "linear",
        exec_cb     = function(obj, v) obj:set({ bg_opa = v }) end,
        done_cb     = function(anim, obj) obj:add_flag(lvgl.FLAG.HIDDEN) end,
        run         = true
    })

    local sensorSub = nil

    local function updateLoop(acc)
        if isPaused then return end
        for _, layer in ipairs(layerWidgets) do
            local c = layer.cfg
            -- X 轴和 Y 轴都跟随重力
            local targetX = layer.baseX + (-acc.x * c.speedX)
            local targetY = layer.baseY + (acc.y * c.speedY)
            
            -- 插值更新
            layer.currX = layer.currX + (targetX - layer.currX) * 0.1
            layer.currY = layer.currY + (targetY - layer.currY) * 0.1
            
            -- 应用位置（更新 X 和 Y）
            layer.widget:set({ x = math.floor(layer.currX + 0.5), y = math.floor(layer.currY + 0.5) })
        end
    end

    local function screenONCb()
        -- 恢复遮罩并播放动画
        fadeMask:clear_flag(lvgl.FLAG.HIDDEN)
        fadeAnim:start()

        if sensorSub then return end
        sensorSub = topic.subscribe("sensor_accel", 0, function(t, status, value)
            if status == 0 and type(value) == "table" and type(value[1]) == "table" then
                if activity.isShown { appID = activity.APPID.WATCHFACE, pageID = 2 } then return end
                updateLoop(value[1])
            end
        end)
        if sensorSub then sensorSub:frequency(CONFIG.SENSOR_FREQUENCY) end
    end

    local function screenOFFCb()
        if sensorSub then sensorSub:unsubscribe() sensorSub = nil end
    end

    screenONCb()
    return screenONCb, screenOFFCb
end

local on, off = entry()
function ScreenStateChangedCB(pre, now, reason)
    if pre ~= "ON" and now == "ON" then on()
    elseif pre == "ON" and now ~= "ON" then off() end
end
