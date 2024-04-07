--@module = true

local gui = require("gui")
local json = require('json')
local overlay = require('plugins.overlay')
local utils = require('utils')
local widgets = require("gui.widgets")

local CONFIG_FILE = 'dfhack-config/manipulator.json'

local config = json.open(CONFIG_FILE)

------------------------
-- Column
--

Column = defclass(Column, widgets.Panel)
Column.ATTRS{
    label='',
    data_fn=DEFAULT_NIL,
    count_fn=DEFAULT_NIL,
    make_sort_order_fn=DEFAULT_NIL,
    group=DEFAULT_NIL,
    label_inset=0,
    data_width=4,
    hidden=DEFAULT_NIL,
    autoarrange_subviews=true,
}

function Column:init()
    self.frame = utils.assign({t=0, b=0, l=0, w=14}, self.frame or {})

    if not self.make_sort_order_fn then
        self.make_sort_order_fn = function(unit_ids)
            local spec = {key=function(choice) return self.data_fn(df.unit.find(choice.unit_id)) end}
            return utils.make_sort_order(choices, {spec})
        end
    end

    if self.hidden == nil then
        self.hidden = safe_index(config.data, 'cols', self.label, 'hidden')
    end

    self:addviews{
        widgets.Panel{
            frame={l=0, h=5},
            subviews={
                widgets.Divider{
                    view_id='col_stem',
                    frame={l=self.label_inset, t=4, w=1, h=1},
                    frame_style=gui.FRAME_INTERIOR,
                    frame_style_b=false,
                },
                widgets.HotkeyLabel{
                    view_id='col_label',
                    frame={l=self.label_inset, t=4},
                    label=self.label,
                    on_activate=function() end, -- TODO: sort by this column
                },
            },
        },
        widgets.Label{
            view_id='col_current',
            frame={l=1+self.label_inset, w=4},
        },
        widgets.Label{
            view_id='col_total',
            frame={l=1+self.label_inset, w=4},
        },
        widgets.List{
            view_id='col_list',
            frame={l=0, w=self.data_width},
        },
    }

    self.subviews.col_list.scrollbar.visible = false
end

function Column:set_data(units, unit_ids, sort_order)
    self.unit_ids, self.sort_order = unit_ids, sort_order

    local choices = {}
    local current, total = 0, 0
    local next_id_idx = 1
    for _, unit in ipairs(units) do
        local val = self.count_fn(unit)
        if unit.id == unit_ids[next_id_idx] then
            local data = self.data_fn(unit)
            table.insert(choices, (not data or data == 0) and '-' or tostring(data))
            current = current + val
            next_id_idx = next_id_idx + 1
        end
        total = total + val
    end
    self.subviews.col_current:setText(tostring(current))
    self.subviews.col_total:setText(tostring(total))
    self.subviews.col_list:setChoices(choices)
end

function Column:set_stem_height(h)
    self.subviews.col_label.frame.t = 4 - h
    self.subviews.col_stem.frame.t = 4 - h
    self.subviews.col_stem.frame.h = h + 1
end

------------------------
-- DataColumn
--

DataColumn = defclass(DataColumn, Column)
DataColumn.ATTRS{
}

function DataColumn:init()
    if not self.count_fn then
        self.count_fn = function(unit)
            local data = self.data_fn(unit)
            if not data then return 0 end
            if type(data) == 'number' then return data > 0 and 1 or 0 end
            return 1
        end
    end
end

------------------------
-- ToggleColumn
--

ToggleColumn = defclass(ToggleColumn, Column)
ToggleColumn.ATTRS{
    on_toggle=DEFAULT_NIL,
}

function ToggleColumn:init()
    if not self.count_fn then
        self.count_fn = function(unit) return self.data_fn(unit) and 1 or 0 end
    end
end

------------------------
-- Spreadsheet
--

Spreadsheet = defclass(Spreadsheet, widgets.Panel)

function Spreadsheet:init()
    self.left_col = 1

    local cols = widgets.Panel{}
    self.cols = cols

    cols:addviews{
        ToggleColumn{
            label='Favorites',
            data_fn=function(unit) return utils.binsearch(ensure_key(config.data, 'favorites'), unit.id) end,
        },
    }

    for i in ipairs(df.job_skill) do
        local caption = df.job_skill.attrs[i].caption
        if caption then
            cols:addviews{
                DataColumn{
                    label=caption,
                    data_fn=function(unit)
                        return (utils.binsearch(unit.status.current_soul.skills, i, 'id') or {rating=0}).rating
                    end,
                    group='skills',
                }
            }
        end
    end

    self:addviews{
        widgets.Label{
            frame={t=5, l=0},
            text='Shown:',
        },
        widgets.Label{
            frame={t=6, l=0},
            text='Total:',
        },
        DataColumn{
            view_id='name',
            frame={w=30},
            label='Name',
            label_inset=8,
            data_fn=dfhack.units.getReadableName,
            data_width=30,
        },
        cols,
    }

    self.list = self.subviews.name.subviews.col_list
    self:addviews{
            widgets.Scrollbar{
            view_id='scrollbar',
            frame={t=7, r=0},
            on_scroll=self.list:callback('on_scrollbar'),
        }
    }
    self.list.scrollbar = self.subviews.scrollbar

    self:refresh()
