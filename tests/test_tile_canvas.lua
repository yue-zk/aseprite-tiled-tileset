-- Run with Aseprite CLI; pass helpers and a fresh output directory via app.params.
local Grid = dofile(app.fs.joinPath(app.params.helpers, "tile_grid.lua"))
local Canvas = dofile(app.fs.joinPath(app.params.helpers, "tile_canvas.lua"))
local output = assert(app.params.output, "pass --script-param output=<directory>")

local grid = Grid.new { tile_width = 4, tile_height = 3, columns = 3, rows = 2, margin = 1, spacing = 2 }
assert(grid.width == 18 and grid.height == 10 and grid.count == 6)
for id = 0, grid.count - 1 do
  local col, row = grid:coords(id)
  local box = grid:rect(id)
  assert(grid:id(col, row) == id)
  local found, x, y = grid:locate(box.x + 3, box.y + 2)
  assert(found == id and x == 3 and y == 2)
end
assert(grid:locate(0, 1) == nil and grid:locate(-1, -1) == nil)
assert(grid:locate(5, 1) == nil and grid:locate(1, 4) == nil)
assert(grid:locate(17, 1) == nil and grid:locate(18, 1) == nil)
assert(not pcall(grid.rect, grid, 6) and not pcall(grid.id, grid, 3, 0))
assert(not pcall(Grid.new, {tile_width = 0, tile_height = 3, columns = 3, rows = 2}))
assert(not pcall(Grid.new, {tile_width = 3, tile_height = 3, columns = 3, rows = 2, spacing = false}))
assert(not pcall(grid.locate, grid, 0.25, 2))

local red = app.pixelColor.rgba(250, 30, 60, 255)
local blue = app.pixelColor.rgba(20, 80, 200, 255)
local translucent = app.pixelColor.rgba(10, 20, 30, 128)
local sprite = Sprite(grid.width, grid.height, ColorMode.RGB)
local canvas = Canvas.new(sprite, grid)
local layer = sprite:newLayer()
layer.name = "Test atlas pixels"
local existing = Image(3, 2, ColorMode.RGB)
existing:drawPixel(0, 0, red)
existing:drawPixel(2, 1, blue)
sprite:newCel(layer, 1, existing, Point(3, 2))
local first = canvas:read_tile(layer, 1, 0)
assert(first.width == 4 and first.height == 3)
assert(first:getPixel(2, 1) == red and first:getPixel(0, 0) == 0)
first:drawPixel(2, 1, blue)
assert(canvas:read_tile(layer, 1, 0):getPixel(2, 1) == red, "read changed the cel")

local ink = Image(4, 3, ColorMode.RGB)
ink:drawPixel(0, 0, translucent)
assert(canvas:write_tile(layer, 1, 0, ink, "overlay"))
local tile = canvas:read_tile(layer, 1, 0)
assert(tile:getPixel(0, 0) == translucent and tile:getPixel(2, 1) == red)
assert(canvas:write_tile(layer, 1, 0, ink, "replace"))
assert(canvas:read_tile(layer, 1, 0):getPixel(2, 1) == 0)
local cel = layer:cel(1)
assert(cel.image:getPixel(5 - cel.position.x, 3 - cel.position.y) == blue, "gutter pixel changed")
assert(not canvas:write_tile(layer, 1, 0, ink, "replace"), "unchanged write should be a no-op")
assert(canvas:write_tile(layer, 1, 5, Canvas.mirror(ink, "x")))
assert(canvas:read_tile(layer, 1, 5):getPixel(3, 0) == translucent)
assert(ink:getPixel(0, 0) == translucent, "mirror changed source")
assert(Canvas.mirror(ink, "y"):getPixel(0, 2) == translucent)
local strip = Canvas.edge(ink, "top", 2, true)
assert(strip.width == 4 and strip.height == 2 and strip:getPixel(3, 0) == translucent)
assert(Canvas.edge(ink, "left", 1, true):getPixel(0, 2) == translucent)
assert(Canvas.edge(ink, "bottom"):getPixel(0, 0) == 0)
assert(Canvas.edge(ink, "right"):getPixel(0, 0) == 0)
assert(not pcall(Canvas.edge, ink, "top", 4))

