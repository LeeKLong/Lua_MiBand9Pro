local lvgl = require("lvgl")
-- 尝试加载 activity 模块用于判断编辑态
local activity = nil
pcall(function() activity = require("activity") end)

local ui = {}

-- 1. 创建全屏遮罩层
ui.mask = lvgl.Object(nil, {
    w = lvgl.HOR_RES(),
    h = lvgl.VER_RES(),
    bg_color = 0x000000,
    bg_opa = 255,
    border_width = 0,
    pad_all = 0
})

-- 【完善：防止干扰】
-- 显式关闭点击，并开启事件冒泡，确保系统级长按手势不受影响
ui.mask:clear_flag(lvgl.FLAG.CLICKABLE)
ui.mask:add_flag(lvgl.FLAG.EVENT_BUBBLE)

-- 2. 初始化动画句柄
ui.fadeAnim = lvgl.Anim(ui.mask, {
    start_value = 255,
    end_value   = 0,
    duration    = 500,
    path        = "ease_out",
    exec_cb     = function(obj, v)
        obj:set({ bg_opa = v })
    end,
    done_cb     = function(anim, obj)
        -- 动画完成后隐藏层，防止遮挡下方 UI 刷新
        obj:add_flag(lvgl.FLAG.HIDDEN)
    end
})

-- 3. 系统状态管理回调
function ScreenStateChangedCB(pre, now, reason)
    -- 判断是否在表盘编辑模式
    local isEdit = false
    if activity then
        -- appID 2, pageID 2 通常代表表盘编辑界面
        isEdit = activity.isShown({ appID = 2, pageID = 2 })
    end

    if now == "ON" then
        if not isEdit then
            -- 正常亮屏：显示遮罩并启动渐隐动画
            ui.mask:clear_flag(lvgl.FLAG.HIDDEN)
            ui.fadeAnim:start()
        else
            -- 编辑模式：强制隐藏遮罩以防干扰编辑预览
            ui.mask:add_flag(lvgl.FLAG.HIDDEN)
        end
    else
        -- 屏幕关闭：立即停止动画节省资源，并重置透明度为下次亮屏做准备
        ui.fadeAnim:stop()
        ui.mask:set({ bg_opa = 255 })
    end
end

-- 4. 初始启动处理
-- 如果脚本在屏幕开启时加载，则立即执行一次
ScreenStateChangedCB("OFF", "ON", "INIT")
