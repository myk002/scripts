--@module = true

local gui = require("gui")
local json = require('json')
local overlay = require('plugins.overlay')
local presets = reqscript('internal/manipulator/presets')
local textures = require('gui.textures')
local utils = require('utils')
local widgets = require("gui.widgets")

------------------------
-- persistent state
--

local GLOBAL_KEY = 'manipulator'
local CONFIG_FILE = 'dfhack-config/manipulator.json'

-- persistent player (global) state schema
local function get_default_config()
    return {
        tags={},
        presets={},
    }
end

-- persistent per-fort state schema
local function get_default_state()
    return {
        favorites={},
        tagged={},
    }
end

-- preset schema
local function get_default_preset()
    return {
        hidden_groups={},
        hidden_cols={},
        pinned={},
    }
end

local function get_config()
    local data = get_default_config()
    local cfg = json.open(CONFIG_FILE)
    utils.assign(data, cfg.data)
    cfg.data = data
    return cfg
end

config = config or get_config()
state = state or get_default_state()
preset = preset or get_default_preset()

local function persist_state()
    dfhack.persistent.saveSiteData(GLOBAL_KEY, state)
end

dfhack.onStateChange[GLOBAL_KEY] = function(sc)
    if sc == SC_MAP_UNLOADED then
        state = get_default_state()
        return
    end
    if sc ~= SC_MAP_LOADED or not dfhack.world.isFortressMode() then
        return
    end
    state = get_default_state()
    utils.assign(state, dfhack.persistent.getSiteData(GLOBAL_KEY, state))
end

------------------------
-- Column
--

Column = defclass(Column, widgets.Panel)
Column.ATTRS{
    label=DEFAULT_NIL,
    group='',
    label_inset=0,
    data_width=4,
    hidden=DEFAULT_NIL,
    shared=DEFAULT_NIL,
    data_fn=DEFAULT_NIL,
    count_fn=DEFAULT_NIL,
    cmp_fn=DEFAULT_NIL,
    choice_fn=DEFAULT_NIL,
}

local CH_DOT = string.char(15)
local CH_UP = string.char(30)
local CH_DN = string.char(31)

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
                widgets.Panel{
                    view_id='col_label',
                    frame={l=self.label_inset, t=4},
                    subviews={
                        widgets.HotkeyLabel{
                            frame={l=0, t=0, w=1},
                            label=CH_DN,
                            text_pen=COLOR_LIGHTGREEN,
                            visible=function()
                                local sort_spec = self.shared.sort_stack[#self.shared.sort_stack]
                                return sort_spec.col == self and not sort_spec.rev
                            end,
                        },
                        widgets.HotkeyLabel{
                            frame={l=0, t=0, w=1},
                            label=CH_UP,
                            text_pen=COLOR_LIGHTGREEN,
                            visible=function()
                                local sort_spec = self.shared.sort_stack[#self.shared.sort_stack]
                                return sort_spec.col == self and sort_spec.rev
                            end,
                        },
                        widgets.HotkeyLabel{
                            frame={l=0, t=0, w=1},
                            label=CH_DOT,
                            text_pen=COLOR_GRAY,
                            visible=function()
                                local sort_spec = self.shared.sort_stack[#self.shared.sort_stack]
                                return sort_spec.col ~= self
                            end,
                        },
                        widgets.HotkeyLabel{
                            frame={l=1, t=0},
                            label=self.label,
                            on_activate=self:callback('sort', true),
                        },
                    },
                },
            },
        },
        widgets.Label{
            view_id='col_current',
            frame={t=7, l=1+self.label_inset, w=4},
            auto_height=false,
        },
        widgets.Label{
            view_id='col_total',
            frame={t=8, l=1+self.label_inset, w=4},
            auto_height=false,
        },
        widgets.List{
            view_id='col_list',
            frame={t=10, l=0, w=self.data_width+2}, -- +2 for the invisible scrollbar
            on_submit=self:callback('on_select'),
        },
    }

    self.subviews.col_list.scrollbar.visible = false
    self.col_data = {}
    self.dirty = true
end

-- extended by subclasses
function Column:on_select(idx, choice)
    -- conveniently, this will be nil for the namelist column itself,
    -- avoiding an infinite loop
    local namelist = self.parent_view.parent_view.namelist
    if namelist then
        namelist:setSelected(idx)
    end
end

