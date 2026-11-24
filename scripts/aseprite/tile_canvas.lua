-- Aseprite Lua helpers for regular atlases on ordinary pixel layers.
local Canvas = {}
Canvas.__index = Canvas

local function empty_image(sprite, width, height)
  local spec = sprite.spec
  spec.width, spec.height = width, height
  -- Image(spec) is normally initialized to zero, not necessarily the palette mask.
  local image = Image(spec)
  if spec.colorMode == ColorMode.INDEXED and spec.transparentColor ~= 0 then
    for pixel in image:pixels() do pixel(spec.transparentColor) end
  end
  return image
end

local function is_transparent(pixel, mode, mask)
  if mode == ColorMode.INDEXED then return pixel == mask end
  if mode == ColorMode.GRAY then return app.pixelColor.grayaA(pixel) == 0 end
  return app.pixelColor.rgbaA(pixel) == 0
end

local function copy_pixels(dst, src, from_x, from_y, width, height, to_x, to_y)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      dst:drawPixel(to_x + x, to_y + y, src:getPixel(from_x + x, from_y + y))
    end
  end
end

function Canvas.new(sprite, grid)
  assert(sprite and grid and type(grid.rect) == "function", "sprite and TileGrid are required")
  assert(grid.width <= sprite.width and grid.height <= sprite.height, "grid does not fit sprite canvas")
  local mode = sprite.colorMode
  assert(mode == ColorMode.RGB or mode == ColorMode.GRAY or mode == ColorMode.INDEXED,
    "unsupported sprite color mode")
  return setmetatable({ sprite = sprite, grid = grid }, Canvas)
end

