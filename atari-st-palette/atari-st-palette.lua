--[[
  Atari ST Palette Editor for Aseprite
  =====================================
  Edit the first 16 colors of the current sprite's palette using
  Atari ST-style 3-bit RGB sliders (0-7 per channel).

  The Atari ST 512-color mode uses 3 bits per channel (R:3 G:3 B:3),
  producing 512 possible colors. This plugin maps those values to
  the full Aseprite 8-bit palette (0-255 per channel).

  Features:
    - 4×4 color swatch grid — click a swatch to select it and open
      the Aseprite color picker, or use the R/G/B sliders
    - Single shared R, G, B sliders (0-7) that edit the selected slot
    - Real-time palette preview as sliders are dragged
    - "Skip first" mode: map slots to palette indices 1-16
    - "Stretch" mode: full-range 8-bit conversion vs simple shift
    - STE mode: switch to 4-bit-per-channel (0-15, 4096 colors)
    - 3-bit hex display for the selected slot (e.g., "777" = full white)
]]

-- ================================================================
-- API Version Guard
-- ================================================================

if app.apiVersion < 21 then
  return app.alert("This script requires Aseprite v1.3 or later")
end

-- ================================================================
-- State
-- ================================================================

local selectedSlot = 0
local stretchEnabled = true
local skipFirstEnabled = false
local steEnabled = false
local updating = false

-- Per-slot 3-bit color values (source of truth for display)
-- Keyed by slot number (0-15), NOT palette index
local slotColors3bit = {}

-- ================================================================
-- Helper Functions
-- ================================================================

--- Convert a 3-bit value (0-7) to an 8-bit value (0-255).
--- When stretch is enabled, uses full-range bit replication:
---   0 -> 0, 7 -> 255
--- When disabled, uses a simple left shift:
---   0 -> 0, 7 -> 224
--- @param v integer 0-7
--- @return integer 0-255
local function bit3to8(v, stretch)
  if steEnabled then
    -- 4-bit (STE): 0-15 → 0-255
    if stretch then
      return (v << 4) | v  -- replicate nibble: 15 → 255
    end
    return v << 4  -- 15 → 240
  end
  -- 3-bit (ST): 0-7 → 0-255
  if stretch then
    return (v << 5) | (v << 2) | (v >> 1)
  end
  return v << 5
end

--- Convert an 8-bit value (0-255) back to a 3-bit value (0-7).
--- Rounds to the nearest 3-bit representation.
--- @param v integer 0-255
--- @return integer 0-7
local function bit8to3(v)
  if steEnabled then
    return math.floor(v * 15 / 255 + 0.5)
  end
  return math.floor(v * 7 / 255 + 0.5)
end

--- Format three 3-bit values as a single lowercase hex string.
--- Example: rgb3hex(7, 0, 3) -> "703"
--- @param r integer 0-7
--- @param g integer 0-7
--- @param b integer 0-7
--- @return string 3-char hex
local function rgb3hex(r, g, b)
  return "$" .. string.format("%x%x%x", r, g, b)
end

--- Map a UI slot number (0-15) to the actual palette index,
--- accounting for the skip-first toggle.
--- @param slot integer 0-15
--- @return integer palette index
local function slotToIndex(slot)
  if skipFirstEnabled then
    return slot + 1
  end
  return slot
end

--- Read all 16 palette entries into the slotColors3bit table.
--- Called at startup and when skip-first toggles.
--- @param pal Palette
local function initSlotColors(pal)
    for slot = 0, 15 do
        local idx = slotToIndex(slot)
        local color = pal:getColor(idx)
        if color then
            slotColors3bit[slot] = {
                r = bit8to3(color.red),
                g = bit8to3(color.green),
                b = bit8to3(color.blue)
            }
        else
            slotColors3bit[slot] = { r = 0, g = 0, b = 0 }
        end
    end
end

-- ================================================================
-- Canvas Geometry
-- ================================================================

local CANVAS_W = 252
local CANVAS_H = 188
local SWATCH_W = 60
local SWATCH_H = 44
local SWATCH_GAP = 4
-- Helper: rectangle for a palette slot in the swatch grid
local function slotRect(slot)
  local col = slot % 4
  local row = math.floor(slot / 4)
  return Rectangle(
    col * (SWATCH_W + SWATCH_GAP),
    row * (SWATCH_H + SWATCH_GAP),
    SWATCH_W, SWATCH_H
  )
end

-- Helper: find which slot contains a point (canvas coords)
local function slotAtPoint(x, y)
  for slot = 0, 15 do
    if slotRect(slot):contains(Point(x, y)) then
      return slot
    end
  end
  return nil
end

-- Canvas mouse state
local hoveredSlot = nil

-- ================================================================
-- Dialog Update Functions
-- ================================================================

