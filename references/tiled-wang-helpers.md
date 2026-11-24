# Tiled Wang 规则辅助库

[wang.py](../scripts/tiled/wang.py) 是供 AI 和其他脚本直接导入的 Python 模块，不是完整素材转换器。需要 **Python 3.10+**，只用标准库；读取、比较和修改内存中的 XML 不需要安装 Aseprite 或 Tiled。实际刷图验收仍按技能入口执行。

## 先声明要支持的接边

以 `corner`、`edge` 或 `mixed` 明确指定地形集类型。八槽顺序固定为 `top, top_right, right, bottom_right, bottom, bottom_left, left, top_left`。`pack_slots` 要求提供全部有效槽位，避免把漏写误当空白；非有效槽由函数补 0。0 表示未标注触点，只有像素和设计都确实要求透明时才把它作为接空白来验。全零不属于有内容的图块标注。

```python
from scripts.tiled.wang import format_wangid, pack_slots, parse_wangid, unpack_slots

contact = pack_slots("corner", {
    "top_right": 1, "bottom_right": 2, "bottom_left": 0, "top_left": 1,
})
text = format_wangid("corner", contact)  # 0,1,0,2,0,0,0,1
assert unpack_slots("corner", parse_wangid("corner", text))["bottom_right"] == 2
```

## 查缺项，不自动补图

在仓库根目录运行 Python，从某个具体 `<wangset>` 读出本地 tile ID 和签名，再与要求对照。这里只查传入的 `expected`。如果只承诺若干接边，传这些签名，不要调用全组合生成。只有明确承诺材质自由交汇时才用 `full_signatures`；Mixed Set 有八个有效槽位，组合数增长很快。

```python
from xml.etree import ElementTree as ET
from scripts.tiled.wang import compare_coverage, full_signatures, read_assignments, unpack_slots

root = ET.parse("assets/grass-and-dirt/tiles.tsx").getroot()
terrain = root.find("wangsets/wangset")  # 此样例只有一个集；多集时须指定并核对目标集
kind = terrain.attrib["type"]
actual = read_assignments(terrain)
expected = full_signatures(kind, [0, 1, 2, 3])  # 只因该样例明确承诺四种状态全组合
report = compare_coverage(kind, expected, actual)
for signature in report.missing:
    print(unpack_slots(kind, signature))
```

`missing` 是要求中缺少的签名；`extra` 是范围外签名，只供检查，不自动删除；`variants` 列出同签名的多个本地 tile ID，允许多个外观变体。一个 ID 在同一集里出现两次则是冲突。覆盖率不判断图像是否真的画对，也不模拟笔刷。

## 对现有 TSX 做局部更新

调用 `patch_assignments(tileset, set_name, {tile_id: signature, ...})`。地形集需已经存在且名字唯一，颜色顺序沿用该集；图块 ID 必须是 TSX 本地 ID，不是 TMX GID。传 `None` 仅删除明确指定且已存在的标注。多次出现相同签名是正常变体，不用覆盖其他图块。接口接受逐格确认后得到的签名，不从像素推断。

函数返回一棵新的 `<tileset>` XML 树，**不改输入，不写文件**。只有目标集内指定标注被改动；图块属性、动画、图片引用、调色板和其他集保留。调用者自行决定是否另存、审阅差异及验证资源的相对路径。需要保留 XML 注释或处理指令时，先用 `ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))` 读取；函数保证树级保留，不保证 XML 文本逐字节相同。

## 运行回归

```text
python3 -B -m unittest discover -s tests -p test_wang.py -v
```

测试含 Corner/Edge/Mixed 的不对称槽位、局部需求、变体、无效标注、稀疏图块集、局部更新保留，以及随附样例的 255 个非全零签名。不需要 GUI，不能替代 Tiled 从空白起刷的验收。
