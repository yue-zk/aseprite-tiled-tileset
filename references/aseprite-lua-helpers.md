# Aseprite Lua 瓦片辅助库

用于重复性的网格和像素搬运，不决定画什么、不生成 Tiled 地形规则。模块没有材质、格尺寸或项目路径常量；加载模块本身不会打开文件或修改文档。已有素材仅整理时不用加载绘制模块。

## 从脚本调用

- [tile_grid.lua](../scripts/aseprite/tile_grid.lua) 是纯 Lua 5.3+，不依赖 Aseprite。
- [tile_canvas.lua](../scripts/aseprite/tile_canvas.lua) 需要 Aseprite 的 Lua 环境（本机验证环境见 README）；可从脚本或批处理调用，不需要 Tiled、插件、服务或第三方 Lua 包。需要写出图集时，输出目录须已存在且允许写入。

在 Aseprite 批处理中，显式传辅助库目录，不从当前文档猜路径。下面的 `aseprite` 指向 Aseprite 可执行文件；`<OUTPUT>` 换成已经创建的空目录。命令从仓库根目录运行：

```text
aseprite -b --script-param "helpers=scripts/aseprite" --script-param "output=<OUTPUT>" --script examples/mirror-atlas.lua
```

[示例](../examples/mirror-atlas.lua) 画一格 12×8 瓦片，将其镜像到同图层另一槽，再导出可编辑原稿和原尺寸 PNG。把下面几行嵌入自己的绘制脚本即可复用；`sprite` 和 `layer` 必须是调用者明确选择的对象：

```lua
local Grid = dofile(app.fs.joinPath(app.params.helpers, "tile_grid.lua"))
local Canvas = dofile(app.fs.joinPath(app.params.helpers, "tile_canvas.lua"))
local grid = Grid.new { tile_width = 12, tile_height = 8, columns = 2, rows = 1 }
local atlas = Canvas.new(sprite, grid)
local pixels = atlas:read_tile(layer, 1, grid:id(0, 0))
atlas:write_tile(layer, 1, grid:id(1, 0), Canvas.mirror(pixels, "x"), "overlay")
```

## 接口与边界

| 接口 | 约定 |
| --- | --- |
| `Grid.new { tile_width, tile_height, columns, rows, margin?, spacing? }` | 对称边距，统一间距，行优先排列；ID、行列和像素坐标从 0 开始。`width`、`height` 含边距，`count` 是槽位数。网格建成后不要改字段。 |
| `grid:id(col, row)`、`grid:coords(id)`、`grid:rect(id)` | 转换坐标与 ID；`rect` 返回 `{ x, y, width, height }`；槽位越界抛错。 |
| `grid:locate(x, y)` | 图集像素坐标 → `id, local_x, local_y`；边距、间距或图集外返回 `nil`。 |
| `atlas:read_tile(layer, frame, id)` | `frame` 是从 1 开始的现有帧编号。返回独立 `Image`；没有 cel 或局部落在 cel 外时以透明补齐。 |
| `atlas:write_tile(layer, frame, id, image, operation?)` | 默认为 `replace`，透明可擦除；`overlay` 跳过完全透明，半透明像素按原值写入，**不混色**。返回是否改了像素，必要时扩大紧凑 cel，不搬动格外像素。拒绝写入锁定、链接帧、背景、参考或 Tilemap 图层。 |
| `Canvas.mirror(image, "x" / "y")`、`Canvas.edge(image, side, thickness?, reverse?)` | 返回新 `Image`；`x` 左右翻、`y` 上下翻；`side` 取 `top/right/bottom/left`，厚度默认 1，`reverse` 沿截取边的长度翻转。 |
| `Canvas.save_atlas(sprite, aseprite_path, png_path)` | 单帧图集另存为分层 `.aseprite` 并导出 1× `.png`，不改文档文件名，不覆盖已有输出。PNG 按当前可见图层合成；不是动画导出。 |

普通像素层支持 RGB、灰度和索引色。索引色在同一文档／同一调色板语义下原样搬运索引，不会做调色板重映射；读写双方必须同尺寸、同色彩模式，索引色还必须同透明索引。绘制与过渡取舍由调用者做，工具不会擅自改源像素、补图、添加地形规则或替代 Tiled 实刷。

## 运行回归

在 Aseprite CLI 下将示例命令的脚本换成 [tests/test_tile_canvas.lua](../tests/test_tile_canvas.lua)，使用新的空输出目录。测试检查网格、像素、图层偏移、覆盖语义、镜像和原稿／PNG 回读；不会写仓库内的样例。
