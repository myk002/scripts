-- A GUI front-end for autofarm
--@ module = true
--[====[
gui/autofarm
============
Graphical interface for the `autofarm` plugin. It allows you to visualize your
farm plot crop allocation and change target thresholds for your crops. It also
lets you select farm plots to exclude from autofarm management.
]====]

local gui = require('gui')
local guidm = require('gui.dwarfmode')
local widgets = require('gui.widgets')

local function is_tile_aboveground(pos)
    local flags = dfhack.maps.getTileFlags(pos)
    return not flags.subterranean
end

local function is_tile_managed(settings, bld, aboveground, pos)
    if aboveground and not settings.manage_aboveground_crops then return false end
    if not aboveground and not settings.manage_underground_crops then return false end
    if aboveground ~= is_tile_aboveground(pos) then return false end
    return not settings.exclude_farm_plots[bld.id]
end

-- set up some mocks until autofarm provides a real Lua API

local af = {}
-- load the real plugin API if we can and let it override our mocks
dfhack.pcall(function() af = require('plugins.autofarm') end)
local mock_settings = {
        manage_aboveground_crops=true, -- boolean
        manage_underground_crops=true, -- boolean
        exclude_farm_plots={},  -- set<id> (i.e. map of building id to true)
        default_threshold=50,
        thresholds={HELMET_PLUMP=150}, -- map of plant ids to custom thresholds
    }
af.get_settings = af.get_settings or function() return mock_settings end
af.set_settings = af.set_settings or function(settings)
        mock_settings = copyall(settings)
        mock_settings.exclude_farm_plots = copyall(settings.exclude_farm_plots)
    end
af.is_plot_aboveground = af.is_plot_aboveground or function(bld)
        return is_tile_aboveground(xyz2pos(bld.x1, bld.y1, bld.z))
    end
af.get_num_plantable_seeds = af.get_num_plantable_seeds or function()
        return 123
    end
af.get_num_growable_plants = af.get_num_growable_plants or function()
        return 321
    end
af.get_plant_data = af.get_plant_data or function()
        return {
            {name='Plump Helmets', id='HELMET_PLUMP', num_plants=350,
             num_seeds=40, percent_map_plantable=75},
        }
    end
af.dry_run = af.dry_run or function(settings)
        return {
            HELMET_PLUMP={plots=4, tiles=20},
        }
    end

-- end mocks

local function is_in_extent(bld, x, y)
    local extents = bld.room.extents
    if not extents then return true end -- farm plot is solid
    local yoff = (y - bld.y1) * (bld.x2 - bld.x1 + 1)
    local xoff = x - bld.x1
    return extents[yoff+xoff] == 1
end

-- scan through buildings and build farm plot metadata for the display
local function get_plot_data(settings)
    local season = df.global.cur_season
    local plots = df.global.world.buildings.other[
            df.buildings_other_id.FARM_PLOT]

    local num_managed_plots, total_plots = 0, 0
    local num_managed_tiles, total_tiles = 0, 0
    local plot_map = {} -- coordinate map for managed/unmanaged plot tiles
    local plant_allocs = {} -- allocation metadata for each plant type

    for _,bld in ipairs(plots) do
        if bld:getBuildStage() ~= bld:getMaxBuildStage() then
            goto plot_continue
        end
        local plot_managed = false
        local aboveground = af.is_plot_aboveground(bld)
        local plot_tiles = 0
        for x=bld.x1,bld.x2 do for y=bld.y1,bld.y2 do
            if not is_in_extent(bld, x, y) then goto tile_continue end
            local zlevel = ensure_key(plot_map, bld.z)
            local bounds = ensure_key(zlevel,'bounds',{x1=x, x2=x, y1=y, y2=y})
            local row = ensure_key(zlevel, y)
            local managed = is_tile_managed(settings, bld, aboveground,
                                            xyz2pos(x, y, bld.z))
            row[x] = {managed=managed, id=bld.id}
            if managed then
                plot_managed = true
            end
            plot_tiles = plot_tiles + 1
            bounds.x1 = math.min(bounds.x1, x)
            bounds.x2 = math.max(bounds.x2, x)
            bounds.y1 = math.min(bounds.y1, y)
            bounds.y2 = math.max(bounds.y2, y)
            ::tile_continue::
        end end
        local plant_id = bld.plant_id[season]
        if plant_id ~= -1 then
            local plant_alloc = ensure_key(plant_allocs, plant_id)
            ensure_key(plant_alloc, 'plots', 0)
            ensure_key(plant_alloc, 'tiles', 0)
            plant_alloc.plots = plant_alloc.plots + 1
            plant_alloc.tiles = plant_alloc.tiles + plot_tiles
        end
        if plot_managed then
            num_managed_tiles = num_managed_tiles + plot_tiles
            num_managed_plots = num_managed_plots + 1
        end
        total_tiles = total_tiles + plot_tiles
        total_plots = total_plots + 1
        ::plot_continue::
    end
    return {
        num_managed_plots=num_managed_plots,
        total_plots=total_plots,
        num_managed_tiles=num_managed_tiles,
        total_tiles=total_tiles,
        plot_map=plot_map,
        plant_allocs=plant_allocs,
    }
