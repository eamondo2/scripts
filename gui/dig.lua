-- A GUI front-end for the digging designations
--@ module = false

-- TODOS ====================

-- Must Haves
-----------------------------
-- Line 'shape' between two points with thickness (currently tricky with how shapes are defined as within bounds rectangle)
--   A totally vertical line with thickness of e.g. 3 would end up with tiles outside the bounds/view rectangle
--   Could also allow 'multi-point' line that would produce curves
-- Need to support classic mode? Might just be double checking non-graphics 'pen' settings

-- Should Haves
-----------------------------
-- As the number of shapes and designations grow it might be better to have list menus for them instead of cycle
-- 3D shapes, would allow stuff like spiral staircases/minecart tracks and other neat stuff, probably not too hard
-- Grid view without slowness (can ignore if next TODO is done, since nrmal mining mode has grid view)
--   Lags when drawing the full screen grid on each frame render
-- Integrate with default mining mode for designation type, priority, etc... (possible?)
-- Add warning to stairs if not spanning z levels like vanilla does
-- Figure out how to remove dug stairs with mode (nothing seems to work, include 'dig ramp')
-- 'No overwrite' mode to not overwrite existing designations
-- Smoothing and engraving

-- Nice To Haves
-----------------------------
-- Triangle shapes, more shapes in general, could even do dynamic creation of residential layouts as long as they can be mathematically represented
-- Exploration pattern ladder https://dwarffortresswiki.org/index.php/DF2014:Exploratory_mining#Ladder_Rows
-- Investigate using single quickfort API call when commiting  https://github.com/joelpt/quickfort/blob/master/README.md#area-expansion-syntax

-- Stretch Goals
-----------------------------
-- Shape preview in panel
-- Shape designer in preview panel to draw repeatable shapes i'e' 2x3 room with door

-- END TODOS ================

local gui = require("gui")
local guidm = require("gui.dwarfmode")
local widgets = require("gui.widgets")
local quickfort = reqscript("quickfort")
local shapes = reqscript("internal/dig/shapes")

local tile_attrs = df.tiletype.attrs

local to_pen = dfhack.pen.parse

local function get_dims(pos1, pos2)
    local width, height, depth =
    math.abs(pos1.x - pos2.x) + 1,
        math.abs(pos1.y - pos2.y) + 1,
        math.abs(pos1.z - pos2.z) + 1
    return width, height, depth
end

-- Panel to show the Mouse position/dimensions/etc
-- Stolen from blueprint or quickfort I forget
ActionPanel = defclass(ActionPanel, widgets.ResizingPanel)
ActionPanel.ATTRS {
    get_mark_fn = DEFAULT_NIL,
    autoarrange_subviews = true,
}

function ActionPanel:init()
    self:addviews { widgets.WrappedLabel {
        view_id = "action_label",
        text_to_wrap = self:callback("get_action_text"),
    },
        widgets.TooltipLabel {
            view_id = "selected_area",
            indent = 1,
            text = { { text = self:callback("get_area_text") } },
            show_tooltip = self.get_mark_fn,
        } }
end

function ActionPanel:get_action_text()
    local text = "Select the "
    if self.get_mark_fn() then
        text = text .. "second corner"
    else
        text = text .. "first corner"
    end
    return text .. " with the mouse."
end

function ActionPanel:get_area_text()
    local mark = self.get_mark_fn()
    if not mark then
        return ""
    end
    local other = dfhack.gui.getMousePos() or {
        x = mark.x,
        y = mark.y,
        z = df.global.window_z,
    }
    local width, height, depth = get_dims(mark, other)
    local tiles = width * height * depth
    local plural = tiles > 1 and "s" or ""
    return ("%dx%dx%d (%d tile%s) mark: %d, %d, %d"):format(
        width,
        height,
        depth,
        tiles,
        plural,
        other.x,
        other.y,
        other.z
    )
end

-- Generic options not specific to shapes
GenericOptionsPanel = defclass(GenericOptionsPanel, widgets.ResizingPanel)
GenericOptionsPanel.ATTRS {
    name = DEFAULT_NIL,
    autoarrange_subviews = true,
    dig_panel = DEFAULT_NIL,
    on_layout_change = DEFAULT_NIL,
}

