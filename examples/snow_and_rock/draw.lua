-- Example-specific art direction; grid and image operations use the shared library.
local helpers = assert(app.params.helpers, "pass helpers=<directory>")
local output = assert(app.params.output, "pass output=<existing empty directory>")
local Grid = dofile(app.fs.joinPath(helpers, "tile_grid.lua"))
local Canvas = dofile(app.fs.joinPath(helpers, "tile_canvas.lua"))

local manifest = assert(io.open(assert(app.params.manifest, "pass manifest=<tiles.tsv>"), "r"))
local width, height, columns = (manifest:read("*l") or ""):match("^grid\t(%d+)\t(%d+)\t(%d+)\r?$")
width, height, columns = tonumber(width), tonumber(height), tonumber(columns)
assert(width and width >= 2 and height >= 2 and columns >= 1, "invalid grid header")
local header = (manifest:read("*l") or ""):gsub("\r$", "")
assert(header == "id\ttop_left\ttop_right\tbottom_right\tbottom_left", "unexpected manifest columns")
local entries, seen = {}, {}
for line in manifest:lines() do
  local id, a, b, c, d = line:match("^(%d+)\t([012])\t([012])\t([012])\t([012])\r?$")
  assert(id and tonumber(id) == #entries, "expected contiguous zero-based IDs and four valid corner values")
  local key = a .. b .. c .. d
  assert(key ~= "0000" and not seen[key], "all-blank or duplicate signature: " .. key)
  seen[key] = true
  entries[#entries + 1] = {tonumber(a), tonumber(b), tonumber(c), tonumber(d)}
end
manifest:close()
assert(#entries == 80, "expected every non-empty snow/rock corner combination")

local grid = Grid.new {
  tile_width = width, tile_height = height, columns = columns,
  rows = (#entries + columns - 1) // columns,
}
local sprite = Sprite(grid.width, grid.height, ColorMode.RGB)
sprite.gridBounds = Rectangle(0, 0, width, height)
local rock_layer = sprite.layers[1]
rock_layer.name = "岩地 · 冷灰层理"
local snow_layer = sprite:newLayer()
snow_layer.name = "雪地 · 冰蓝阴影"
local canvas = Canvas.new(sprite, grid)
local function color(hex)
  return app.pixelColor.rgba((hex >> 16) & 255, (hex >> 8) & 255, hex & 255, 255)
end
local snow = {color(0xa6cddd), color(0xc4e0e9), color(0xdbeef0), color(0xebf7f2), color(0xf9fff7)}
local rock = {color(0x344453), color(0x465867), color(0x526777), color(0x607583), color(0x7e9098)}

local function draw_tiles(corners)
  local snowfall = Image(width, height, ColorMode.RGB)
  local bedrock = Image(width, height, ColorMode.RGB)
  local far_x, far_y = width - 1, height - 1
  local area = far_x * far_y
  local scores = {[0] = 0, 0, 0}
  for y = 0, far_y do
    for x = 0, far_x do
      scores[0], scores[1], scores[2] = 0, 0, 0
      local left, upper = far_x - x, far_y - y
      local weights = {left * upper, x * upper, x * y, left * y}
      for index, material in ipairs(corners) do
        scores[material] = scores[material] + weights[index]
      end
      -- Opposite tile borders sample the same coordinates and only the shared corners.
      local tx, ty = x % far_x, y % far_y
      local noise = (tx * 83 + ty * 71 + tx * ty * 29 + tx * tx * 11 + ty * ty * 7) % 97
      local band = (tx + ty * 3 + noise // 20) % 13
      local material = 0
      for candidate = 1, 2 do
        if scores[candidate] > scores[material] then material = candidate end
      end
      if material == 1 then
        local rival = math.max(scores[0], scores[2])
        local level = rival * 2 > area and 1
          or ((scores[1] - rival) * 4 < area and 2
          or (noise < 8 and 5 or band < 2 and 3 or 4))
        snowfall:drawPixel(x, y, snow[level])
      elseif material == 2 then
        local level = (scores[2] - math.max(scores[0], scores[1])) * 7 < area and 1
          or (band < 3 and 2 or band > 10 and 4 or noise < 10 and 5 or 3)
        bedrock:drawPixel(x, y, rock[level])
      end
    end
  end
  return snowfall, bedrock
end

for index, corners in ipairs(entries) do
  local snow_pixels, rock_pixels = draw_tiles(corners)
  canvas:write_tile(snow_layer, 1, index - 1, snow_pixels)
  canvas:write_tile(rock_layer, 1, index - 1, rock_pixels)
end
Canvas.save_atlas(sprite, app.fs.joinPath(output, "tiles.aseprite"), app.fs.joinPath(output, "tiles.png"))
sprite:close()
print(string.format("Exported %d snow/rock tiles (%dx%d each)", #entries, width, height))
