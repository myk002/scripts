--@module = true

local gui = require("gui")
local json = require('json')
local overlay = require('plugins.overlay')
local utils = require('utils')
local widgets = require("gui.widgets")

local CONFIG_FILE = 'dfhack-config/manipulator.json'

config = config or json.open(CONFIG_FILE)

------------------------
-- Column
--

Column = defclass(Column, widgets.Panel)
Column.ATTRS{
    idx=DEFAULT_NIL,
    label=DEFAULT_NIL,
    group='',
    label_inset=0,
    data_width=4,
    hidden=DEFAULT_NIL,
    shared=DEFAULT_NIL,
    data_fn=DEFAULT_NIL,
    count_fn=DEFAULT_NIL,
    cmp_fn=DEFAULT_NIL,
}

function Column:init()
    self.frame = utils.assign({t=0, b=0, l=0, w=14}, self.frame or {})

    self:addviews{
        widgets.TextButton{
            view_id='col_group',
            frame={t=0, l=0, h=1, w=#self.group+2},
            label=self.group,
            visible=#self.group > 0,
        },
        widgets.Panel{
            frame={t=2, l=0, h=5},
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
                    on_activate=self:callback('sort'),
                },
            },
        },
        widgets.Label{
            view_id='col_current',
            frame={t=7, l=1+self.label_inset, w=4},
        },
        widgets.Label{
            view_id='col_total',
            frame={t=8, l=1+self.label_inset, w=4},
        },
        widgets.List{
            view_id='col_list',
            frame={t=10, l=0, w=self.data_width},
        },
    }

    self.subviews.col_list.scrollbar.visible = false
    self.dirty = true
end

function Column:sort()
    if self.dirty then
        self:refresh()
    end
    if self.shared.sort_idx == self.idx then
        self.shared.sort_rev = not self.shared.sort_rev
    else
        self.shared.sort_idx = self.idx
        self.shared.sort_rev = false
    end
    local spec = {compare=self.cmp_fn, reverse=self.shared.sort_rev, key=function(choice) return choice.data end}
    local ordered_col_data = {}
    for i, ordered_i in ipairs(self.shared.sort_order) do
    end
    local sort_order = utils.make_sort_order(ordered_col_data, {spec})
end

function Column:get_units()
    if self.shared.cache.units then return self.shared.cache.units end
    local units = {}
    for _, unit_id in ipairs(self.shared.unit_ids) do
        local unit = df.unit.find(unit_id)
        if unit then
            table.insert(units, unit)
        else
            self.shared.fault = true
        end
    end
    self.shared.cache.units = units
    return units
end

function Column:refresh()
    local col_data, choices = {}, {}
    local current, total = 0, 0
    local next_id_idx = 1
    for _, unit in ipairs(self:get_units()) do
        local data = self.data_fn(unit)
        local val = self.count_fn(data)
        if unit.id == self.shared.filtered_unit_ids[next_id_idx] then
            table.insert(col_data, data)
            table.insert(choices, {
                text=function()
                    local ordered_data = col_data[self.shared.sort_order[next_id_idx]]
                    return (not data or data == 0) and '-' or tostring(data)
                end,
            })
            current = current + val
            next_id_idx = next_id_idx + 1
        end
        total = total + val
    end

    self.col_data = col_data
    self.subviews.col_current:setText(tostring(current))
    self.subviews.col_total:setText(tostring(total))
    self.subviews.col_list:setChoices(choices)

    self.dirty = false
end

function Column:render(dc)
    if self.dirty then
        self:refresh()
    end
    Column.super.render(self, dc)
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
        self.count_fn = function(data)
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
        self.count_fn = function(data) return data and 1 or 0 end
    end
end

------------------------
-- Spreadsheet
--

Spreadsheet = defclass(Spreadsheet, widgets.Panel)