--- Read the selected slot's palette color, convert to 3-bit, and
--- update the sliders and selected label. Does NOT write to palette.
--- @param dlg Dialog
--- @param pal Palette
local function refreshSliders(dlg, pal)
  local idx = slotToIndex(selectedSlot)
  local c = slotColors3bit[selectedSlot]
  local r3, g3, b3 = 0, 0, 0
  if c then
    r3, g3, b3 = c.r, c.g, c.b
  end

  dlg:modify{ id = "s_r", value = r3 }
  dlg:modify{ id = "s_g", value = g3 }
  dlg:modify{ id = "s_b", value = b3 }

  dlg:modify{ id = "selLabel", text = string.format("Selected: %2d: %s", idx, rgb3hex(r3, g3, b3)) }
end

--- Write the current slider values for the selected slot to the
--- palette, then refresh the button labels, shades, and selected label.
--- @param dlg Dialog
--- @param pal Palette
local function writeSelectedSlot(dlg, pal)
  local r3 = dlg.data.s_r or 0
  local g3 = dlg.data.s_g or 0
  local b3 = dlg.data.s_b or 0
  local idx = slotToIndex(selectedSlot)

  -- Store the 3-bit value (source of truth)
  slotColors3bit[selectedSlot] = { r = r3, g = g3, b = b3 }

  -- Convert to 8-bit using current stretch setting
  local r8 = bit3to8(r3, stretchEnabled)
  local g8 = bit3to8(g3, stretchEnabled)
  local b8 = bit3to8(b3, stretchEnabled)

  pal:setColor(idx, Color{ r = r8, g = g8, b = b8, a = 255 })

  dlg:repaint()

  -- Update the selected label
  dlg:modify{ id = "selLabel", text = string.format("Selected: %2d: %s", idx, rgb3hex(r3, g3, b3)) }
end

-- ================================================================
-- Main Entry Point
-- ================================================================

local sprite = app.activeSprite
if not sprite then
  app.alert("No active sprite")
  return
end

local pal = sprite.palettes[1]

-- Ensure the palette has at least 17 entries (indices 0-16) so that
-- both modes (skip-first on/off) can read and write safely.
local ok, err = pcall(function()
  pal:resize(17)
end)
if not ok then
  -- If resize fails, we may still be able to edit existing colors
  -- Only abort if the palette is too small
  if #pal < 17 then
    app.alert("Could not resize palette: " .. tostring(err))
    return
  end
end

-- ================================================================
-- Build Dialog
-- ================================================================

local dlg = Dialog("Atari ST Palette Editor")

-- Skip first checkbox
dlg:check{
  id = "skipFirst",
  text = "Skip palette index 0 (show indices 1–16)",
  selected = skipFirstEnabled,
  onclick = function()
    if updating then return end
    updating = true
    skipFirstEnabled = dlg.data.skipFirst
    initSlotColors(pal)      -- re-read all slots from palette with new mapping
    dlg:repaint()
    refreshSliders(dlg, pal)
    updating = false
  end
}

dlg:newrow()

-- Stretch checkbox (default: checked = full-range)
dlg:check{
  id = "stretch",
  text = "Stretch colors to full 8-bit range",
  selected = stretchEnabled,
  onclick = function()
    stretchEnabled = dlg.data.stretch
    if updating then return end
    updating = true
    -- Re-convert all 16 slots using the new stretch setting
    for slot = 0, 15 do
      local c = slotColors3bit[slot]
      if c then
        pal:setColor(slotToIndex(slot), Color{
          r = bit3to8(c.r, stretchEnabled),
          g = bit3to8(c.g, stretchEnabled),
          b = bit3to8(c.b, stretchEnabled),
          a = 255
        })
      end
    end
    dlg:repaint()
    refreshSliders(dlg, pal)
    updating = false
  end
}

dlg:newrow()

-- STE mode checkbox
dlg:check{
  id = "ste",
  text = "STE palette (4-bit primaries, 0-15 per channel)",
  selected = steEnabled,
  onclick = function()
    steEnabled = dlg.data.ste
    if updating then return end
    updating = true
    -- Re-read palette at new bit depth (handles clamping)
    initSlotColors(pal)
    -- Update slider max values
    local newMax = steEnabled and 15 or 7
    dlg:modify{ id = "s_r", max = newMax }
    dlg:modify{ id = "s_g", max = newMax }
    dlg:modify{ id = "s_b", max = newMax }
    -- Refresh display
    refreshSliders(dlg, pal)
    dlg:repaint()
    updating = false
  end
}

dlg:separator{ text = "Palette" }

-- --- Canvas callbacks (defined here to capture dlg, pal) ---


-- Detect palette changes (e.g., from undo) and re-sync slotColors3bit
local function ensureSynced()
  for slot = 0, 15 do
    local idx = slotToIndex(slot)
    local color = pal:getColor(idx)
    if color then
      local r3 = bit8to3(color.red)
      local g3 = bit8to3(color.green)
      local b3 = bit8to3(color.blue)
      local c = slotColors3bit[slot]
      if not c or c.r ~= r3 or c.g ~= g3 or c.b ~= b3 then
        -- Mismatch detected: re-sync from palette
        updating = true
        initSlotColors(pal)
        refreshSliders(dlg, pal)
        dlg:repaint()
        updating = false
        return
      end
    end
  end