end

AutofarmDetails = defclass(AutofarmDetails, gui.FramedScreen)
AutofarmDetails.ATTRS {
    focus_path='autofarm/details',
    frame_style=gui.GREY_LINE_FRAME,
    frame_inset=1,
    frame_title='Autofarm Crop Threshold Details'
}

-- formats the given parameters with the correct field widths for display
local function make_details_line(name, id, threshold, seeds, plants, plantable)
    -- plant name
    -- plant id string
    -- target threshold
    -- plants on hand
    -- seeds on hand
    -- percent of map where this plant is plantable
    -- farm plots currently allocated to this plant
    -- plot tiles currently allocated to this plant
    -- farm plots allocated to this plant on next update
    -- plot tiles allocated to this plant on next update
end

function AutofarmDetails:init(args)
    local settings = af.get_settings()
    local plant_data = af.get_plant_data()
    local next_allocs = af.dry_run(settings)
    local cur_allocs = args.cur_allocs
end

function AutofarmDetails:onInput(keys)
    if self:inputToSubviews(keys) then
        return true
    end

    if keys.LEAVESCREEN then
        self:dismiss()
    end
end

AutofarmUI = defclass(AutofarmUI, guidm.MenuOverlay)
AutofarmUI.ATTRS {
    frame_inset=1,
    focus_path='autofarm',
    sidebar_mode=df.ui_sidebar_mode.Default,
}

function AutofarmUI:init()
    self:refresh_data()

    local settings = af.get_settings()
    local num_seeds = af.get_num_plantable_seeds()
    local num_plants = af.get_num_growable_plants()

    local subviews = {
        widgets.Label{text='Autofarm'},
        widgets.WrappedLabel{
            text_to_wrap=self:callback('get_help_text'),
            text_pen=COLOR_GREY},
        widgets.ResizingPanel{autoarrange_subviews=true, subviews={
            widgets.Label{text={'Managed plots: ',
                    {text=function() return self.data.num_managed_plots end},
                    ' of ',
                    {text=function() return self.data.total_plots end}}},
            widgets.Label{text={'Managed tiles: ',
                    {text=function() return self.data.num_managed_tiles end},
                    ' of ',
                    {text=function() return self.data.total_tiles end}}}
            }},
        widgets.ToggleHotkeyLabel{
            key='CUSTOM_SHIFT_A',
            label='Manage aboveground',
            initial_option=settings.manage_aboveground_crops,
            on_change=self:callback('set_setting_flag',
                                    'manage_aboveground_crops')},
        widgets.ToggleHotkeyLabel{
            key='CUSTOM_SHIFT_U',
            label='Manage underground',
            initial_option=settings.manage_underground_crops,
            on_change=self:callback('set_setting_flag',
                                    'manage_underground_crops')},
        widgets.HotkeyLabel{
            key='CUSTOM_X',
            label='Select plots to exclude',
            on_activate=self:callback('start_selection', 'exclude')},
        widgets.HotkeyLabel{
            key='CUSTOM_SHIFT_X',
            label='Select plots to include',
            on_activate=self:callback('start_selection', 'include')},
        widgets.ResizingPanel{autoarrange_subviews=true, subviews={
            widgets.Label{text={'Total plantable seeds: ' .. num_seeds}},
            widgets.Label{text={'Total growable plants: ' .. num_plants}}
            }},
        widgets.HotkeyLabel{
            key='CUSTOM_T',
            label='Crop threshold details',
            on_activate=self:callback('show_details')},
        widgets.HotkeyLabel{
            key='LEAVESCREEN',
            label=self:callback('get_back_text'),
            on_activate=self:callback('on_back')}
    }

    self:addviews{widgets.Panel{autoarrange_subviews=true,
                                autoarrange_gap=1,
                                subviews=subviews}}
end

function AutofarmUI:refresh_data(settings)
    settings = settings or af.get_settings()
    self.data = get_plot_data(settings)
end

function AutofarmUI:do_update(settings)
    af.set_settings(settings)
    self:refresh_data(settings)
end