function Spreadsheet:init()
    self.left_col = 1
    self.dirty = true

    self.shared = {sort_idx=-1, sort_rev=false, cache={}, unit_ids={}, filtered_unit_ids={}, sort_order={}}

    local cols = widgets.Panel{}
    self.cols = cols

    cols:addviews{
        ToggleColumn{
            view_id='favorites',
            idx=#cols.subviews+1,
            label='Favorites',
            data_fn=function(unit) return utils.binsearch(ensure_key(config.data, 'favorites'), unit.id) end,
            group='tags',
            shared=self.shared,
        },
    }

    for i in ipairs(df.job_skill) do
        local caption = df.job_skill.attrs[i].caption
        if caption then
            cols:addviews{
                DataColumn{
                    idx=#cols.subviews+1,
                    label=caption,
                    data_fn=function(unit)
                        return (utils.binsearch(unit.status.current_soul.skills, i, 'id') or {rating=0}).rating
                    end,
                    group='skills',
                    shared=self.shared,
                }
            }
        end
    end

    for _, wd in ipairs(df.global.plotinfo.labor_info.work_details) do
        cols:addviews{
            ToggleColumn{
                idx=#cols.subviews+1,
                label=wd.name,
                data_fn=function(unit)
                    return utils.binsearch(wd.assigned_units, unit.id) and true or false
                end,
                group='work details',
                shared=self.shared,
            }
        }
    end

    self:addviews{
        widgets.TextButton{
            view_id='left_group',
            frame={t=1, l=0, h=1},
            visible=false,
        },
        widgets.TextButton{
            view_id='right_group',
            frame={t=1, r=0, h=1},
            visible=false,
        },
        widgets.Label{
            frame={t=7, l=0},
            text='Shown:',
        },
        widgets.Label{
            frame={t=8, l=0},
            text='Total:',
        },
        DataColumn{
            view_id='name',
            frame={w=30},
            idx=0,
            label='Name',
            label_inset=8,
            data_fn=dfhack.units.getReadableName,
            data_width=30,
            shared=self.shared,
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

    self:update_headers()
end

function Spreadsheet:sort_by_current_row()
end

function Spreadsheet:filter(search)
end

function Spreadsheet:hide_current_row()
end

function Spreadsheet:jump_to_group(group)
    for i, col in ipairs(self.cols.subviews) do
        if not col.hidden and col.group == group then
            self.left_col = i
            break
        end
    end
    self:updateLayout()
end

function Spreadsheet:update_headers()
    local ord = 1
    for _, col in ipairs(self.cols.subviews) do
        if not col.hidden then
            col:set_stem_height((5-ord)%5)
            ord = ord + 1
        end
    end
end

-- TODO: apply search and filtering
function Spreadsheet:get_visible_units(units)
    local visible_units, visible_unit_ids = {}, {}
    for _, unit in ipairs(units) do
        table.insert(visible_units, unit)
        table.insert(visible_unit_ids, unit.id)
    end
    return visible_units, visible_unit_ids
end

function Spreadsheet:refresh()
    self.shared.fault = false
    self.subviews.name.dirty = true
    for _, col in ipairs(self.cols.subviews) do
        col.dirty = true
    end
    local units = dfhack.units.getCitizens()
    self.shared.cache.units = units
    self.shared.cache.visible_units, self.shared.visible_unit_ids = self:get_visible_units(units)
    local sort_idx = self.shared.sort_idx
    self.shared.sort_rev = not self.shared.sort_rev
    if sort_idx == -1 then
        self.subviews.name:sort()
        self.subviews.favorites:sort()
    elseif sort_idx == 0 then
        self.subviews.name:sort()
    else
        self.cols.subviews[sort_idx]:sort()
    end
    self.dirty = false
end

function Spreadsheet:update_col_layout(idx, col, width, group, max_width)
    col.visible = not col.hidden and idx >= self.left_col and width + col.frame.w <= max_width
    col.frame.l = width
    if not col.visible then
        return width, group
    end
    local col_group = col.subviews.col_group
    col_group.label.on_activate=self:callback('jump_to_group', col.group)
    col_group.visible = group ~= col.group
    return width + col.data_width + 1, col.group
end

function Spreadsheet:preUpdateLayout(parent_rect)
    local left_group, right_group = self.subviews.left_group, self.subviews.right_group
    left_group.visible, right_group.visible = false, false

    local width, group, cur_col_group = self.subviews.name.data_width + 1, '', ''
    local prev_col_group, next_col_group
    for idx, col in ipairs(self.cols.subviews) do
        local prev_group = group
        width, group = self:update_col_layout(idx, col, width, group, parent_rect.width)
        if not next_col_group and group ~= '' and not col.visible and col.group ~= cur_col_group then
            next_col_group = col.group
            local str = next_col_group .. string.char(26)  -- right arrow
            right_group:setLabel(str)
            right_group.frame.w = #str + 2
            right_group.label.on_activate=self:callback('jump_to_group', next_col_group)
            right_group.visible = true
        end
        if cur_col_group ~= col.group then
            prev_col_group = cur_col_group
        end
        cur_col_group = col.group
        if prev_group == '' and group ~= '' and prev_col_group and prev_col_group ~= '' then
            local str = string.char(27) .. prev_col_group  -- left arrow
            left_group:setLabel(str)
            left_group.frame.w = #str + 2
            left_group.label.on_activate=self:callback('jump_to_group', prev_col_group)
            left_group.visible = true
        end
    end
end

function Spreadsheet:render(dc)
    if self.dirty or self.shared.fault then
        self:refresh()
        self:updateLayout()
    end
    local page_top = self.list.page_top
    for _, col in ipairs(self.cols.subviews) do
        col.subviews.col_list.page_top = page_top
    end
    Spreadsheet.super.render(self, dc)
    self.shared.cache = {}
end

function Spreadsheet:onInput(keys)
    if keys.KEYBOARD_CURSOR_LEFT then
        self.left_col = math.max(1, self.left_col - 1)
        self:updateLayout()
    elseif keys.KEYBOARD_CURSOR_RIGHT then
        self.left_col = math.min(#self.cols.subviews, self.left_col + 1)
        self:updateLayout()
    end
    return Spreadsheet.super.onInput(self, keys)
end

------------------------
-- Manipulator
--

Manipulator = defclass(Manipulator, widgets.Window)
Manipulator.ATTRS{
    frame_title='Unit Overview and Manipulator',
    frame={w=110, h=40},
    frame_inset={t=1, l=1, r=1, b=0},
    resizable=true,
    resize_min={w=70, h=30},
}

function Manipulator:init()
    self:addviews{
        widgets.EditField{
            view_id='search',
            frame={l=0, t=0},
            key='FILTER',
            label_text='Search: ',
            on_change=function(val) self.subviews.sheet:filter(val) end,
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
                widgets.WrappedLabel{
                    frame={t=0, l=0},
                    text_to_wrap='Use arrow keys or middle click drag to navigate cells. Left click or ENTER to toggle current cell.',
                },
                widgets.Label{
                    frame={b=2, l=0},
                    text='Current column:',
                },
                widgets.HotkeyLabel{
                    frame={b=2, l=17},
                    auto_width=true,
                    label='Sort/reverse sort',
                    key='CUSTOM_SHIFT_S',
                    on_activate=function() self.subviews.sheet:sort_by_current_row() end,
                },
                widgets.HotkeyLabel{
                    frame={b=2, l=39},
                    auto_width=true,
                    label='Hide',
                    key='CUSTOM_SHIFT_H',
                    on_activate=function() self.subviews.sheet:hide_current_row() end,
                },
                widgets.Label{
                    frame={b=1, l=0},
                    text='Current group:',
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=17},
                    auto_width=true,
                    label='Next group',
                    key='CUSTOM_CTRL_T',
                    on_activate=function()  end,
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=37},
                    auto_width=true,
                    label='Hide',
                    key='CUSTOM_CTRL_H',
                    on_activate=function() self.subviews.sheet:hide_current_row() end,
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=51},
                    auto_width=true,
                    label='Show hidden',
                    key='CUSTOM_CTRL_W',
                    on_activate=function() self.subviews.sheet:hide_current_row() end,
                },
                widgets.HotkeyLabel{
                    frame={b=0, l=0},
                    auto_width=true,
                    label='Refresh', -- TODO: add warning if citizen list has changed and needs refreshing
                    key='CUSTOM_SHIFT_R',
                    on_activate=function()
                        self.subviews.sheet:refresh()
                        self.subviews.sheet:filter(self.subviews.search.text)
                    end,
                },
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
