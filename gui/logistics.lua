local gui = require('gui')
local widgets = require('gui.widgets')

Logistics = defclass(Logistics, widgets.Window)
Logistics.ATTRS {
    frame_title='Stockpile Logistics',
    frame={w=50, h=45},
    resizable=true,
    resize_min={w=50, h=20},
}

function Logistics:init()
    self:addviews{
      -- add subview widgets here
    }
end

function Logistics:onInput(keys)
    -- if required
end

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

view = view and view:raise() or LogisticsScreen{}:show()
