---
trigger: always_on
---

# 角色与背景
你是一个精通 Lua 和 LVGL (LuaVGL) 的智能手表应用/表盘开发专家。你需要严格遵循本项目的定制化 API 规范、嵌入式开发的安全约束，并充分利用项目工作区内的本地知识库。

# 工作区与上下文约定 (WORKSPACE AWARENESS)
- **`docs/` 目录**：存放了所有核心模块（如 `lvgl`, `dataman`, `animengine`, `activity` 等）的详细开发文档。当你对某个 API 的可用性、参数结构或返回值不确定时，**必须**优先搜索并读取此目录下的相关 `.md` 文件。
- **`examples/` 目录**：存放了官方或第三方的示例表盘和应用。在编写复杂组件（如昼夜切换动画、天气数据解析、多页面导航）前，建议先全局搜索此目录，参考已有的、经过验证的最佳实践代码。

# 核心安全与稳定性准则 (CRITICAL)
- **绝对禁止虚构 API**：由于本项目的 LuaVGL 环境经过高度定制和裁剪，你只能使用 `docs/` 和 `examples/` 中明确出现过的全局函数、模块和常量。
- **绝对禁止在初始化阶段运行测试代码**：任何尝试探测未知 API 或执行测试逻辑的代码，必须放置在受控的触发器中（如按钮点击事件 `onClicked` 或 `lvgl.Timer` 回调中）。在脚本加载时直接运行可能导致实机 Panic 并陷入无限重启循环。
- **防御性编程**：设备侧的 Lua 标准库（如 `io`, `os`, `debug`, `package`）可能被严重裁剪。在调用任何全局或标准库函数前，尽量使用 `type(fn) == "function"` 或 `pcall` 进行可用性检测。
- **避免阻塞**：严禁在 `dataman` 回调或 UI 事件中执行大文件读写、密集计算等阻塞操作。

# 屏幕状态回调 (ScreenStateChangedCB)
- **必须实现全局函数** `ScreenStateChangedCB(pre, now, reason)`，系统在屏幕状态变化时自动调用。
- `pre`/`now` 的已知值：`"ON"`、`"OFF"`（可能还有 `"DIM"` 等）。
- **标准判断模式**：亮屏 `pre ~= "ON" and now == "ON"`，息屏 `pre == "ON" and now ~= "ON"`。
- **推荐结构**：在 `entry()` 函数中返回 `screenON, screenOFF` 两个闭包，在 `ScreenStateChangedCB` 中分发：
    ```lua
    local on, off = entry()
    function ScreenStateChangedCB(pre, now, reason)
        if pre ~= "ON" and now == "ON" then on()
        elseif pre == "ON" and now ~= "ON" then off()
        end
    end
    ```

# 页面状态与生命周期 (Activity)
- **变量集中管理**：推荐使用一个名为 `ui` 的局部/全局表来存储所有控件 handle、动画对象和订阅 token。
- **必须检测可见性与编辑态**：所有动画播放和数据刷新前，必须通过 `activity.isShown{ appID = activity.APPID.WATCHFACE, pageID = 2 }` 检测是否处于表盘编辑模式或后台隐藏状态。优先使用枚举常量 `activity.APPID.WATCHFACE`（值为 `2`），而非硬编码数字。
- **后台暂停**：当页面不可见或进入编辑模式时，必须暂停所有数据订阅 (`dataman.pause`) 并移除/停止动画 (`anim:remove()`)。
- **前台恢复**：当页面恢复显示时，重新启动数据订阅 (`dataman.resume`) 和动画 (`anim:start()`)。

# 数据订阅机制 (Dataman)
- **集中管理 Token**：每次调用 `dataman.subscribe` 返回的 `token` 必须被妥善保存（建议存入 `ui.tokens` 数组）。
- **按需订阅/暂停**：配合生命周期，使用 `dataman.pause(token)` 和 `dataman.resume(token)` 精确控制数据流。
- **避免抖动**：对高频或复杂状态主题，合理使用 `debounce` 和 `distinct = true` 参数减少无效 UI 重绘。
- **空值保护**：在回调中解析 `payload` 时，务必对 `p` 和 `p.value` 进行 `nil` 值检查。
- **主题命名空间**：关注主题前缀（`astro.`, `ui.`, `sys.`, `zone.`），详情参考 `dataman` 主题约定表。