function GenericOptionsPanel:init()
    local options = {}
    for i, shape in pairs(shapes.all_shapes) do
        options[#options + 1] = {
            label = shape.name,
            value = i,
        }
    end

    local stair_options = {
        {
            label = "Auto",
            value = "auto",
        },
        {
            label = "Up/Down",
            value = "i",
        },
        {
            label = "Up",
            value = "u",
        },
        {
            label = "Down",
            value = "j",
        },
    }

    self:addviews { widgets.WrappedLabel {
        view_id = "settings_label",
        text_to_wrap = "General Settings:\n",
    },
        widgets.CycleHotkeyLabel {
            view_id = "shape_name",
            key = "CUSTOM_Z",
            key_back = "CUSTOM_SHIFT_Z",
            label = "Shape: ",
            label_width = 8,
            active = true,
            enabled = true,
            options = options,
            disabled = false,
            show_tooltip = true,
            on_change = self:callback("change_shape"),
        },
        widgets.ToggleHotkeyLabel {
            view_id = "invert_designation_label",
            key = "CUSTOM_I",
            label = "Invert: ",
            label_width = 8,
            active = true,
            enabled = true,
            disabled = false,
            show_tooltip = true,
            initial_option = false,
            on_change = function(new, old)
                self.dig_panel.shape.invert = new
                self.dig_panel.dirty = true
            end,
        },
        widgets.CycleHotkeyLabel {
            view_id = "mode_name",
            key = "CUSTOM_F",
            key_back = "CUSTOM_SHIFT_F",
            label = "Mode: ",
            label_width = 8,
            active = true,
            enabled = true,
            options = {
                {
                    label = "Dig",
                    value = "d",
                },
                {
                    label = "Channel",
                    value = "h",
                },
                {
                    label = "Remove Designation",
                    value = "x",
                },
                {
                    label = "Remove Ramps",
                    value = "z",
                },
                {
                    label = "Remove Constructions",
                    value = "n",
                },
                {
                    label = "Stairs",
                    value = "i",
                },
                {
                    label = "Ramp",
                    value = "r",
                }
            },
            disabled = false,
            show_tooltip = true,
            on_change = function(new, old) self.dig_panel:updateLayout() end,
        },
        widgets.CycleHotkeyLabel {
            view_id = "stairs_top_subtype",
            key = "CUSTOM_R",
            label = "Top Stair Type: ",
            active = true,
            enabled = true,
            visible = function() return self.dig_panel.subviews.mode_name:getOptionValue() == "i" end,
            options = stair_options,
        },
        widgets.CycleHotkeyLabel {
            view_id = "stairs_middle_subtype",
            key = "CUSTOM_G",
            label = "Middle Stair Type: ",
            active = true,
            enabled = true,
            visible = function() return self.dig_panel.subviews.mode_name:getOptionValue() == "i" end,
            options = stair_options,
        },
        widgets.CycleHotkeyLabel {
            view_id = "stairs_bottom_subtype",
            key = "CUSTOM_B",
            label = "Bottom Stair Type: ",
            active = true,
            enabled = true,
            visible = function() return self.dig_panel.subviews.mode_name:getOptionValue() == "i" end,
            options = stair_options,
        },
        widgets.WrappedLabel {
            view_id = "shape_prio_label",
            text_to_wrap = function()
                return "Priority: " .. tostring(self.dig_panel.prio)
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_option_priority_minus",
            key = "CUSTOM_P",
            label = "Increase Priority",
            active = true,
            enabled = function()
                return self.dig_panel.prio > 1
            end,
            disabled = false,
            show_tooltip = true,
            on_activate = function()
                self.dig_panel.prio = self.dig_panel.prio - 1
                self.dig_panel:updateLayout()
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_option_priority_plus",
            key = "CUSTOM_SHIFT_P",
            label = "Decrease Priority",
            active = true,
            enabled = function()
                return self.dig_panel.prio < 7
            end,
            disabled = false,
            show_tooltip = true,
            on_activate = function()
                self.dig_panel.prio = self.dig_panel.prio + 1
                self.dig_panel:updateLayout()
            end,
        },
        widgets.ToggleHotkeyLabel {
            view_id = "autocommit_designation_label",
            key = "CUSTOM_C",
            label = "Auto-Commit: ",
            active = true,
            enabled = true,
            disabled = false,
            show_tooltip = true,
            initial_option = true,
            on_change = function(new, old)
                self.dig_panel.autocommit = new
                self.dig_panel.dirty = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "commit_label",
            key = "CUSTOM_CTRL_C",
            label = "Commit Designation",
            active = true,
            enabled = function()
                return self.dig_panel.saved_cursor and self.dig_panel.mark
            end,
            disabled = false,
            show_tooltip = true,
            on_activate = function()
                self.dig_panel:commit()
            end,
        } }
