-- A GUI front-end for autofarm
--@ module = true
--[====[
gui/autofarm
============
Graphical interface for the `autofarm` plugin. It allows you to visualize your
farm plot crop allocation and change target thresholds for your crops. It also
lets you choose which farm plots to exclude from autofarm management.
]====]

local af = require('plugins.autofarm')
local dialogs = require('gui.dialogs')
local gui = require('gui')
local guidm = require('gui.dwarfmode')
local widgets = require('gui.widgets')

-- set up some mocks until autofarm provides the real Lua API
af = af or {}
local mock_settings = {
        manage_aboveground_crops=true, -- boolean
        manage_underground_crops=true, -- boolean
        exclude_farm_plots={},  -- set<id> (i.e. map of id to anything truthy)
    }
af.get_settings = af.get_settings or function() return mock_settings end
af.set_settings = af.set_settings or function(settings) mock_settings = settings end
af.is_plot_aboveground = af.is_plot_aboveground or function() return false end
-- end mocks

local function is_tile_aboveground(pos)
    local flags = dfhack.maps.getTileFlags(pos)
    if return flags.aboveground
end

local function is_tile_managed(settings, bld.id, aboveground, pos)
    if aboveground and not settings.manage_aboveground_crops then return false end
    if not aboveground and not settings.manage_underground_crops then return false end
    if aboveground ~= is_tile_aboveground(pos) then return false end
    return not settings.exclude_farm_plots[bld.id]
end

-- scan through buildings and build farm plot metadata
local function get_plot_data(settings)
    local num_managed_plots, total_plots = 0, 0
    local num_managed_tiles, total_tiles = 0, 0
    local plot_map = {}
    for _,bld in ipairs(df.world.buildings) do
        if bld:getType() ~= df.building_types.FARM_PLOT then goto continue end
        local plot_managed = false
        local aboveground = af.is_plot_aboveground(bld)
        for x=0,bld.width-1 do for y=0,bld.height-1 do
            if bld.extents[x].value:_displace(y) == 1 then
                local zlevel = ensure_key(plot_map, bld.z)
                local mapx, mapy = bld.x1 + x, bld.y1 + y
                local bounds = ensure_key(zlevel, 'bounds',
                                          {x1=mapx, x2=mapx, y1=mapy, y2=mapy})
                local row = ensure_key(zlevel, mapy)
                local managed = is_tile_managed(settings, bld.id, aboveground,
                                                xyz2pos(mapx, mapy, bld.z))
                row[mapx] = managed
                if managed then
                    plot_managed = true
                    num_managed_tiles = num_managed_tiles + 1
                end
                total_tiles = total_tiles + 1
                bounds.x1 = math.min(bounds.x1, mapx)
                bounds.x2 = math.max(bounds.x2, mapx)
                bounds.y1 = math.min(bounds.y1, mapy)
                bounds.y2 = math.max(bounds.y2, mapy)
            end
        end end
        if plot_managed then num_managed_plots = num_managed_plots + 1 end
        total_plots = total_plots + 1
        ::continue::
    end
    return {
        num_managed_plots=num_managed_plots,
        total_plots=total_plots,
        num_managed_tiles=num_managed_tiles,
        total_tiles=total_tiles,
        plot_map=plot_map,
    }
end

AutofarmUI = defclass(AutofarmUI, guidm.MenuOverlay)
AutofarmUI.ATTRS {
    frame_inset=1,
    focus_path='autofarm',
    sidebar_mode=df.ui_sidebar_mode.LookAround,
}
function AutofarmUI:init()
    local settings = af.get_settings()
    self.data = get_plot_data(settings)
    
    local function do_update()
        af.set_settings(settings)
        self.data = get_plot_data(settings)
    end

    local subviews = {
        widgets.Label{text='Autofarm'},
        widgets.Panel{autoarrange_subviews=true, subviews={
            widgets.Label{text={'Managed farm plots: ',
                                {text=function() return tostring(self.data.num_managed_plots) end},
                                ' of ',
                                {text=function() return tostring(self.data.total_plots) end}}},
            widgets.Label{text={'Managed farm tiles: ',
                                {text=function() return tostring(self.data.num_managed_tiles) end},
                                ' of ',
                                {text=function() return tostring(self.data.total_tiles) end}}}
            }},
        widgets.ToggleHotkeyLabel{key='CUSTOM_SHIFT_A',
            label='Manage aboveground crops',
            initial_option=settings.manage_aboveground_crops,
            on_change=function(val)
                settings.manage_aboveground_crops = val
                do_update()
            end},
        widgets.ToggleHotkeyLabel{key='CUSTOM_SHIFT_U',
            label='Manage underground crops',
            initial_option=settings.manage_underground_crops,
            on_change=function(val)
                settings.manage_underground_crops = val
                do_update()
            end},
        widgets.HotkeyLabel{key='LEAVESCREEN', label='Back',
            on_activate=self:callback('dismiss')}
    }

    self:addviews{widgets.Panel{autoarrange_subviews=true,
                                autoarrange_gap=1,
                                subviews=subviews}}
end

function AutofarmUI:onRenderBody()
    if not gui.blink_visible(500) then return end

    local zlevel = self.data.plot_map[guidm.getCursorPos().z]
    if not zlevel then return end

    local function get_overlay_char(pos)
        local plot_data = safe_index(zlevel, pos.y, pos.x)
        if plot_data == nil then return nil end
        return 'X', plot_data and COLOR_GREEN or COLOR_RED
    end

    self:renderMapOverlay(get_overlay_char, zlevel.bounds)
end

function AutofarmUI:onInput(keys)
    if self:inputToSubviews(keys) then
        return true
    end

    return self:propagateMoveKeys(keys)
end

if dfhack_flags.module then
    return
end

if not dfhack.isMapLoaded() then
    qerror('This script requires a fortress map to be loaded')
end

AutofarmUI():show()
