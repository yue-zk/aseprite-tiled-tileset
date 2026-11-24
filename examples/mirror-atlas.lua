-- A small standalone example: draw one tile, mirror it, and export both formats.
local helper_dir = assert(app.params.helpers, "pass --script-param helpers=<directory>")
local output_dir = assert(app.params.output, "pass --script-param output=<directory>")
local Grid = dofile(app.fs.joinPath(helper_dir, "tile_grid.lua"))
local Canvas = dofile(app.fs.joinPath(helper_dir, "tile_canvas.lua"))

local grid = Grid.new { tile_width = 12, tile_height = 8, columns = 2, rows = 1, margin = 1, spacing = 2 }
local sprite = Sprite(grid.width, grid.height, ColorMode.RGB)
local layer = sprite.layers[1]
layer.name = "Lines"
local canvas = Canvas.new(sprite, grid)
local tile = canvas:read_tile(layer, 1, 0)
local ink = app.pixelColor.rgba(75, 174, 210, 255)
for y = 1, 6 do
  for x = 1, y + 1 do tile:drawPixel(x, y, ink) end
end
canvas:write_tile(layer, 1, 0, tile)
canvas:write_tile(layer, 1, 1, Canvas.mirror(tile, "x"))
Canvas.save_atlas(sprite, app.fs.joinPath(output_dir, "mirror-atlas.aseprite"),
  app.fs.joinPath(output_dir, "mirror-atlas.png"))
sprite:close()
print("Exported mirror-atlas.aseprite and mirror-atlas.png")