end

function GenericOptionsPanel:change_shape(new, old)
    self.dig_panel.shape = shapes.all_shapes[new]
    self.dig_panel:add_shape_options()
    self.dig_panel:updateLayout()
end

--
-- For tile graphics
--

local CURSORS = {
    INSIDE = { 1, 2 },
    NORTH = { 1, 1 },
    N_NUB = { 3, 2 },
    S_NUB = { 4, 2 },
    W_NUB = { 3, 1 },
    E_NUB = { 5, 1 },
    NE = { 2, 1 },
    NW = { 0, 1 },
    WEST = { 0, 2 },
    EAST = { 2, 2 },
    SW = { 0, 3 },
    SOUTH = { 1, 3 },
    SE = { 2, 3 },
    VERT_NS = { 3, 3 },
    VERT_EW = { 4, 1 },
    POINT = { 4, 3 },
}

-- Bit positions to use for keys in PENS table
local PEN_MASK = {
    NORTH = 1,
    SOUTH = 2,
    EAST = 3,
    WEST = 4,
    CORNER = 5,
    MOUSEOVER = 6,
    INSHAPE = 7,
}

-- Populated dynamically as needed
-- The pens will be stored with keys corresponding to the directions passed to gen_pen_key()
local PENS = {}


--
-- Dig
--

Dig = defclass(Dig, widgets.Window)
Dig.ATTRS {
    frame_title = "Dig",
    frame = {
        w = 47,
        h = 40,
        r = 2,
        t = 18,
    },
    resizable = true,
    resize_min = { h = 30 },
    autoarrange_subviews = true,
    autoarrange_gap = 1,
    shape = DEFAULT_NIL,
    dirty = true,
    prio = 4,
    autocommit = true,
    cur_shape = 1,
}

