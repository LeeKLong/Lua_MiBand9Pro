local lvgl = require("lvgl")
local math = require("math")
local os = require("os")
local topic = require("topic")
local dataman = require("dataman")

-- 图片路径前缀
local fsRoot = SCRIPT_PATH or "/"
function imgPath(src)
    return fsRoot .. src
end

-- 图片文件名称，假设为0.bin, 1.bin, 2.bin, 3.bin
local IMAGE_FILES = {"0.bin", "1.bin", "2.bin", "3.bin"}
local IMAGE_COUNT = #IMAGE_FILES
local SWITCH_INTERVAL = 500  -- 毫秒
local DELAY_BEFORE_SHOW = 3000  -- 毫秒

-- 位置设置，请根据需要修改 x, y 坐标
-- 例如：local IMAGE_POSITION = { x = 100, y = 100 }
local IMAGE_POSITION = { x = 0, y = 0 }

-- 准备主函数
local function entry()
    -- 创建根容器
    local root = lvgl.Object(nil, {
        w = lvgl.HOR_RES(),
        h = lvgl.VER_RES(),
        bg_opa = 0,
        border_width = 0,
        pad_all = 0,
    })
    root:clear_flag(lvgl.FLAG.SCROLLABLE)
    root:add_flag(lvgl.FLAG.EVENT_BUBBLE)
    
    -- 创建图片控件，初始隐藏
    local img = lvgl.Image(root, {
        src = imgPath(IMAGE_FILES[1]),
        x = IMAGE_POSITION.x,
        y = IMAGE_POSITION.y,
    })
    img:add_flag(lvgl.FLAG.HIDDEN)
    
    -- 获取图片尺寸并设置宽高
    local imgWidth, imgHeight = img:get_img_size()
    if imgWidth and imgHeight then
        img:set { w = imgWidth, h = imgHeight }
    end
    
    -- 状态变量
    local currentIndex = 1  -- 当前显示图片索引（1-based）
    local animTimer = nil   -- 动画定时器
    local startTimer = nil  -- 延迟启动定时器
    local isAnimating = false
    local userClosed = false  -- 用户是否手动关闭了动画
    
    -- 更新图片显示
    local function updateImage()
        currentIndex = currentIndex + 1
        if currentIndex > IMAGE_COUNT then
            currentIndex = 1
        end
        img:set { src = imgPath(IMAGE_FILES[currentIndex]) }
    end
    
    -- 开始动画
    local function startAnimation()
        if isAnimating or userClosed then return end
        
        -- 显示图片
        img:clear_flag(lvgl.FLAG.HIDDEN)
        isAnimating = true
        
        -- 创建定时器，每 SWITCH_INTERVAL 毫秒切换图片
        animTimer = lvgl.Timer({
            period = SWITCH_INTERVAL,
            cb = function(t)
                updateImage()
            end
        })
    end
    
    -- 停止动画
    local function stopAnimation()
        if animTimer then
            animTimer:pause()  -- 暂停定时器
            animTimer = nil
        end
        isAnimating = false
        img:add_flag(lvgl.FLAG.HIDDEN)
    end
    
    -- 延迟启动动画
    local function scheduleStart()
        -- 如果已有定时器，先取消
        if startTimer then
            startTimer:pause()
            startTimer = nil
        end
        
        -- 如果用户手动关闭了，不启动
        if userClosed then return end
        
        startTimer = lvgl.Timer({
            period = DELAY_BEFORE_SHOW,
            cb = function(t)
                startAnimation()
                t:pause()  -- 执行后暂停，防止重复
            end
        })
    end
    
    -- 点击图片关闭动画
    img:add_flag(lvgl.FLAG.CLICKABLE)
    img:onevent(lvgl.EVENT.SHORT_CLICKED, function(obj, code)
        -- 停止启动定时器
        if startTimer then
            startTimer:pause()
            startTimer = nil
        end
        -- 停止动画
        stopAnimation()
        -- 标记为用户手动关闭
        userClosed = true
    end)
    
    -- 屏幕状态回调
    local function screenONCb()
        -- 屏幕打开，重置用户关闭标志，重新调度启动
        userClosed = false
        scheduleStart()
    end
    
    local function screenOFFCb()
        -- 屏幕关闭，停止所有定时器和动画
        if startTimer then
            startTimer:pause()
            startTimer = nil
        end
        stopAnimation()
        -- 屏幕关闭时重置用户关闭标志，这样下次亮屏会重新开始
        userClosed = false
    end
    
    -- 初始启动
    scheduleStart()
    
    return screenONCb, screenOFFCb
end

-- 执行主函数
local on, off = entry()

-- 订阅屏幕状态变化
function ScreenStateChangedCB(pre, now, reason)
    if pre ~= "ON" and now == "ON" then
        on()
    elseif pre == "ON" and now ~= "ON" then
        off()
    end
end