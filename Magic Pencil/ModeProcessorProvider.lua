local Mode = dofile("./Mode.lua")
local RegularMode = dofile("./modes/RegularMode.lua")
local CutMode = dofile("./modes/CutMode.lua")
local GraffitiMode = dofile("./modes/GraffitiMode.lua")
local MergeMode = dofile("./modes/MergeMode.lua")
local OutlineMode = dofile("./modes/OutlineMode.lua")
local OutlineLiveMode = dofile("./modes/OutlineLiveMode.lua")
local SelectionMode = dofile("./modes/SelectionMode.lua")
local ShiftMode = dofile("./modes/ShiftMode.lua")
local ColorizeMode = dofile("./modes/ColorizeMode.lua")
local DesaturateMode = dofile("./modes/DesaturateMode.lua")
local MixMode = dofile("./modes/MixMode.lua")
local MixProportionalMode = dofile("./modes/MixProportionalMode.lua")
local YeetMode = dofile("./modes/YeetMode.lua")
local ShadingMode = dofile("./modes/ShadingMode.lua") -- Add this line

local ModeProcessorProvider = {
    modes = {
        [Mode.Regular] = RegularMode,
        [Mode.Cut] = CutMode,
        [Mode.Graffiti] = GraffitiMode,
        [Mode.Merge] = MergeMode,
        [Mode.Outline] = OutlineMode,
        [Mode.OutlineLive] = OutlineLiveMode,
        [Mode.Selection] = SelectionMode,
        [Mode.Shift] = ShiftMode,
        [Mode.Colorize] = ColorizeMode,
        [Mode.Desaturate] = DesaturateMode,
        [Mode.Mix] = MixMode,
        [Mode.MixProportional] = MixProportionalMode,
        [Mode.Yeet] = YeetMode,
        [Mode.Shading] = ShadingMode -- Add this line
    }
}

function ModeProcessorProvider:Get(mode)
    return self.modes[mode]
end

return ModeProcessorProvider
