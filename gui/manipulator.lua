--@module = true

local gui = require("gui")
local widgets = require("gui.widgets")
local overlay = require('plugins.overlay')

------------------------
-- Manipulator
--

Manipulator = defclass(Manipulator, widgets.Window)
Manipulator.ATTRS {
    frame_title='Unit Overview and Manipulator',
    frame={w=110, h=40},
    resizable=true,
    resize_min={w=70, h=15},
}

function Manipulator:init()
    self:addviews{
    }
end

------------------------
-- ManipulatorScreen
--

ManipulatorScreen = defclass(ManipulatorScreen, gui.ZScreen)
ManipulatorScreen.ATTRS {
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