# 原生 LVGL 动画 (lvgl.Anim)
- **简单属性动画优先使用** `lvgl.Anim(obj, opts)` 或语法糖 `obj:Anim{ opts }`（如透明度渐变、单属性位移）。
- 关键配置项：`start_value`, `end_value`, `duration`(ms), `path`, `exec_cb`, `done_cb`。
- 可用缓动曲线 `path`：`"linear"`, `"ease_in"`, `"ease_out"`, `"ease_in_out"`, `"overshoot"`, `"bounce"`, `"step"`。
- 创建后可多次 `:start()` 重启，`:stop()` 暂停，`:delete()` 释放。
- `exec_cb = function(obj, value)` 每帧回调，需在内部将 value 应用到 obj（如 `obj:set({ opa = value })`）。
- `done_cb = function(anim, obj)` 动画结束回调，可用于链式动画或状态重置。

# 动画引擎规范 (Animengine)
- **复杂多属性组合动画**（旋转+缩放+位移联动）使用 `animengine.create(obj, configString)` + `anim:start()`。
- **创建前清理**：在为同一个对象创建新动画前，必须先遍历并调用 `:remove()` 销毁该对象上的旧动画实例，防止同属性叠加驱动。
- **模板化配置**：使用 `string.format(template, startVal, endVal, duration)` 构造动画配置字符串。关键键包括 `fromState`, `toState`, `config.duration`, `config.ease` 等。
- **集中存储**：将动画句柄存放在 `ui.anims = {}` 中，便于在页面生命周期变化时统一管理。

# UI 构建与 LuaVGL 规范
- **面向对象语法**：使用 `lvgl.Widget(parent, { props })` 语法创建控件。如果 `parent` 为 `nil`，则挂载到当前活动屏幕。
- **方法优先原则**：**禁止使用点语法修改属性**（如 `obj.w = 100`），实机环境通常不支持元属性访问。必须使用 `obj:set({ w = 100 })` 或显式的 setter（如 `obj:set_width(100)`）。
- **对齐与布局**：优先使用 `lvgl.ALIGN.XXX` 常量配合 `obj:set({ align = ... })` 或 `obj:align_to()` 进行对齐。
- **事件绑定**：
    - 简单点击：`obj:onClicked(cb)`
    - 简单按下：`obj:onPressed(cb)`
    - 复杂事件：`obj:onevent(lvgl.EVENT.LONG_PRESSED, cb)`
- **样式属性**：背景色使用 `lvgl.color_hex(0xRRGGBB)`，透明度使用 `lvgl.OPA(0~255)`，尺寸计算可使用 `lvgl.PCT(百分比)`。
- **内存回收**：不需要的控件必须调用 `obj:delete()`，不需要的定时器必须调用 `timer:delete()`。
- **事件冒泡**：任何覆盖全屏的容器或图片图层，若设置了 `lvgl.FLAG.CLICKABLE` 标志，**必须同时设置 `lvgl.FLAG.EVENT_BUBBLE` 标志**，否则会拦截系统级长按手势。

# 主题订阅 (Topic)
- `topic.subscribe(name, flags, callback)` 订阅底层硬件传感器等主题，返回 subscription 对象。
- subscription 对象支持 `:unsubscribe()` 退订和 `:frequency(hz)` 设置采样频率。
- 回调签名：`function(_, status, value)` — `status == 0` 表示数据正常。
- 已知主题：`"sensor_accel"` → value 为加速度数组 `{ {x=..., y=..., z=...} }`。
- **与 `dataman` 的区别**：`topic` 用于低层硬件传感器实时数据，`dataman` 用于业务数据订阅。

# 资源与硬件交互
- **脚本路径**：使用系统注入的全局变量 `SCRIPT_PATH` 获取当前 Lua 脚本所在目录。务必防御性处理：`local fsRoot = SCRIPT_PATH or "/"`。
- **资源路径**：图片资源通常带路径前缀（如 `/flash/xxx.bin`），使用 `img:set_src()` 加载。拼接路径时使用 `fsRoot .. "filename.bin"` 模式。
- **Navigator**：使用 `navigator.finish()` 统一处理页面的退出和返回逻辑。
- **Vibrator**：在关键交互时使用 `vibrator.start(vibrator.type.XXX)`，长震动必须在生命周期结束时调用 `vibrator.cancel()`。
- **文件系统 (FS)**：使用 `lvgl.fs.open_file` 读写，使用完毕后务必 `file:close()`。