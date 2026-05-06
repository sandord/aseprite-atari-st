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
    - 3-bit hex display for the selected slot (e.g., "777" = full white)
]]

-- ================================================================
-- State
-- ================================================================

local selectedSlot = 0
local stretchEnabled = true
local skipFirstEnabled = false
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
  if stretch then
    -- Full-range stretch: replicate 3 bits across 8 bits
    -- 7 (111b) -> (11100000) | (00011100) | (00000011) = 11111111 = 255
    return (v << 5) | (v << 2) | (v >> 1)
  end
  -- Simple shift: 7 (111b) -> 11100000 = 224
  return v << 5
end

--- Convert an 8-bit value (0-255) back to a 3-bit value (0-7).
--- Rounds to the nearest 3-bit representation.
--- @param v integer 0-255
--- @return integer 0-7
local function bit8to3(v)
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
-- Dialog Update Functions
-- ================================================================

--- Read all 16 palette entries and update the button labels.
--- Does NOT write to the palette. Missing entries default to black.
--- @param dlg Dialog
--- @param pal Palette
local function refreshButtons(dlg, pal)
  for slot = 0, 15 do
    local idx = slotToIndex(slot)
    local c = slotColors3bit[slot]
    if c then
      dlg:modify{ id = "b" .. slot, text = string.format("%2d: %s", idx, rgb3hex(c.r, c.g, c.b)) }
    else
      dlg:modify{ id = "b" .. slot, text = string.format("%2d: $000", idx) }
    end
  end
end

--- Read all 16 palette entries and update the visual shades strip.
--- Pure display — no interaction. Does NOT write to the palette.
--- @param dlg Dialog
--- @param pal Palette
local function refreshShadesDisplay(dlg, pal)
  local colors = {}
  for slot = 0, 15 do
    local idx = slotToIndex(slot)
    local color = pal:getColor(idx)
    if color then
      colors[slot + 1] = Color{ r = color.red, g = color.green, b = color.blue, a = 255 }
    else
      colors[slot + 1] = Color{ r = 0, g = 0, b = 0, a = 255 }
    end
  end
  dlg:modify{ id = "colorPreviews", colors = colors }
end

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

  -- Refresh all displays
  refreshButtons(dlg, pal)
  refreshShadesDisplay(dlg, pal)

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
    skipFirstEnabled = dlg.data.skipFirst
    initSlotColors(pal)      -- re-read all slots from palette with new mapping
    refreshButtons(dlg, pal)
    refreshShadesDisplay(dlg, pal)
    refreshSliders(dlg, pal)
  end
}

dlg:newrow()

-- Stretch checkbox (default: checked = full-range)
dlg:check{
  id = "stretch",
  text = "Stretch 3-bit colors to full 8-bit range",
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
    refreshButtons(dlg, pal)
    refreshShadesDisplay(dlg, pal)
    refreshSliders(dlg, pal)
    updating = false
  end
}

dlg:separator{ text = "Palette" }

-- Visual color preview strip (read-only, no interaction)
dlg:shades{
  id = "colorPreviews",
  colors = {}
}

-- 4×4 grid of selection buttons, each showing index and 3-bit hex
for row = 0, 3 do
  for col = 0, 3 do
    local currentSlot = row * 4 + col
    dlg:button{
      id = "b" .. currentSlot,
      text = string.format("%2d: $000", slotToIndex(currentSlot)),
      onclick = function()
        if updating then return end
        updating = true
        selectedSlot = currentSlot
        refreshSliders(dlg, pal)
        updating = false
      end
    }
  end
  dlg:newrow()
end

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
refreshButtons(dlg, pal)
refreshShadesDisplay(dlg, pal)
refreshSliders(dlg, pal)

-- Show the dialog modally (blocks script execution until closed)
dlg:show{ wait = true }