local other = sprite:newLayer()
assert(not other:cel(1) and canvas:read_tile(other, 1, 5):getPixel(0, 0) == 0)
assert(not canvas:write_tile(other, 1, 1, Image(4, 3, ColorMode.RGB), "overlay"))
assert(not other:cel(1))
assert(canvas:write_tile(other, 1, 1, ink))
assert(canvas:read_tile(layer, 1, 1):getPixel(0, 0) == 0)
other.isEditable = false
assert(not pcall(canvas.write_tile, canvas, other, 1, 0, ink))
assert(not pcall(canvas.write_tile, canvas, layer, 1, 0, Image(3, 3)))
assert(not pcall(canvas.read_tile, canvas, layer, 0, 0))
local group = sprite:newGroup()
local child = sprite:newLayer()
child.parent = group
group.isEditable = false
assert(not pcall(canvas.write_tile, canvas, child, 1, 0, ink))
group.isEditable = true
assert(canvas:write_tile(child, 1, 0, ink))
assert(not pcall(canvas.write_tile, canvas, layer, 1.25, 0, ink))
assert(not pcall(Canvas.edge, ink, "right", 1.25))
-- This fixture is independent of the export test below.
sprite:deleteLayer(group)
local too_small = Sprite(4, 4)
assert(not pcall(Canvas.new, too_small, grid))
assert(not pcall(canvas.read_tile, canvas, too_small.layers[1], 1, 0))
too_small:close()

for _, mode in ipairs({ColorMode.GRAY, ColorMode.INDEXED}) do
  local s = Sprite(grid.width, grid.height, mode)
  if mode == ColorMode.INDEXED then s.transparentColor = 7 end
  local c = Canvas.new(s, grid)
  local target = s:newLayer()
  local data = c:read_tile(target, 1, 1)
  local empty = mode == ColorMode.INDEXED and 7 or 0
  local color = mode == ColorMode.INDEXED and 2 or app.pixelColor.graya(90, 128)
  assert(data:getPixel(0, 0) == empty)
  data:drawPixel(1, 1, color)
  assert(c:write_tile(target, 1, 1, data, "overlay"))
  assert(c:read_tile(target, 1, 1):getPixel(1, 1) == color)
  assert(c:read_tile(target, 1, 1):getPixel(0, 0) == empty)
  s:close()
end

local source = app.fs.joinPath(output, "test-atlas.aseprite")
local png = app.fs.joinPath(output, "test-atlas.png")
local filename = sprite.filename
Canvas.save_atlas(sprite, source, png)
assert(sprite.filename == filename, "save_atlas changed the original filename")
assert(not pcall(Canvas.save_atlas, sprite, source, png), "overwriting should be rejected")
local saved = Sprite { fromFile = source }
assert(#saved.layers == #sprite.layers and saved.width == grid.width and saved.height == grid.height)
assert(Canvas.new(saved, grid):read_tile(saved.layers[2], 1, 5):getPixel(3, 0) == translucent)
local exported = Image { fromFile = png }
assert(exported.width == grid.width and exported.height == grid.height)
assert(exported:getPixel(16, 6) == translucent and exported:getPixel(0, 0) == 0)
saved:close()

sprite:close()

-- A separate document keeps saved-file tests independent of active-frame setup.
local animated = Sprite(grid.width, grid.height, ColorMode.RGB)
app.sprite = animated
local animated_canvas = Canvas.new(animated, grid)
local track = animated.layers[1]
assert(animated_canvas:write_tile(track, 1, 0, ink))
local frame = animated:newEmptyFrame()
assert(frame.frameNumber == 2)
assert(animated_canvas:write_tile(track, 2, 0, Canvas.mirror(ink, "y")))
assert(animated_canvas:read_tile(track, 2, 0):getPixel(0, 2) == translucent)
assert(animated_canvas:read_tile(track, 1, 0):getPixel(0, 2) == 0)
assert(animated_canvas:write_tile(track, 2, 0, ink))
assert(animated_canvas:read_tile(track, 1, 0):getPixel(0, 0) == translucent)
track.isContinuous = true
local linked = animated:newFrame()
assert(linked.frameNumber == 3 and track:cel(2).image == track:cel(3).image, "linked fixture failed")
local wrote, message = pcall(animated_canvas.write_tile, animated_canvas, track, 2, 0, Canvas.mirror(ink, "x"))
assert(not wrote and message:find("linked", 1, true), "writing a linked cel should fail explicitly")
assert(animated_canvas:read_tile(track, 3, 0):getPixel(0, 0) == translucent)
assert(not pcall(Canvas.save_atlas, animated, app.fs.joinPath(output, "many.aseprite"), app.fs.joinPath(output, "many.png")))
animated:close()
print("PASS: TileGrid and TileCanvas coordinate, pixel and Aseprite export contracts")