local function check_target(canvas, layer, frame, writing)
  assert(layer and layer.sprite == canvas.sprite and layer.isImage and not layer.isTilemap,
    "expected a pixel layer of this sprite")
  assert(not layer.isBackground and not layer.isReference,
    "expected a normal non-background, non-reference pixel layer")
  assert(type(frame) == "number" and frame % 1.0 == 0.0 and frame >= 1 and
    frame <= #canvas.sprite.frames, "frame must be an existing one-based frame number")
  assert(canvas.grid.width <= canvas.sprite.width and canvas.grid.height <= canvas.sprite.height,
    "grid no longer fits sprite canvas")
  if writing then
    local function editable(layers, parent_editable)
      for _, item in ipairs(layers) do
        local unlocked = parent_editable and item.isEditable
        if item == layer then return unlocked end
        if item.isGroup then
          local nested = editable(item.layers, unlocked)
          if nested ~= nil then return nested end
        end
      end
    end
    assert(editable(canvas.sprite.layers, true), "target layer or parent group is locked")
  end
  return layer:cel(frame)
end

-- Returns a detached, tile-sized Image; pixels outside the cel are transparent.
function Canvas:read_tile(layer, frame, id)
  local cel = check_target(self, layer, frame, false)
  local rect = self.grid:rect(id)
  local out = empty_image(self.sprite, rect.width, rect.height)
  if not cel then return out end

  local image, pos = cel.image, cel.position
  local x1, y1 = math.max(rect.x, pos.x), math.max(rect.y, pos.y)
  local x2 = math.min(rect.x + rect.width, pos.x + image.width)
  local y2 = math.min(rect.y + rect.height, pos.y + image.height)
  if x1 < x2 and y1 < y2 then
    copy_pixels(out, image, x1 - pos.x, y1 - pos.y, x2 - x1, y2 - y1, x1 - rect.x, y1 - rect.y)
  end
  return out
end

-- Replaces exact pixel values; "overlay" skips only fully transparent pixels.
-- This deliberately does not blend, unlink cels, or move other layers/frames.
function Canvas:write_tile(layer, frame, id, image, operation)
  if operation == nil then operation = "replace" end
  assert(operation == "replace" or operation == "overlay", "expected replace or overlay")
  local cel = check_target(self, layer, frame, true)
  local rect = self.grid:rect(id)
  assert(image and image.width == rect.width and image.height == rect.height,
    "source image must match the tile size")
  local spec = self.sprite.spec
  local mask, mode = spec.transparentColor, spec.colorMode
  assert(image.colorMode == mode, "source image color mode must match the sprite")
  assert(mode ~= ColorMode.INDEXED or image.spec.transparentColor == mask,
    "source image must use the same transparent palette index")

  local current, pos
  if cel then
    current, pos = cel.image, cel.position
    for _, other in ipairs(layer.cels) do
      assert(other.frameNumber == frame or other.image ~= current,
        "target cel is linked; unlink it explicitly before writing")
    end
  end

  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  local changes = {}
  local clear = mode == ColorMode.INDEXED and mask or 0
  for y = 0, rect.height - 1 do
    for x = 0, rect.width - 1 do
      local pixel = image:getPixel(x, y)
      local transparent = is_transparent(pixel, mode, mask)
      if operation == "replace" or not transparent then
        local gx, gy = rect.x + x, rect.y + y
        local within = current and gx >= pos.x and gy >= pos.y and
          gx < pos.x + current.width and gy < pos.y + current.height
        local before = within and current:getPixel(gx - pos.x, gy - pos.y) or clear
        if before ~= pixel and (within or not transparent) then
          changes[#changes + 1] = { gx, gy, pixel }
          x1, y1 = math.min(x1, gx), math.min(y1, gy)
          x2, y2 = math.max(x2, gx + 1), math.max(y2, gy + 1)
        end
      end
    end
  end
  if #changes == 0 then return false end

  if current then
    x1, y1 = math.min(pos.x, x1), math.min(pos.y, y1)
    x2, y2 = math.max(pos.x + current.width, x2), math.max(pos.y + current.height, y2)
  end
  local out = empty_image(self.sprite, x2 - x1, y2 - y1)
  if current then copy_pixels(out, current, 0, 0, current.width, current.height, pos.x - x1, pos.y - y1) end
  for _, change in ipairs(changes) do out:drawPixel(change[1] - x1, change[2] - y1, change[3]) end
  local function apply()
    if cel then
      cel.image = out
      if pos.x ~= x1 or pos.y ~= y1 then cel.position = Point(x1, y1) end
    else
      self.sprite:newCel(layer, frame, out, Point(x1, y1))
    end
  end
  -- A batch sprite can be active without an editor transaction context.
  if app.isUIAvailable and app.sprite == self.sprite then app.transaction("Write atlas tile", apply) else apply() end
  return true
end

function Canvas.mirror(image, axis)
  assert(axis == "x" or axis == "y", "mirror axis must be x or y")
  local out = Image(image.spec)
  for y = 0, image.height - 1 do
    for x = 0, image.width - 1 do
      local sx = axis == "x" and image.width - 1 - x or x
      local sy = axis == "y" and image.height - 1 - y or y
      out:drawPixel(x, y, image:getPixel(sx, sy))
    end
  end
  return out
end

-- Extracts a detached edge strip. Reverse mirrors along the length of the edge.
function Canvas.edge(image, side, thickness, reverse)
  local horizontal = side == "top" or side == "bottom"
  assert(horizontal or side == "left" or side == "right", "invalid edge side")
  if thickness == nil then thickness = 1 end
  assert(type(thickness) == "number" and thickness % 1.0 == 0.0 and thickness >= 1 and
    thickness <= (horizontal and image.height or image.width), "edge thickness outside image")
  local w, h = horizontal and image.width or thickness, horizontal and thickness or image.height
  local x = side == "right" and image.width - w or 0
  local y = side == "bottom" and image.height - h or 0
  local spec = image.spec
  spec.width, spec.height = w, h
  local out = Image(spec)
  copy_pixels(out, image, x, y, w, h, 0, 0)
  return reverse and Canvas.mirror(out, horizontal and "x" or "y") or out
end

-- Save copies; never overwrite existing files, change the active path or scale the atlas.
function Canvas.save_atlas(sprite, source_path, png_path)
  assert(#sprite.frames == 1, "atlas export requires one frame")
  local function check(path, extension)
    assert(type(path) == "string" and path:lower():sub(-#extension) == extension,
      "expected output path ending in " .. extension)
    assert(not app.fs.isFile(path) and not app.fs.isDirectory(path), "output already exists: " .. path)
    local parent = app.fs.filePath(app.fs.normalizePath(path))
    assert(app.fs.isDirectory(parent == "" and "." or parent), "output directory does not exist: " .. path)
  end
  check(source_path, ".aseprite")
  check(png_path, ".png")
  sprite:saveCopyAs(source_path)
  assert(app.fs.isFile(source_path), "Aseprite source save failed: " .. source_path)
  sprite:saveCopyAs(png_path)
  assert(app.fs.isFile(png_path), "PNG export failed: " .. png_path)
end

return Canvas
