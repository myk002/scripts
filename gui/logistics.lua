local gui = require('gui')
local widgets = require('gui.widgets')
local plugin = require('plugins.logistics')

local PROPERTIES_HEADER = 'Monitor Items Marked  '
local REFRESH_MS = 10000

--
-- Logistics
--

Logistics = defclass(Logistics, widgets.Window)
Logistics.ATTRS {
    frame_title='Stockpile Logistics',
    frame={w=64, h=27},
    resizable=true,
    resize_min={h=25},
    hide_unmonitored=DEFAULT_NIL,
    manual_hide_unmonitored_touched=DEFAULT_NIL,
}

function Logistics:init()
    local minimal = false
    local saved_frame = {w=45, h=8, r=2, t=18}
    local saved_resize_min = {w=saved_frame.w, h=saved_frame.h}
    local function toggle_minimal()
        minimal = not minimal
        local swap = self.frame
        self.frame = saved_frame
        saved_frame = swap
        swap = self.resize_min
        self.resize_min = saved_resize_min
        saved_resize_min = swap
        self:updateLayout()
        self:refresh_data()
    end
    local function is_minimal()
        return minimal
    end
    local function is_not_minimal()
        return not minimal
    end

    self:addviews{
        widgets.ToggleHotkeyLabel{
            view_id='enable_toggle',
            frame={t=0, l=0, w=31},
            label='Logistics is',
            key='CUSTOM_CTRL_E',
            options={{value=true, label='Enabled', pen=COLOR_GREEN},
                     {value=false, label='Disabled', pen=COLOR_RED}},
            on_change=function(val) plugin.setEnabled(val) end,
        },
        widgets.HotkeyLabel{
            frame={r=0, t=0, w=10},
            key='CUSTOM_ALT_M',
            label=string.char(31)..string.char(30),
            on_activate=toggle_minimal},
        widgets.Label{
            view_id='minimal_summary',
            frame={t=1, l=0, h=4},
            auto_height=false,
            visible=is_minimal,
        },
        widgets.Label{
            frame={t=3, l=0},
            text='Stockpile',
            auto_width=true,
            visible=is_not_minimal,
        },
        widgets.Label{
            frame={t=3, r=0},
            text=PROPERTIES_HEADER,
            auto_width=true,
            visible=is_not_minimal,
        },
        widgets.List{
            view_id='list',
            frame={t=5, l=0, r=0, b=14},
            on_submit=self:callback('configure_stockpile'),
            visible=is_not_minimal,
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide',
            frame={b=11, l=0},
            label='Hide stockpiles with no meltable items: ',
            key='CUSTOM_CTRL_H',
            initial_option=false,
            on_change=function() self:update_choices() end,
            visible=is_not_minimal,
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide_unmonitored',
            frame={b=10, l=0},
            label='Hide unmonitored stockpiles: ',
            key='CUSTOM_CTRL_U',
            initial_option=self:getDefaultHide(),
            on_change=function()
                self:update_choices()
            end,
            visible=is_not_minimal,
        },
        widgets.HotkeyLabel{
            frame={b=9, l=0},
            label='Designate items for melting now',
            key='CUSTOM_CTRL_D',
            on_activate=function()
                plugin.logistics_designate()
                self:refresh_data()
                self:update_choices()
            end,
            visible=is_not_minimal,
        },
        widgets.Label{
            view_id='summary',
            frame={b=0, l=0},
            visible=is_not_minimal,
        },
    }

    self:refresh_data()
end

function Logistics:hasMonitoredStockpiles()
    self.data = plugin.getItemCountsAndStockpileConfigs()
    --- check to see if we have any already monitored stockpiles
    for _,c in ipairs(self.data.stockpile_configs) do
        if c.monitored then
            return true
        end
    end

    return false
end

function Logistics:getDefaultHide()
    return self:hasMonitoredStockpiles()
end

function Logistics:configure_stockpile(idx, choice)
    self.subviews.stockpile_settings:show(choice, function()
                self:refresh_data()
                self:update_choices()
            end)
end

function Logistics:update_choices()
    local list = self.subviews.list
    local name_width = list.frame_body.width - #PROPERTIES_HEADER
    local fmt = '%-'..tostring(name_width)..'s [%s]   %5d  %5d  '
    local hide_empty = self.subviews.hide:getOptionValue()
    local hide_unmonitored = self.subviews.hide_unmonitored:getOptionValue()
    local choices = {}
    for _,c in ipairs(self.data.stockpile_configs) do
        local num_items = self.data.item_counts[c.id] or 0
        if not hide_empty or num_items > 0 then
            if not hide_unmonitored or c.monitored then
                local text = (fmt):format(
                        c.name:sub(1,name_width), c.monitored and 'x' or ' ',
                        num_items or 0, self.data.premarked_item_counts[c.id] or 0)
                table.insert(choices, {text=text, data=c})
            end
        end
    end
    self.subviews.list:setChoices(choices)
    self.subviews.list:updateLayout()


end

function Logistics:refresh_data()
    self.subviews.enable_toggle:setOption(plugin.isEnabled())
    self.data = plugin.getItemCountsAndStockpileConfigs()

    local summary = self.data.summary
    local summary_text = {
        '                          Items in monitored stockpiles: ', tostring(summary.total_items),
        NEWLINE,
        'All items marked for melting (monitored piles + global): ', tostring(summary.marked_item_count_total),
        NEWLINE,

    }
    self.subviews.summary:setText(summary_text)

    local minimal_summary_text = {
        '         Items monitored: ', tostring(summary.total_items), NEWLINE,
        'Monitored Items marked for melting: ',tostring(summary.premarked_items),
    }
    self.subviews.minimal_summary:setText(minimal_summary_text)

    self.next_refresh_ms = dfhack.getTickCount() + REFRESH_MS
end


function Logistics:postUpdateLayout()
    self:update_choices()
end

-- refreshes data every 10 seconds or so
function Logistics:onRenderBody()
    if self.next_refresh_ms <= dfhack.getTickCount() then
        self:refresh_data()
        self:update_choices()
    end
end

--
-- LogisticsScreen
--

LogisticsScreen = defclass(LogisticsScreen, gui.ZScreen)
LogisticsScreen.ATTRS {
    focus_path='logistics',
}

function LogisticsScreen:init()
    self:addviews{Logistics{}}
end

function LogisticsScreen:onDismiss()
    view = nil
end

if not dfhack.isMapLoaded() then
    qerror('logistics requires a map to be loaded')
end

view = view and view:raise() or LogisticsScreen{}:show()
