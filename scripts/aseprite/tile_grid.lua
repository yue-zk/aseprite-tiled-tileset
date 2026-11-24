-- Pure Lua grid for row-major, zero-based atlas slots.
local Grid = {}
Grid.__index = Grid

local function integer(value, name, minimum)
  local n = type(value) == "number" and math.tointeger(value)
  -- Some embedded Lua builds coerce fractional values even in mixed numeric comparisons.
  assert(n and value % 1.0 == 0.0 and (minimum == nil or n >= minimum), name .. " must be a valid integer")
  return n
end

function Grid.new(options)
  assert(type(options) == "table", "grid options are required")
  local w = integer(options.tile_width, "tile_width", 1)
  local h = integer(options.tile_height, "tile_height", 1)
  local cols = integer(options.columns, "columns", 1)
  local rows = integer(options.rows, "rows", 1)
  local margin = integer(options.margin == nil and 0 or options.margin, "margin", 0)
  local spacing = integer(options.spacing == nil and 0 or options.spacing, "spacing", 0)
  -- Keep arithmetic exact in Lua and dimensions usable by signed 32-bit image APIs.
  local width = 2.0 * margin + 1.0 * cols * w + (cols - 1.0) * spacing
  local height = 2.0 * margin + 1.0 * rows * h + (rows - 1.0) * spacing
  assert(width <= 2147483647 and height <= 2147483647 and 1.0 * cols * rows <= 2147483647,
    "grid dimensions or slot count are too large")
  return setmetatable({
    tile_width = w, tile_height = h, columns = cols, rows = rows,
    margin = margin, spacing = spacing, count = cols * rows,
    width = math.tointeger(width), height = math.tointeger(height),
  }, Grid)
end

function Grid:id(column, row)
  local c = integer(column, "column", 0)
  local r = integer(row, "row", 0)
  assert(c < self.columns and r < self.rows, "slot coordinates outside grid")
  return r * self.columns + c
end

function Grid:coords(id)
  local i = integer(id, "tile id", 0)
  assert(i < self.count, "tile id outside grid")
  return i % self.columns, i // self.columns
end

function Grid:rect(id)
  local col, row = self:coords(id)
  return {
    x = self.margin + col * (self.tile_width + self.spacing),
    y = self.margin + row * (self.tile_height + self.spacing),
    width = self.tile_width,
    height = self.tile_height,
  }
end

-- Returns the id and tile-local xy, or nil for gutters, margins and outside pixels.
function Grid:locate(x, y)
  x = integer(x, "x")
  y = integer(y, "y")
  if x < self.margin or y < self.margin or
    x >= self.width - self.margin or y >= self.height - self.margin then return nil end
  local sx, sy = self.tile_width + self.spacing, self.tile_height + self.spacing
  local dx, dy = x - self.margin, y - self.margin
  local lx, ly = dx % sx, dy % sy
  if lx >= self.tile_width or ly >= self.tile_height then return nil end
  return self:id(dx // sx, dy // sy), lx, ly
end

return Grid
