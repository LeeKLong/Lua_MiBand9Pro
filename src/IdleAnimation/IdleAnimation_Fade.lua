local lvgl = require("lvgl")
local activity = nil
pcall(function() activity = require("activity") end)

-- 配置参数
local CONFIG = {
    IMAGE_FILES = {"0.bin"},
    SWITCH_INTERVAL = 500,     -- 图片切换间隔 (ms)
    DELAY_BEFORE_SHOW = 2500,   -- 亮屏后多久启动动画 (ms)
    POSITION = { x = 0, y = 0 },
    FADE_DURATION = 300        -- 渐变时长 (ms)
}

-- 局部状态管理
local ui = {
    timers = {},
    curIdx = 1,
    nextIdx = 2,
    isAnimating = false,
    userClosed = false,
    inTransition = false,
    bgTopOpa = 0,
    bgBottomOpa = 255,
    isClosing = false,
    isOpening = false
}

-- 路径处理函数
local fsRoot = SCRIPT_PATH or "/"
local function imgPath(src) return fsRoot .. src end

local function entry()
    local picCount = #CONFIG.IMAGE_FILES
    if picCount < 2 then
        ui.nextIdx = 1
    end

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

    -- 底层图片
    ui.bgBottom = lvgl.Image(ui.root, {
        src = imgPath(CONFIG.IMAGE_FILES[ui.curIdx]),
        x = CONFIG.POSITION.x,
        y = CONFIG.POSITION.y
    })
    ui.bgBottom:add_flag(lvgl.FLAG.HIDDEN)
    ui.bgBottom:add_flag(lvgl.FLAG.CLICKABLE)
    ui.bgBottom:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    -- 顶层图片 (用于渐变)
    ui.bgTop = lvgl.Image(ui.root, {
        src = imgPath(CONFIG.IMAGE_FILES[ui.nextIdx]),
        x = CONFIG.POSITION.x,
        y = CONFIG.POSITION.y,
        opa = 0
    })
    ui.bgTop:add_flag(lvgl.FLAG.HIDDEN)
    ui.bgTop:add_flag(lvgl.FLAG.CLICKABLE)
    ui.bgTop:add_flag(lvgl.FLAG.EVENT_BUBBLE)

    -- 全局渐显遮罩 (fade-bright 融合)
    ui.mask = lvgl.Object(nil, {
        w = lvgl.HOR_RES(),
        h = lvgl.VER_RES(),
        bg_color = 0x000000,
        bg_opa = 255,
        border_width = 0,
        pad_all = 0
    })
    ui.mask:clear_flag(lvgl.FLAG.CLICKABLE)
    ui.mask:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    
    ui.maskFadeAnim = lvgl.Anim(ui.mask, {
        start_value = 255,
        end_value   = 0,
        duration    = 500,
        path        = "ease_out",
        exec_cb     = function(obj, v)
            obj:set({ bg_opa = v })
        end,
        done_cb     = function(anim, obj)
            obj:add_flag(lvgl.FLAG.HIDDEN)
        end
    })

    -- 2. 动画控制逻辑
    local function finishTransition()
        ui.inTransition = false
        ui.curIdx = ui.nextIdx
        ui.nextIdx = (ui.curIdx % picCount) + 1
        ui.bgBottom:set({ src = imgPath(CONFIG.IMAGE_FILES[ui.curIdx]) })
        ui.bgTop:set({ src = imgPath(CONFIG.IMAGE_FILES[ui.nextIdx]), opa = 0 })
        ui.bgTopOpa = 0
    end

    ui.fadeAnim = ui.bgTop:Anim{
        start_value = 0,
        end_value = 255,
        duration = CONFIG.FADE_DURATION,
        path = "ease_in_out",
        exec_cb = function(obj, v) 
            ui.bgTopOpa = v
            obj:set({ opa = v }) 
        end,
        done_cb = finishTransition
    }

    local function stopAnimation()
        if ui.timers.anim then 
            ui.timers.anim:delete() 
            ui.timers.anim = nil 
        end
        if ui.inTransition then
            ui.fadeAnim:stop()
            ui.inTransition = false
        end
        if ui.isClosing and ui.closeAnim then
            ui.closeAnim:stop()
            ui.isClosing = false
        end
        if ui.isOpening and ui.showAnim then
            ui.showAnim:stop()
            ui.isOpening = false
        end
        ui.isAnimating = false
        ui.bgBottomOpa = 255
        ui.bgBottom:add_flag(lvgl.FLAG.HIDDEN)
        ui.bgTop:add_flag(lvgl.FLAG.HIDDEN)
    end

    local function updateImage()
        if not ui.inTransition then
            ui.inTransition = true
            ui.fadeAnim:start()
        end
    end

    local function startAnimation()
        -- 如果已在运行、用户已手动关闭、或者处于编辑模式，则不启动
        local isEdit = activity and activity.isShown({appID=2, pageID=2}) or false
        if ui.isAnimating or ui.userClosed or isEdit then return end
        
        ui.isAnimating = true
        ui.isOpening = true
        
        ui.bgBottom:set({ opa = 0 })
        ui.bgTop:set({ opa = 0 })
        ui.bgBottomOpa = 0
        ui.bgTopOpa = 0
        ui.bgBottom:clear_flag(lvgl.FLAG.HIDDEN)
        ui.bgTop:clear_flag(lvgl.FLAG.HIDDEN)
        
        ui.showAnim = ui.bgBottom:Anim{
            start_value = 0,
            end_value = 255,
            duration = 300,
            path = "ease_in",
            exec_cb = function(obj, v)
                ui.bgBottomOpa = v
                obj:set({ opa = v })
            end,
            done_cb = function()
                ui.bgBottomOpa = 255
                ui.bgBottom:set({ opa = 255 })
                ui.isOpening = false
            end
        }
        ui.showAnim:start()
        
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
    local function onClick()
        if ui.isClosing then return end
        ui.isClosing = true
        ui.userClosed = true -- 本次亮屏不再自动弹出

        if ui.timers.start then ui.timers.start:delete() ui.timers.start = nil end
        
        -- 停止动画播放器
        if ui.timers.anim then 
            ui.timers.anim:delete() 
            ui.timers.anim = nil 
        end
        if ui.inTransition then
            ui.fadeAnim:stop()
            ui.inTransition = false
        end
        if ui.isOpening and ui.showAnim then
            ui.showAnim:stop()
            ui.isOpening = false
        end

        local startTopOpa = ui.bgTopOpa
        local startBottomOpa = ui.bgBottomOpa
        ui.closeAnim = ui.bgBottom:Anim{
            start_value = startBottomOpa,
            end_value = 0,
            duration = 300,
            path = "ease_out",
            exec_cb = function(obj, v)
                ui.bgBottomOpa = v
                obj:set({ opa = v })
                -- top 层按当前透明度的比例同时衰减
                local topV = 0
                if startBottomOpa > 0 then
                    topV = math.floor(startTopOpa * (v / startBottomOpa))
                end
                ui.bgTopOpa = topV
                ui.bgTop:set({ opa = topV })
            end,
            done_cb = function()
                stopAnimation()
                ui.bgBottom:set({ opa = 255 })
                ui.bgTop:set({ opa = 0 })
                ui.bgBottomOpa = 255
                ui.bgTopOpa = 0
                ui.isClosing = false
            end
        }
        ui.closeAnim:start()
    end
    ui.bgBottom:onClicked(onClick)
    ui.bgTop:onClicked(onClick)

    -- 5. 生命周期管理
    local function screenON()
        local isEdit = activity and activity.isShown({appID=2, pageID=2}) or false
        if not isEdit then
            ui.mask:clear_flag(lvgl.FLAG.HIDDEN)
            ui.maskFadeAnim:start()
        else
            ui.mask:add_flag(lvgl.FLAG.HIDDEN)
        end

        ui.userClosed = false
        scheduleStart()
    end

    local function screenOFF()
        ui.maskFadeAnim:stop()
        ui.mask:set({ bg_opa = 255 })

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