end

-- TODO: apply search and filtering
function Spreadsheet:get_visible_unit_ids(units)
    local visible_unit_ids = {}
    for _, unit in ipairs(units) do
        table.insert(visible_unit_ids, unit.id)
    end
    return visible_unit_ids
end

function Spreadsheet:update_col_layout(idx, col, width, max_width)
    col.visible = not col.hidden and idx >= self.left_col and width + col.frame.w <= max_width
    col.frame.l = width
    return width + (col.visible and col.data_width+1 or 0)
end

function Spreadsheet:refresh()
    local units = dfhack.units.getCitizens()
    local visible_unit_ids = self:get_visible_unit_ids(units)
    --local sort_order = self.subviews.name.sort_order or self.subviews.name.make_sort_order_fn(visible_unit_ids)
    local max_width = self.frame_body and self.frame_body.width or 0
    local ord, width = 1, self.subviews.name.data_width + 1
    self.subviews.name:set_data(units, visible_unit_ids, sort_order)
    for idx, col in ipairs(self.cols.subviews) do
        col:set_data(units, visible_unit_ids, sort_order)
        if not col.hidden then
            col:set_stem_height((6-ord)%5)
            ord = ord + 1
        end
        width = self:update_col_layout(idx, col, width, max_width)
    end
end

function Spreadsheet:preUpdateLayout(parent_rect)
    local width = self.subviews.name.data_width + 1
    for idx, col in ipairs(self.cols.subviews) do
        width = self:update_col_layout(idx, col, width, parent_rect.width)
    end
end

function Spreadsheet:render(dc)
    local page_top = self.list.page_top
    for idx, col in ipairs(self.cols.subviews) do
        col.subviews.col_list.page_top = page_top
    end
    Spreadsheet.super.render(self, dc)
end

------------------------
-- Manipulator
--

Manipulator = defclass(Manipulator, widgets.Window)
Manipulator.ATTRS{
    frame_title='Unit Overview and Manipulator',
    frame={w=110, h=40},
    resizable=true,
    resize_min={w=70, h=25},
}

function Manipulator:init()
    self:addviews{
        widgets.EditField{
            view_id='search',
            frame={l=0, t=0},
            label_text='Search: ',
            on_char=function(ch) return ch:match('[%l -]') end,
            on_change=function() self.subviews.sheet:refresh() end,
        },
        widgets.Divider{
            frame={l=0, r=0, t=2, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        Spreadsheet{
            view_id='sheet',
            frame={l=0, t=3, r=0, b=7},
        },
        widgets.Divider{
            frame={l=0, r=0, b=6, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        widgets.Panel{
            frame={l=0, r=0, b=0, h=5},
            subviews={
                widgets.Label{
                    frame={t=0, l=0},
                    text='Use arrow keys to navigate cells.',
                },
                widgets.HotkeyLabel{
                    frame={b=2, l=0},
                    label='Sort/reverse sort by current column',
                    key='CUSTOM_SHIFT_S',
                    on_activate=function() end, -- TODO
                },
                widgets.HotkeyLabel{
                    frame={b=0, l=0},
                    auto_width=true,
                    label='Refresh', -- TODO add warning if citizen list has changed and needs refreshing
                    key='CUSTOM_SHIFT_R',
                    on_activate=function() end, -- TODO
                },
                -- TODO moar hotkeys
            },
        },
    }
end

------------------------
-- ManipulatorScreen
--

ManipulatorScreen = defclass(ManipulatorScreen, gui.ZScreen)
ManipulatorScreen.ATTRS{
    focus_path='manipulator',
}

function ManipulatorScreen:init()
    self:addviews{Manipulator{}}
end

function ManipulatorScreen:onDismiss()
    view = nil
end

------------------------
-- ManipulatorOverlay
--

ManipulatorOverlay = defclass(ManipulatorOverlay, overlay.OverlayWidget)
ManipulatorOverlay.ATTRS{
    desc='Adds a hotkey to the vanilla units screen to launch the DFHack units interface.',
    default_pos={x=50, y=-5},
    default_enabled=true,
    viewscreens='dwarfmode/Info/CREATURES/CITIZEN',
    frame={w=34, h=1},
}

function ManipulatorOverlay:init()
    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            label='DFHack citizen interface',
            key='CUSTOM_CTRL_N',
            on_activate=function() dfhack.run_script('gui/manipulator') end,
        },
    }
end

OVERLAY_WIDGETS = {
    launcher=ManipulatorOverlay,
}

if dfhack_flags.module then return end

if not dfhack.world.isFortressMode() or not dfhack.isMapLoaded() then
    qerror("This script requires a fortress map to be loaded")
end

view = view and view:raise() or ManipulatorScreen{}:show()