function AutofarmUI:set_setting_flag(flag, val)
    local settings = af.get_settings()
    settings[flag] = val
    self:do_update(settings)
end

function AutofarmUI:get_help_text()
    if not self.mode then
        return 'Managed farm plots are highlighted in green.' ..
                ' Unmanaged farm plots are highlighted in red.'
    end

    local text = 'Select the '
    if self.mark then
        text = text .. 'second corner'
    else
        text = text .. 'first corner'
    end
    return text .. ' with the cursor or mouse.'
end

function AutofarmUI:get_back_text()
    if self.mode then
        return 'Cancel selection'
    end
    return 'Back'
end

function AutofarmUI:on_back()
    if self.mark then
        self.mark = nil
    elseif self.mode then
        self:cancel_selection()
    else
        self:dismiss()
    end
end

function AutofarmUI:show_details()
    AutofarmDetails{cur_allocs=self.data.plant_allocs}:show()
end

function AutofarmUI:get_bounds(cursor)
    local cursor = cursor or guidm.getCursorPos()
    local mark = self.mark

    return {
        x1=math.min(cursor.x, mark.x),
        x2=math.max(cursor.x, mark.x),
        y1=math.min(cursor.y, mark.y),
        y2=math.max(cursor.y, mark.y),
        z1=math.min(cursor.z, mark.z),
        z2=math.max(cursor.z, mark.z)
    }
end

function AutofarmUI:render_selection_overlay()
    local cursor = guidm.getCursorPos()
    if not cursor or not self.mark or not gui.blink_visible(500) then return end


    local function get_selection_overlay_char(pos, is_cursor)
        if is_cursor then return nil end
        return 'X', self.mode == 'include' and COLOR_GREEN or COLOR_RED
    end

    self:renderMapOverlay(get_selection_overlay_char, self:get_bounds(cursor))
end

function AutofarmUI:render_farm_overlay()
    if not gui.blink_visible(1000) then return end

    local zlevel = self.data.plot_map[df.global.window_z]
    if not zlevel then return end

    local function get_farm_overlay_char(pos, is_cursor)
        if is_cursor then return nil end
        local plot_data = safe_index(zlevel, pos.y, pos.x)
        if plot_data == nil then return nil end
        return 'X', plot_data.managed and COLOR_GREEN or COLOR_RED
    end

    self:renderMapOverlay(get_farm_overlay_char, zlevel.bounds)
end

function AutofarmUI:onRenderBody()
    self:render_farm_overlay()
    self:render_selection_overlay()
end

function AutofarmUI:onInput(keys)
    if self:inputToSubviews(keys) then
        return true
    end

    local pos = nil
    if keys._MOUSE_L then
        local x, y = dfhack.screen.getMousePos()
        if gui.is_in_rect(self.df_layout.map, x, y) then
            pos = xyz2pos(df.global.window_x + x - 1,
                          df.global.window_y + y - 1,
                          df.global.window_z)
            guidm.setCursorPos(pos)
        end
    elseif keys.SELECT then
        pos = guidm.getCursorPos()
    end

    if pos then
        if self.mark then
            self:commit_selection(pos)
        else
            self:set_mark(pos)
        end
        return true
    end

    return self:propagateMoveKeys(keys)
end

function AutofarmUI:start_selection(mode)
    self.mode = mode
    self:updateLayout() -- refresh help text

    -- get a cursor on the screen
    self:sendInputToParent('D_LOOK')
end

function AutofarmUI:set_mark(pos)
    self.mark = pos
    self:updateLayout() -- refresh help text
end

function AutofarmUI:cancel_selection()
    self.mode = nil
    self.mark = nil
    self:updateLayout() -- refresh help text

    -- return to the Default (cursorless) viewscreen
    self:sendInputToParent('LEAVESCREEN')
end

function AutofarmUI:commit_selection()
    -- scan for affected plots
    local plot_map, is_exclude = self.data.plot_map, self.mode == 'exclude'
    local bounds = self:get_bounds()
    local settings = af.get_settings()
    local exclude_map = settings.exclude_farm_plots

    for z=bounds.z1,bounds.z2 do
        for y=bounds.y1,bounds.y2 do
            for x=bounds.x1,bounds.x2 do
                local plot_data = safe_index(plot_map, z, y, x)
                if not plot_data then goto continue end
                exclude_map[plot_data.id] = is_exclude or nil
                ::continue::
            end
        end
    end

    self:do_update(settings)
    self:cancel_selection()
end

if dfhack_flags.module then
    return
end

if not dfhack.isMapLoaded() then
    qerror('This script requires a fortress map to be loaded')
end

AutofarmUI():show()
