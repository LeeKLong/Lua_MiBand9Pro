local lvgl = require("lvgl")
local activity = nil
pcall(function() activity = require("activity") end)

-- 配置参数
local CONFIG = {
    IMAGE_FILES = {"0.bin", "1.bin", "2.bin", "3.bin"},
    SWITCH_INTERVAL = 500,     -- 图片切换间隔 (ms)
    DELAY_BEFORE_SHOW = 3000,   -- 亮屏后多久启动动画 (ms)
    POSITION = { x = 0, y = 0 }
}

-- 局部状态管理
local ui = {
    timers = {},
    currentIndex = 1,
    isAnimating = false,
    userClosed = false
}

-- 路径处理函数
local fsRoot = SCRIPT_PATH or "/"
local function imgPath(src) return fsRoot .. src end

local function entry()
    -- 1. UI 构建
    ui.root = lvgl.Object(nil, {
        w = lvgl.HOR_RES(),
        h = lvgl.VER_RES(),
        bg_opa = 0,
        border_width = 0,
        pad_all = 0
    })
    ui.root:clear_flag(lvgl.FLAG.SCROLLABLE)
    ui.root:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    ui.img = lvgl.Image(ui.root, {
        src = imgPath(CONFIG.IMAGE_FILES[1]),
        x = CONFIG.POSITION.x,
        y = CONFIG.POSITION.y
    })
    ui.img:add_flag(lvgl.FLAG.HIDDEN)
    ui.img:add_flag(lvgl.FLAG.CLICKABLE)
    ui.img:add_flag(lvgl.FLAG.EVENT_BUBBLE) -- 确保不拦截系统级长按

    -- 2. 动画控制逻辑
    local function stopAnimation()
        if ui.timers.anim then 
            ui.timers.anim:delete() 
            ui.timers.anim = nil 
        end
        ui.isAnimating = false
        ui.img:add_flag(lvgl.FLAG.HIDDEN)
    end

    local function updateImage()
        ui.currentIndex = (ui.currentIndex % #CONFIG.IMAGE_FILES) + 1
        ui.img:set({ src = imgPath(CONFIG.IMAGE_FILES[ui.currentIndex]) })
    end

    local function startAnimation()
        -- 如果已在运行、用户已手动关闭、或者处于编辑模式，则不启动
        local isEdit = activity and activity.isShown({appID=2, pageID=2}) or false
        if ui.isAnimating or ui.userClosed or isEdit then return end
        
        ui.img:clear_flag(lvgl.FLAG.HIDDEN)
        ui.isAnimating = true
        
        ui.timers.anim = lvgl.Timer({
            period = CONFIG.SWITCH_INTERVAL,
            cb = function()
                updateImage()
            end
        })
    end

    -- 3. 延时启动调度
    local function scheduleStart()
        if ui.timers.start then ui.timers.start:delete() ui.timers.start = nil end
        if ui.userClosed then return end

        ui.timers.start = lvgl.Timer({
            period = CONFIG.DELAY_BEFORE_SHOW,
            cb = function(t)
                startAnimation()
                t:delete() -- 执行一次后立即销毁，防止内存堆积
                ui.timers.start = nil
            end
        })
    end

    -- 4. 交互：点击关闭
    ui.img:onClicked(function()
        if ui.timers.start then ui.timers.start:delete() ui.timers.start = nil end
        stopAnimation()
        ui.userClosed = true -- 本次亮屏不再自动弹出
    end)

    -- 5. 生命周期管理
    local function screenON()
        ui.userClosed = false
        scheduleStart()
    end

    local function screenOFF()
        if ui.timers.start then ui.timers.start:delete() ui.timers.start = nil end
        stopAnimation()
    end

    -- 初始执行
    screenON()
    
    return screenON, screenOFF
end

local on, off = entry()

-- 6. 系统屏幕状态回调
function ScreenStateChangedCB(pre, now, reason)
    if pre ~= "ON" and now == "ON" then
        on()
    elseif pre == "ON" and now ~= "ON" then
        off()
    end
end