function Column:sort(make_primary)
    local sort_stack = self.shared.sort_stack
    if make_primary then
        -- we are newly sorting by this column: reverse sort if we're already on top of the
        -- stack; otherwise put us on top of the stack
        local top = sort_stack[#sort_stack]
        if top.col == self then
            top.rev = not top.rev
        else
            for idx,sort_spec in ipairs(sort_stack) do
                if sort_spec.col == self then
                    table.remove(sort_stack, idx)
                    break
                end
            end
            table.insert(sort_stack, {col=self, rev=false})
        end
    end
    for _,sort_spec in ipairs(sort_stack) do
        local col = sort_spec.col
        if col.dirty then
            col:refresh()
        end
    end
    local compare = function(a, b)
        for idx=#sort_stack,1,-1 do
            local sort_spec = sort_stack[idx]
            local col = sort_spec.col
            local first, second
            if sort_spec.rev then
                first, second = col.col_data[b], col.col_data[a]
            else
                first, second = col.col_data[a], col.col_data[b]
            end
            if first == second then goto continue end
            if not first then return 1 end
            if not second then return -1 end
            local ret = (col.cmp_fn or utils.compare)(first, second)
            if ret ~= 0 then return ret end
            ::continue::
        end
        return 0
    end
    local order = utils.tabulate(function(i) return i end, 1, #self.shared.filtered_unit_ids)
    local spec = {compare=compare}
    self.shared.sort_order = utils.make_sort_order(order, {spec})
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

function Column:get_sorted_unit_id(idx)
    return self.shared.filtered_unit_ids[self.shared.sort_order[idx]]
end

function Column:get_sorted_data(idx)
    return self.col_data[self.shared.sort_order[idx]]
end

function Column:refresh()
    local col_data, choices = {}, {}
    local current, total = 0, 0
    local next_id_idx = 1
    for _, unit in ipairs(self:get_units()) do
        local data = self.data_fn(unit)
        local val = self.count_fn(data)
        if unit.id == self.shared.filtered_unit_ids[next_id_idx] then
            local idx = next_id_idx
            table.insert(col_data, data)
            table.insert(choices, self.choice_fn(function() return self:get_sorted_data(idx) end))
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

local function data_cmp(a, b)
    if type(a) == 'number' then return -utils.compare(a, b) end
    return utils.compare(a, b)
end

local function data_count(data)
    if not data then return 0 end
    if type(data) == 'number' then return data > 0 and 1 or 0 end
    return 1
end

local function data_choice(get_ordered_data_fn)
    return {
        text={
            {
                text=function()
                    local ordered_data = get_ordered_data_fn()
                    return (not ordered_data or ordered_data == 0) and '-' or tostring(ordered_data)
                end,
            },
        },
    }
end

DataColumn = defclass(DataColumn, Column)
DataColumn.ATTRS{
    cmp_fn=data_cmp,
    count_fn=data_count,
    choice_fn=data_choice,
}

------------------------
-- ToggleColumn
--

local ENABLED_PEN_LEFT = dfhack.pen.parse{fg=COLOR_CYAN,
        tile=curry(textures.tp_control_panel, 1), ch=string.byte('[')}
local ENABLED_PEN_CENTER = dfhack.pen.parse{fg=COLOR_LIGHTGREEN,
        tile=curry(textures.tp_control_panel, 2) or nil, ch=251} -- check
local ENABLED_PEN_RIGHT = dfhack.pen.parse{fg=COLOR_CYAN,
        tile=curry(textures.tp_control_panel, 3) or nil, ch=string.byte(']')}
local DISABLED_PEN_LEFT = dfhack.pen.parse{fg=COLOR_CYAN,
        tile=curry(textures.tp_control_panel, 4) or nil, ch=string.byte('[')}
local DISABLED_PEN_CENTER = dfhack.pen.parse{fg=COLOR_RED,
        tile=curry(textures.tp_control_panel, 5) or nil, ch=string.byte('x')}
local DISABLED_PEN_RIGHT = dfhack.pen.parse{fg=COLOR_CYAN,
        tile=curry(textures.tp_control_panel, 6) or nil, ch=string.byte(']')}

local function toggle_count(data)
    return data and 1 or 0
end

local function toggle_choice(get_ordered_data_fn)
    local function get_enabled_button_token(enabled_tile, disabled_tile)
        return {
            tile=function() return get_ordered_data_fn() and enabled_tile or disabled_tile end,
        }
    end
    return {
        text={
            get_enabled_button_token(ENABLED_PEN_LEFT, DISABLED_PEN_LEFT),
            get_enabled_button_token(ENABLED_PEN_CENTER, DISABLED_PEN_CENTER),
            get_enabled_button_token(ENABLED_PEN_RIGHT, DISABLED_PEN_RIGHT),
        },
    }
end

local function toggle_sorted_vec_data(vec, unit)
    return utils.binsearch(vec, unit.id) and true or false
end

local function toggle_sorted_vec(vec, unit_id, prev_val)
    if prev_val then
        utils.erase_sorted(vec, unit_id)
    else
        utils.insert_sorted(vec, unit_id)
    end
end

ToggleColumn = defclass(ToggleColumn, Column)
ToggleColumn.ATTRS{
    count_fn=toggle_count,
    choice_fn=toggle_choice,
    toggle_fn=DEFAULT_NIL,
}

function ToggleColumn:on_select(idx, choice)
    ToggleColumn.super.on_select(self, idx, choice)
    if not self.toggle_fn then return end
    local unit_id = self:get_sorted_unit_id(idx)
    local prev_val = self:get_sorted_data(idx)
    self.toggle_fn(unit_id, prev_val)
    self.dirty = true
end

------------------------
-- Spreadsheet
--

Spreadsheet = defclass(Spreadsheet, widgets.Panel)
Spreadsheet.ATTRS{
    get_units_fn=DEFAULT_NIL,
}

local function get_workshop_label(workshop, type_enum, bld_defs)
    if #workshop.name > 0 then
        return workshop.name
    end
    local type_name = type_enum[workshop.type]
    if type_name == 'Custom' then
        local bld_def = bld_defs[workshop.custom_type]
        if bld_def then return bld_def.code end
    end
    return type_name
end

function Spreadsheet:init()
    self.left_col = 1
    self.prev_filter = ''
    self.dirty = true

    self.shared = {
        unit_ids={},
        filtered_unit_ids={},
        sort_stack={},
        sort_order={},  -- list of indices into filtered_unit_ids (or cache.filtered_units)
        cache={},       -- cached pointers; reset at end of frame
    }

    local cols = widgets.Panel{}
    self.cols = cols

    cols:addviews{
        ToggleColumn{
            view_id='favorites',
            group='tags',
            label='Favorites',
            shared=self.shared,
            data_fn=curry(toggle_sorted_vec_data, state.favorites),
            toggle_fn=function(unit_id, prev_val)
                toggle_sorted_vec(state.favorites, unit_id, prev_val)
                persist_state()
            end,
        },
        DataColumn{
            group='summary',
            label='Stress',
            shared=self.shared,
            data_fn=function(unit) return unit.status.current_soul.personality.stress end,
            choice_fn=function(get_ordered_data_fn)
                return {
                    text={
                        {
                            text=function()
                                local ordered_data = get_ordered_data_fn()
                                if ordered_data > 99999 then
                                    return '>99k'
                                elseif ordered_data > 9999 then
                                    return ('%3dk'):format(ordered_data // 1000)
                                elseif ordered_data < -99999 then
                                    return ' -' .. string.char(236)  -- -∞
                                elseif ordered_data < -999 then
                                    return ('%3dk'):format(-(-ordered_data // 1000))
                                end
                                return ('%4d'):format(ordered_data)
                            end,
                            pen=function()
                                local ordered_data = get_ordered_data_fn()
                                local level = dfhack.units.getStressCategoryRaw(ordered_data)
                                local is_graphics = dfhack.screen.inGraphicsMode()
                                -- match colors of stress faces depending on mode
                                if level == 0 then return COLOR_RED end
                                if level == 1 then return COLOR_LIGHTRED end
                                if level == 2 then return is_graphics and COLOR_BROWN or COLOR_YELLOW end
                                if level == 3 then return is_graphics and COLOR_YELLOW or COLOR_WHITE end
                                if level == 4 then return is_graphics and COLOR_CYAN or COLOR_GREEN end
                                if level == 5 then return is_graphics and COLOR_GREEN or COLOR_LIGHTGREEN end
                                return is_graphics and COLOR_LIGHTGREEN or COLOR_LIGHTCYAN
                            end,
                        },
                    },
                }
            end,
        }
    }

    for i in ipairs(df.job_skill) do
        local caption = df.job_skill.attrs[i].caption
        if caption then
            cols:addviews{
                DataColumn{
                    group='skills',
                    label=caption,
                    shared=self.shared,
                    data_fn=function(unit)
                        return (utils.binsearch(unit.status.current_soul.skills, i, 'id') or {rating=0}).rating
                    end,
                }
            }
        end
    end

    local work_details = df.global.plotinfo.labor_info.work_details
    for _, wd in ipairs(work_details) do
        cols:addviews{
            ToggleColumn{
                group='work details',
                label=wd.name,
                shared=self.shared,
                data_fn=curry(toggle_sorted_vec_data, wd.assigned_units),
                toggle_fn=function(unit_id, prev_val)
                    toggle_sorted_vec(wd.assigned_units, unit_id, prev_val)
                    -- TODO: poke DF to actually apply the work details to units
                end,
            }
        }
    end

    local function add_workshops(vec, type_enum, type_defs)
        for _, workshop in ipairs(vec) do
            cols:addviews{
                ToggleColumn{
                    group='workshops',
                    label=get_workshop_label(workshop, type_enum, type_defs),
                    shared=self.shared,
                    data_fn=curry(toggle_sorted_vec_data, workshop.profile.permitted_workers),
                    toggle_fn=function(unit_id, prev_val)
                        if not prev_val then
                            -- there can be only one
                            workshop.profile.permitted_workers:resize(0)
                        end
                        toggle_sorted_vec(workshop.profile.permitted_workers, unit_id, prev_val)
                    end,
                }
            }
        end
    end
    add_workshops(df.global.world.buildings.other.FURNACE_ANY, df.furnace_type, df.global.world.raws.buildings.furnaces)
    add_workshops(df.global.world.buildings.other.WORKSHOP_ANY, df.workshop_type, df.global.world.raws.buildings.workshops)

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
            label='Name',
            label_inset=8,
            data_fn=dfhack.units.getReadableName,
            data_width=30,
            shared=self.shared,
        },
        cols,
    }

    -- set up initial sort: primary favorites, secondary name
    self.shared.sort_stack[1] = {col=self.subviews.name, rev=false}
    self.shared.sort_stack[2] = {col=self.subviews.favorites, rev=false}

    self.namelist = self.subviews.name.subviews.col_list
    self:addviews{
            widgets.Scrollbar{
            view_id='scrollbar',
            frame={t=7, r=0},
            on_scroll=self.namelist:callback('on_scrollbar'),
        }
    }
    self.namelist.scrollbar = self.subviews.scrollbar
    self.namelist:setFocus(true)

    self:update_headers()
end

function Spreadsheet:sort_by_current_col()
    -- TODO
end

function Spreadsheet:zoom_to_prev_group()
    -- TODO
end

function Spreadsheet:zoom_to_next_group()
    -- TODO
end

function Spreadsheet:hide_current_col()
    -- TODO
end

function Spreadsheet:hide_current_col_group()
    -- TODO
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

-- TODO: support column addressing for searching/filtering (e.g. "skills/Armoring:>10")
function Spreadsheet:refresh(filter, full_refresh)
    local shared = self.shared
    shared.fault = false
    self.subviews.name.dirty = true
    for _, col in ipairs(self.cols.subviews) do
        col.dirty = true
    end
    local incremental = not full_refresh and self.prev_filter and filter:startswith(self.prev_filter)
    if not incremental then
        local units = self.get_units_fn()
        shared.cache.units = units
        shared.unit_ids = utils.tabulate(function(idx) return units[idx].id end, 1, #units)
    end
    shared.filtered_unit_ids = copyall(shared.unit_ids)
    if #filter > 0 then
        local col = self.subviews.name
        col:refresh()
        for idx=#col.col_data,1,-1 do
            local data = col.col_data[idx]
            if (not utils.search_text(data, filter)) then
                table.remove(shared.filtered_unit_ids, idx)
            end
        end
        if #col.col_data ~= #shared.filtered_unit_ids then
            col.dirty = true
        end
    end
    shared.sort_stack[#shared.sort_stack].col:sort()
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
        self:refresh(self.prev_filter, true)
        self:updateLayout()
    end
    local page_top = self.namelist.page_top
    local selected = self.namelist:getSelected()
    for _, col in ipairs(self.cols.subviews) do
        col.subviews.col_list.page_top = page_top
        col.subviews.col_list:setSelected(selected)
    end
    Spreadsheet.super.render(self, dc)
    self.shared.cache = {}
end

function Spreadsheet:get_num_visible_cols()
    local count = 0
    for _,col in ipairs(self.cols.subviews) do
        if col.visible then
            count = count + 1
        end
    end
    return count
end

function Spreadsheet:onInput(keys)
    if keys.KEYBOARD_CURSOR_LEFT then
        self.left_col = math.max(1, self.left_col - 1)
        self:updateLayout()
    elseif keys.KEYBOARD_CURSOR_LEFT_FAST then
        self.left_col = math.max(1, self.left_col - self:get_num_visible_cols())
        self:updateLayout()
    elseif keys.KEYBOARD_CURSOR_RIGHT then
        self.left_col = math.min(#self.cols.subviews, self.left_col + 1)
        self:updateLayout()
    elseif keys.KEYBOARD_CURSOR_RIGHT_FAST then
        self.left_col = math.min(#self.cols.subviews, self.left_col + self:get_num_visible_cols())
        self:updateLayout()
    end
    return Spreadsheet.super.onInput(self, keys)
end

------------------------
-- Manipulator
--

local REFRESH_MS = 1000

Manipulator = defclass(Manipulator, widgets.Window)
Manipulator.ATTRS{
    frame_title='Unit Overview and Manipulator',
    frame={w=110, h=40},
    frame_inset={t=1, l=1, r=1, b=0},
    resizable=true,
    resize_min={w=70, h=30},
}

function Manipulator:init()
    if dfhack.world.isFortressMode() then
        self.get_units_fn = dfhack.units.getCitizens
    elseif dfhack.world.isAdventureMode() then
        self.get_units_fn = qerror('get party members')
    else
        self.get_units_fn = function() return utils.clone(df.global.world.units.active) end
    end

    self.needs_refresh, self.prev_unit_count, self.prev_last_unit_id = false, 0, -1
    self:update_needs_refresh(true)

    self:addviews{
        widgets.EditField{
            view_id='search',
            frame={l=0, t=0},
            key='FILTER',
            label_text='Search: ',
            on_change=function(text) self.subviews.sheet:refresh(text, false) end,
            on_unfocus=function() self.subviews.sheet.namelist:setFocus(true) end,
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
            get_units_fn=self.get_units_fn,
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
                    on_activate=function() self.subviews.sheet:sort_by_current_col() end,
                },
                widgets.HotkeyLabel{
                    frame={b=2, l=39},
                    auto_width=true,
                    label='Hide',
                    key='CUSTOM_SHIFT_H',
                    on_activate=function() self.subviews.sheet:hide_current_col() end,
                },
                widgets.Label{
                    frame={b=1, l=0},
                    text='Current group:',
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=17},
                    auto_width=true,
                    label='Prev group',
                    key='CUSTOM_CTRL_Y',
                    on_activate=function() self.subviews.sheet:zoom_to_prev_group() end,
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=37},
                    auto_width=true,
                    label='Next group',
                    key='CUSTOM_CTRL_T',
                    on_activate=function() self.subviews.sheet:zoom_to_next_group() end,
                },
                widgets.HotkeyLabel{
                    frame={b=1, l=57},
                    auto_width=true,
                    label='Hide',
                    key='CUSTOM_CTRL_H',
                    on_activate=function() self.subviews.sheet:hide_current_col_group() end,
                },
                widgets.HotkeyLabel{
                    frame={b=0, l=0},
                    auto_width=true,
                    label=function()
                        return self.needs_refresh and 'Refresh (unit list has changed)' or 'Refresh'
                    end,
                    text_pen=function()
                        return self.needs_refresh and COLOR_LIGHTRED or COLOR_GRAY
                    end,
                    key='CUSTOM_SHIFT_R',
                    on_activate=function()
                        self.subviews.sheet:refresh(self.subviews.search.text, true)
                    end,
                },
            },
        },
    }
end

function Manipulator:update_needs_refresh(initialize)
    self.next_refresh_ms = dfhack.getTickCount() + REFRESH_MS

    local units = self.get_units_fn()
    local unit_count = #units
    if unit_count ~= self.prev_unit_count then
        self.needs_refresh = true
        self.prev_unit_count = unit_count
    end
    if unit_count <= 0 then
        self.prev_last_unit_id = -1
    else
        local last_unit_id = units[#units]
        if last_unit_id ~= self.prev_last_unit_id then
            self.needs_refresh = true
            self.prev_last_unit_id = last_unit_id
        end
    end
    if initialize then
        self.needs_refresh = false
    end
end

function Manipulator:render(dc)
    if self.next_refresh_ms <= dfhack.getTickCount() then
        self:update_needs_refresh()
    end
    Manipulator.super.render(self, dc)
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
    default_pos={x=50, y=-6},
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

if not dfhack.isMapLoaded() then
    qerror("This script requires a map to be loaded")
end

view = view and view:raise() or ManipulatorScreen{}:show()