end

local function canvasOnPaint(ev)
  local gc = ev.context
  gc.antialias = false

  -- --- 4x4 swatch grid ---
  for slot = 0, 15 do
    local r = slotRect(slot)
    local c = slotColors3bit[slot] or { r = 0, g = 0, b = 0 }
    local cr = bit3to8(c.r, stretchEnabled)
    local cg = bit3to8(c.g, stretchEnabled)
    local cb = bit3to8(c.b, stretchEnabled)

    -- Fill swatch with color
    gc.color = Color{ r = cr, g = cg, b = cb, a = 255 }
    gc:fillRect(r)

    -- Border: yellow for selected, lighter for hovered, dark for normal
    if slot == selectedSlot then
      gc.color = Color{ r = 255, g = 200, b = 0, a = 255 }
      gc.strokeWidth = 2
    elseif slot == hoveredSlot then
      gc.color = Color{ r = 180, g = 180, b = 180, a = 255 }
      gc.strokeWidth = 1
    else
      gc.color = Color{ r = 60, g = 60, b = 60, a = 255 }
      gc.strokeWidth = 1
    end
    gc:strokeRect(r)

    -- Determine text color based on background brightness
    local brightness = (cr * 299 + cg * 587 + cb * 114) / 1000
    local textColor, dimTextColor
    if brightness > 150 then
      textColor = Color{ r = 0, g = 0, b = 0, a = 255 }
      dimTextColor = Color{ r = 0, g = 0, b = 0, a = 140 }
    else
      textColor = Color{ r = 255, g = 255, b = 255, a = 255 }
      dimTextColor = Color{ r = 255, g = 255, b = 255, a = 140 }
    end

    -- Palette index in top-left corner (subtle)
    local idxText = tostring(slotToIndex(slot))
    gc.color = dimTextColor
    gc:fillText(idxText, r.x + 3, r.y + 12)

    -- Hex color code centered
    local hexText = rgb3hex(c.r, c.g, c.b)
    local size = gc:measureText(hexText)
    gc.color = textColor
    gc:fillText(hexText,
      r.x + (r.w - size.width) / 2,
      r.y + (r.h - size.height) / 2)
  end
end

local function canvasOnMouseMove(ev)
  ensureSynced()
  local newHover = slotAtPoint(ev.x, ev.y)
  if newHover ~= hoveredSlot then
    hoveredSlot = newHover
    dlg:repaint()
  end
end

local function canvasOnMouseUp(ev)
  if updating then return end
  ensureSynced()
  local slot = slotAtPoint(ev.x, ev.y)
  if slot then
    updating = true
    selectedSlot = slot
    refreshSliders(dlg, pal)
    dlg:repaint()
    updating = false
  end
end

-- Custom canvas: preview strip + 4x4 swatch grid
dlg:canvas{
  id = "paletteCanvas",
  width = CANVAS_W,
  height = CANVAS_H,
  autoscaling = false,
  onpaint = canvasOnPaint,
  onmousemove = canvasOnMouseMove,
  onmouseup = canvasOnMouseUp
}

dlg:separator{}

-- Selected slot label
dlg:label{
  id = "selLabel",
  text = "Selected:  0: 000"
}


-- Shared R, G, B sliders (0-7) for the selected slot
local function sliderChanged()
  if updating then return end
  updating = true
  writeSelectedSlot(dlg, pal)
  updating = false
end

dlg:slider{
  id = "s_r",
  label = "R:",
  min = 0,
  max = 7,
  value = 0,
  onchange = sliderChanged
}

dlg:newrow()

dlg:slider{
  id = "s_g",
  label = "G:",
  min = 0,
  max = 7,
  value = 0,
  onchange = sliderChanged
}

dlg:newrow()

dlg:slider{
  id = "s_b",
  label = "B:",
  min = 0,
  max = 7,
  value = 0,
  onchange = sliderChanged
}

dlg:separator{}

-- Close button
dlg:button{
  text = "Close",
  onclick = function()
    dlg:close()
  end
}

-- ================================================================
-- Initialize & Show
-- ================================================================

-- Populate all controls from the current palette state
initSlotColors(pal)
refreshSliders(dlg, pal)

-- Show the dialog non-modally (allows undo and other interactions while open)
dlg:show{ wait = false }

-- Listen for document changes (e.g., undo/redo) to keep dialog in sync
local function onPaletteChange()
  ensureSynced()
end
pcall(function() app.events:on('change', onPaletteChange) end)
pcall(function() sprite.events:on('change', onPaletteChange) end)

-- Repaint after show so the canvas surface is ready
dlg:repaint()