-- Get the pen to use when drawing a type of tile based on it's position in the shape and
-- neighboring tiles. The first time a certain tile type needs to be drawn, it's pen
-- is generated and stored in PENS. On subsequent calls, the cached pen will be used for
-- other tiles with the same position/direction
function Dig:get_pen(x, y, mousePos)
    local function is_corner(_x, _y)
        return _x == 0 and _y == 0 or _x == self.shape.width and _y == 0 or _x == 0 and _y == self.shape.height or
            _x == self.shape.width and _y == self.shape.height
    end

    local function is_mouse_over(_x, _y, mouse)
        return mouse == nil or (_x == mouse.x and _y == mouse.y)
    end

    local n, w, e, s = false, false, false, false
    if y == 0 or not self.shape.arr[x][y - 1] then n = true end
    if x == 0 or not self.shape.arr[x - 1][y] then w = true end
    if x == #self.shape.arr or not self.shape.arr[x + 1][y] then e = true end
    if y == #self.shape.arr[x] or not self.shape.arr[x][y + 1] then s = true end

    -- Get the bit field to use as a key for the PENS map
    local pen_key = self:gen_pen_key(n, s, e, w, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])

    -- If key doesn't exist in the map, set it
    if pen_key and not PENS[pen_key] then
        if not n and not w and not e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.INSIDE, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and w and not e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.NW, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and not w and not e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.NORTH, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and e and not w and not s then
            PENS[pen_key] = self:make_pen(CURSORS.NE, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and w and not e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.WEST, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and not w and e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.EAST, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and w and not e and s then
            PENS[pen_key] = self:make_pen(CURSORS.SW, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and not w and not e and s then
            PENS[pen_key] = self:make_pen(CURSORS.SOUTH, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and not w and e and s then
            PENS[pen_key] = self:make_pen(CURSORS.SE, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and w and e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.N_NUB, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and not w and e and s then
            PENS[pen_key] = self:make_pen(CURSORS.E_NUB, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and w and not e and s then
            PENS[pen_key] = self:make_pen(CURSORS.W_NUB, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and w and e and s then
            PENS[pen_key] = self:make_pen(CURSORS.S_NUB, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and not n and w and e and not s then
            PENS[pen_key] = self:make_pen(CURSORS.VERT_NS, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and not w and not e and s then
            PENS[pen_key] = self:make_pen(CURSORS.VERT_EW, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif self.shape.arr[x][y] and n and w and e and s then
            PENS[pen_key] = self:make_pen(CURSORS.POINT, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        elseif is_corner(x, y) and not self.shape.arr[x][y] then
            PENS[pen_key] = self:make_pen(CURSORS.INSIDE, is_corner(x, y), is_mouse_over(x, y, mousePos), self.shape.arr[x][y])
        else
            PENS[pen_key] = nil
        end
    end

    -- Return the pen for the caller
    return PENS[pen_key]
end


function Dig:init()
    self:addviews { ActionPanel {
        view_id = "action_panel",
        get_mark_fn = function()
            return self.mark
        end,
    },
        GenericOptionsPanel {
            view_id = "name_panel",
            dig_panel = self,
        } }
end

function Dig:postinit()
    self.shape = shapes.all_shapes[self.subviews.shape_name:getOptionValue()]
    if self.shape then
        self:add_shape_options()
    end
end

-- Add shape specific options dynamically based on the shape.options table
-- Currently only supports 'bool' aka toggle and 'plusminus' which creates
-- a pair of HotKeyLabel's to increment/decrement a value
-- Will need to update as needed to add more option types
function Dig:add_shape_options()
    local prefix = "shape_option_"
    for i, view in ipairs(self.subviews or {}) do
        if view.view_id:sub(1, #prefix) == prefix then
            self.subviews[i] = nil
        end
    end

    if not self.shape or not self.shape.options then return end

    self:addviews { widgets.WrappedLabel {
        view_id = "shape_option_label",
        text_to_wrap = "Shape Settings:\n",
    } }

    for key, option in pairs(self.shape.options) do
        if option.type == "bool" then
            self:addviews { widgets.ToggleHotkeyLabel {
                view_id = "shape_option_" .. option.name,
                key = option.key,
                label = option.name,
                active = true,
                enabled = function()
                    if option.enabled == nil then
                        return true
                    else
                        return self.shape.options[option.enabled[1]] == option.enabled[2]
                    end
                end,
                disabled = false,
                show_tooltip = true,
                initial_option = option.value,
                on_change = function(new, old)
                    self.shape.options[key].value = new
                    self.dirty = true
                end,
            } }
        elseif option.type == "plusminus" then
            local min, max = nil, nil
            if type(option['min']) == "number" then
                min = option['min']
            elseif type(option['min']) == "function" then
                min = option['min'](self.shape)
            end
            if type(option['max']) == "number" then
                max = option['max']
            elseif type(option['max']) == "function" then
                max = option['max'](self.shape)
            end

            self:addviews { widgets.HotkeyLabel {
                view_id = "shape_option_" .. option.name .. "_minus",
                key = option.keys[1],
                label = "Decrease " .. option.name,
                active = true,
                enabled = function()
                    if option.enabled ~= nil then
                        if self.shape.options[option.enabled[1]].value ~= option.enabled[2] then
                            return false
                        end
                    end
                    return min == nil or
                        (self.shape.options[key].value > min)
                end,
                disabled = false,
                show_tooltip = true,
                on_activate = function()
                    self.shape.options[key].value =
                    self.shape.options[key].value - 1
                    self.dirty = true
                end,
            },
                widgets.HotkeyLabel {
                    view_id = "shape_option_" .. option.name .. "_plus",
                    key = option.keys[2],
                    label = "Increase " .. option.name,
                    active = true,
                    enabled = function()
                        if option.enabled ~= nil then
                            if self.shape.options[option.enabled[1]].value ~= option.enabled[2] then
                                return false
                            end
                        end
                        return max == nil or
                            (self.shape.options[key].value <= max)
                    end,
                    disabled = false,
                    show_tooltip = true,
                    on_activate = function()
                        self.shape.options[key].value =
                        self.shape.options[key].value + 1
                        self.dirty = true
                    end,
                } }

        end
    end
end

function Dig:save_cursor_pos()
    self.saved_cursor = copyall(df.global.cursor)
end

function Dig:on_mark(pos)
    self.mark = pos
    self:updateLayout()
end

function Dig:get_bounds()
    local cur = self.saved_cursor or dfhack.gui.getMousePos()
    if not cur then return end
    local mark = self.mark or cur

    return {
        x1 = math.min(cur.x, mark.x),
        x2 = math.max(cur.x, mark.x),
        y1 = math.min(cur.y, mark.y),
        y2 = math.max(cur.y, mark.y),
        z1 = math.min(cur.z, mark.z),
        z2 = math.max(cur.z, mark.z),
    }
end

-- return the pen, alter based on if we want to display a corner and a mouse over corner
function Dig:make_pen(direction, is_corner, is_mouse_over, inshape)
    return to_pen {
        ch = inshape and "X" or "o",
        fg = (is_corner and is_mouse_over) and COLOR_LIGHTMAGENTA or (is_corner and COLOR_CYAN or COLOR_GREEN),
        tile = dfhack.screen.findGraphicsTile(
            "CURSORS",
            direction[1],
            direction[2] + (is_corner and (6 + (is_mouse_over and 3 or 0)) or 0)
        ),
    }
end

-- Generate a bit field to store as keys in PENS
function Dig:gen_pen_key(n, s, e, w, is_corner, is_mouse_over, inshape)
    local ret = 0
    if n then ret = ret + (1 << PEN_MASK.NORTH) end
    if s then ret = ret + (1 << PEN_MASK.SOUTH) end
    if e then ret = ret + (1 << PEN_MASK.EAST) end
    if w then ret = ret + (1 << PEN_MASK.WEST) end
    if is_corner then ret = ret + (1 << PEN_MASK.CORNER) end
    if is_mouse_over then ret = ret + (1 << PEN_MASK.MOUSEOVER) end
    if inshape then ret = ret + (1 << PEN_MASK.INSHAPE) end

    return ret
end

function Dig:onRenderFrame(dc, rect)
    Dig.super.onRenderFrame(self, dc, rect)
    if self.shape == nil then
        self.shape =
        shapes.all_shapes[self.subviews.shape_name:getOptionValue()]
    end

    local bounds = self:get_bounds()
    if bounds and self.mark then

        local function get_overlay_pen(pos)
            -- Check if we need to update the shape dimensions. Either there isn't a shape, we've marked it dirty, or the bounds have changed
            if self.dirty or (pos.x >= bounds.x1 and pos.x <= bounds.x2 and pos.y >= bounds.y1 and pos.y <= bounds.y2) then
                if not self.shape or self.dirty or
                    (bounds.x2 - bounds.x1 ~= self.shape.width or bounds.y2 - bounds.y1 ~= self.shape.height) then
                    self.shape:update(
                        bounds.x2 - bounds.x1,
                        bounds.y2 - bounds.y1
                    )
                    self:add_shape_options()
                    self:updateLayout()
                    self.dirty = false
                end

                local mouse_pos = dfhack.gui.getMousePos()
                if mouse_pos ~= nil then
                    mouse_pos.x = mouse_pos.x - bounds.x1
                    mouse_pos.y = mouse_pos.y - bounds.y1
                end

                -- Get the pen from the base Shape class based on if the point is in the shape or not
                -- Send mouse position for stuff like corner anchor mouse over, etc...
                return self:get_pen(
                    pos.x - bounds.x1,
                    pos.y - bounds.y1,
                    mouse_pos
                )
            else
                return nil
            end
        end

        guidm.renderMapOverlay(get_overlay_pen, bounds)
    end
end

function Dig:onInput(keys)
    if Dig.super.onInput(self, keys) then
        return true
    end

    if keys.LEAVESCREEN or keys._MOUSE_R_DOWN then
        if self.mark then
            self.mark = nil
            self:updateLayout()
        else
            self.parent_view:dismiss()
        end
        return true
    end

    local pos = nil
    if keys._MOUSE_L_DOWN and not self:getMouseFramePos() then
        pos = dfhack.gui.getMousePos()
        if pos then
            guidm.setCursorPos(pos)
        end
    elseif keys.SELECT then
        pos = guidm.getCursorPos()
    end

    if keys._MOUSE_L_DOWN and pos then
        if self.mark and not self.saved_cursor then
            self.saved_cursor = pos
            -- The statement after the or is to allow the 1x1 special case for easy doorways
            if self.autocommit or (self.mark.x == self.saved_cursor and self.mark.y == self.saved_cursor.y) then
                self:commit()
            end
        elseif not self.mark then
            self:on_mark(pos)
        else
            -- These check if the user is trying to change a non-commited shape
            -- by clicking and dragging the corner anchors. Basically just flips the
            -- marks around by setting the mark to the opposite corner
            if pos.x == self:get_bounds().x1 and pos.y == self:get_bounds().y1 then
                self.mark =
                xyz2pos(
                    self:get_bounds().x2,
                    self:get_bounds().y2,
                    self.mark.z
                )
            elseif pos.x == self:get_bounds().x2 and pos.y == self:get_bounds().y1 then
                self.mark =
                xyz2pos(
                    self:get_bounds().x1,
                    self:get_bounds().y2,
                    self.mark.z
                )
            elseif pos.x == self:get_bounds().x1 and pos.y == self:get_bounds().y2 then
                self.mark =
                xyz2pos(
                    self:get_bounds().x2,
                    self:get_bounds().y1,
                    self.mark.z
                )
            elseif pos.x == self:get_bounds().x2 and pos.y == self:get_bounds().y2 then
                self.mark =
                xyz2pos(
                    self:get_bounds().x1,
                    self:get_bounds().y1,
                    self.mark.z
                )
            end

            self.saved_cursor = nil
        end

        return true
    end

    -- send movement keys through, but otherwise we're a modal dialog
    return not (keys.D_PAUSE or guidm.getMapKey(keys))
end

-- Put any special logic for designation type here
-- Right now it's setting the stair type based on the z-level
-- Fell through, pass through the option directly from the options value
function Dig:getDesignation(x, y, z)
    local mode = self.subviews.mode_name:getOptionValue()

    -- Stairs
    if mode == "i" then
        local stairs_top_type = self.subviews.stairs_top_subtype:getOptionValue()
        local stairs_middle_type = self.subviews.stairs_middle_subtype:getOptionValue()
        local stairs_bottom_type = self.subviews.stairs_bottom_subtype:getOptionValue()
        if z == 0 then
            return stairs_bottom_type == "auto" and "u" or stairs_bottom_type
        elseif z == math.abs(self:get_bounds().z1 - self:get_bounds().z2) then
            local tile_type = dfhack.maps.getTileType(self:get_bounds().x1 + x, self:get_bounds().y1 + y, z)
            local tile_shape = tile_attrs[tile_type].shape

            -- If top of the bounds is down stair, 'auto' should change it to up/down to match vanilla stair logic
            return stairs_top_type == "auto" and (tile_shape == df.tiletype_shape.STAIR_DOWN and "i" or "j") or
                stairs_top_type
        else
            return stairs_middle_type == "auto" and 'i' or stairs_middle_type
        end
    end

    return self.subviews.mode_name:getOptionValue()
end

-- Commit the shape using quickfort API
function Dig:commit()
    local data = {}

    -- Generates the params for quickfort API
    local function generate_params(grid, position)
        for zlevel = 0, math.abs(self:get_bounds().z1 - self:get_bounds().z2) do
            data[zlevel] = {}
            for row = 0, math.abs(
                self:get_bounds().y1 - self:get_bounds().y2
            ) do
                data[zlevel][row] = {}
                for col = 0, math.abs(
                    self:get_bounds().x1 - self:get_bounds().x2
                ) do
                    if grid[col][row] then
                        local desig = self:getDesignation(col, row, zlevel)
                        if desig ~= "`" then
                            data[zlevel][row][col] =
                            desig .. tostring(self.prio)
                        end
                    end
                end
            end
        end
        return {
            data = data,
            pos = position,
            mode = "dig",
        }
    end

    local bounds = self:get_bounds()
    local start = {
        x = bounds.x1,
        y = bounds.y1,
        z = math.min(bounds.z1, bounds.z2),
    }
    local grid = self.shape.arr

    -- Special case for 1x1 to ease doorway marking
    if bounds.x1 == bounds.x2 and bounds.y1 == bounds.y2 then
        grid = {}
        grid[0] = {}
        grid[0][0] = true
    end

    local params = generate_params(grid, start)
    quickfort.apply_blueprint(params)
    self.mark = nil
    self.saved_cursor = nil
    self:updateLayout()
end

--
-- Dig
--

DigScreen = defclass(DigScreen, gui.ZScreen)
DigScreen.ATTRS {
    focus_path = "dig",
    pass_pause = true,
    pass_movement_keys = true,
}

function DigScreen:init()
    self:addviews { Dig {} }
end

function DigScreen:onDismiss()
    view = nil
end

if dfhack_flags.module then return end

if not dfhack.isMapLoaded() then
    qerror("This script requires a fortress map to be loaded")
end

view = view and view:raise() or DigScreen {}:show()
