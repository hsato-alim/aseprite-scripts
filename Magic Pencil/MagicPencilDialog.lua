-- Magic Pencil/MagicPencilDialog.lua

local ModeProcessorProvider = dofile("./ModeProcessorProvider.lua")
local GetBoundsForPixels = dofile("./GetBoundsForPixels.lua")
local Mode = dofile("./Mode.lua")
local Tool = dofile("./Tool.lua")
local ColorContext = dofile("./ColorContext.lua")

-- Colors
local MagicPink = Color {red = 255, green = 0, blue = 255, alpha = 128}
local MagicTeal = Color {red = 0, green = 128, blue = 128, alpha = 128}

local ColorModels = {HSV = "HSV", HSL = "HSL", RGB = "RGB"}

local function RectangleContains(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width - 1 and --
    y >= rect.y and y <= rect.y + rect.height - 1
end

local function GetButtonsPressedFromEmpty(pixels)
    if #pixels == 0 then return end
    local pixel = pixels[1]
    if ColorContext:Compare(app.fgColor, pixel.newColor) then
        return true, false
    elseif ColorContext:Compare(app.bgColor, pixel.newColor) then
        return false, true
    end
    return false, false
end

local function GetButtonsPressed(pixels)
    if #pixels == 0 then return false, false end
    local leftPressed, rightPressed = false, false
    local pixel = pixels[1]
    if ColorContext:IsTransparent(app.fgColor) and
        not ColorContext:IsTransparent(pixel.newColor) then
        return false, true
    elseif ColorContext:IsTransparent(app.bgColor) and
        not ColorContext:IsTransparent(pixel.newColor) then
        return true, false
    end
    local fgColorDistance = ColorContext:Distance(pixel.newColor, app.fgColor) -
                                ColorContext:Distance(pixel.color, app.fgColor)
    local bgColorDistance = ColorContext:Distance(pixel.newColor, app.bgColor) -
                                ColorContext:Distance(pixel.color, app.bgColor)
    if fgColorDistance < bgColorDistance then
        leftPressed = true
    else
        rightPressed = true
    end
    return leftPressed, rightPressed
end

local function CalculateChangeFromEmpty(cel)
    local pixels = {}
    local pixelValue
    local getPixel = cel.image.getPixel
    for x = 0, cel.image.width - 1 do
        for y = 0, cel.image.height - 1 do
            pixelValue = getPixel(cel.image, x, y)
            if not ColorContext:IsTransparentValue(pixelValue) then
                table.insert(pixels, {
                    x = x + cel.position.x,
                    y = y + cel.position.y,
                    color = ColorContext:Create(0),
                    newColor = ColorContext:Create(pixelValue)
                })
            end
        end
    end
    local leftPressed, rightPressed = GetButtonsPressedFromEmpty(pixels)
    return {
        pixels = pixels,
        bounds = cel.bounds,
        leftPressed = leftPressed,
        rightPressed = rightPressed,
        sizeChanged = false
    }
end

local function CalculateChange(previous, next, canExtend)
    local pixels = {}
    local prevPixelValue = nil
    local getPixel = previous.image.getPixel
    local previousArea = previous.bounds.width * previous.bounds.height
    local nextArea = next.bounds.width * next.bounds.height
    if nextArea > previousArea and canExtend then
        local shift = {
            x = next.position.x - previous.position.x,
            y = next.position.y - previous.position.y
        }
        local shiftedX, shiftedY, nextPixelValue
        for x = 0, next.image.width - 1 do
            for y = 0, next.image.height - 1 do
                shiftedX = x + shift.x
                shiftedY = y + shift.y
                prevPixelValue = getPixel(previous.image, shiftedX, shiftedY)
                nextPixelValue = getPixel(next.image, x, y)
                if (shiftedX < 0 or shiftedX > previous.image.width - 1 or
                    shiftedY < 0 or shiftedY > previous.image.height - 1) then
                    if not ColorContext:IsTransparentValue(nextPixelValue) then
                        table.insert(pixels, {
                            x = x + next.position.x,
                            y = y + next.position.y,
                            color = ColorContext:Create(0),
                            newColor = ColorContext:Create(nextPixelValue)
                        })
                    end
                elseif prevPixelValue ~= nextPixelValue then
                    table.insert(pixels, {
                        x = x + next.position.x,
                        y = y + next.position.y,
                        color = ColorContext:Create(prevPixelValue),
                        newColor = ColorContext:Create(nextPixelValue)
                    })
                end
            end
        end
    else
        local shift = {
            x = previous.position.x - next.position.x,
            y = previous.position.y - next.position.y
        }
        for x = 0, previous.image.width - 1 do
            for y = 0, previous.image.height - 1 do
                prevPixelValue = getPixel(previous.image, x, y)
                if RectangleContains(next.bounds, x + previous.position.x,
                                     y + previous.position.y) then
                    local nextPixelValue =
                        getPixel(next.image, x + shift.x, y + shift.y)
                    if prevPixelValue ~= nextPixelValue then
                        table.insert(pixels, {
                            x = x + previous.position.x,
                            y = y + previous.position.y,
                            color = ColorContext:Create(prevPixelValue),
                            newColor = ColorContext:Create(nextPixelValue)
                        })
                    end
                elseif not ColorContext:IsTransparentValue(prevPixelValue) then
                    table.insert(pixels, {
                        x = x + previous.position.x,
                        y = y + previous.position.y,
                        color = ColorContext:Create(prevPixelValue),
                        newColor = ColorContext:Create(0)
                    })
                end
            end
        end
    end
    local bounds = GetBoundsForPixels(pixels)
    local leftPressed, rightPressed = GetButtonsPressed(pixels)
    return {
        pixels = pixels,
        bounds = bounds,
        leftPressed = leftPressed,
        rightPressed = rightPressed,
        sizeChanged = previous.bounds.width ~= next.bounds.width or
            previous.bounds.height ~= next.bounds.height
    }
end


local function MagicPencilDialog(options)
    local dialog
    local isRefresh = false
    local colorModel = ColorModels.HSV
    local selectedMode = Mode.Regular
    local sprite = app.activeSprite
    local lastCel
    local lastFgColor = ColorContext:Copy(app.fgColor)
    local lastBgColor = ColorContext:Copy(app.bgColor)
    local isMinimized = options.isminimized
    
    local toleranceSlider

    local function UpdateRampsUI()
        if not dialog or not dialog.data.rampSize or not sprite then return end
        local rampSize = tonumber(dialog.data.rampSize)
        if not rampSize then return end
        
        local palette = sprite.palettes[1]
        if not palette then return end

        if toleranceSlider then
            dialog:modify{ id="shadingTolerance", max = rampSize - 1 }
            if dialog.data.shadingTolerance > rampSize - 1 then
                dialog:modify{ id="shadingTolerance", value = rampSize - 1 }
            end
        end
        
        local numRamps = math.floor(#palette / rampSize)
        for i = 1, 32 do
            local checkId = "rampCheck" .. i
            local shadesId = "rampShades" .. i

            if i <= numRamps then
                local rampColors = {}
                local rampStartIndex = (i - 1) * rampSize
                for j = 0, rampSize - 1 do
                    table.insert(rampColors, palette:getColor(rampStartIndex + j))
                end
                dialog:modify{ id=checkId, visible=true }
                dialog:modify{ id=shadesId, visible=true, colors=rampColors }
            else
                dialog:modify{ id=checkId, visible=false }
                dialog:modify{ id=shadesId, visible=false }
            end
        end
    end
    
    local function RefreshDialog()
        if not sprite then return end
        local isRGB = sprite.colorMode == ColorMode.RGB
        local isIndexed = sprite.colorMode == ColorMode.INDEXED
        local isChange = selectedMode == Mode.Colorize or selectedMode == Mode.Desaturate or selectedMode == Mode.Shift
        local isShading = selectedMode == Mode.Shading
        dialog:modify{id = "selectedMode", visible = isMinimized}
              :modify{id = Mode.Regular, visible = not isMinimized}
              :modify{id = "effectSeparator", visible = not isMinimized}
              :modify{id = Mode.Graffiti, visible = not isMinimized}
              :modify{id = Mode.OutlineLive, visible = not isMinimized}
              :modify{id = "transformSeparator", visible = isRGB and not isMinimized}
              :modify{id = Mode.Cut, visible = isRGB and not isMinimized}
              :modify{id = Mode.Merge, visible = isRGB and not isMinimized}
              :modify{id = Mode.Selection, visible = isRGB and not isMinimized}
              :modify{id = "mixSeparator", visible = isRGB and not isMinimized}
              :modify{id = Mode.Desaturate, visible = isRGB and not isMinimized}
              :modify{id = Mode.Mix, visible = isRGB and not isMinimized}
              :modify{id = Mode.MixProportional, visible = isRGB and not isMinimized}
              :modify{id = "changeSeparator", visible = (isRGB or isIndexed) and not isMinimized}
              :modify{id = Mode.Outline, visible = isRGB and not isMinimized}
              :modify{id = Mode.Shift, visible = isRGB and not isMinimized}
              :modify{id = Mode.Colorize, visible = (isRGB or isIndexed) and not isMinimized}
              :modify{id = Mode.Shading, visible = isRGB and not isMinimized}
              :modify{id = "indexedModeSeparator", visible = isRGB and isChange}
              :modify{id = "indexedMode", visible = isRGB and isChange, enabled = isRGB}
              :modify{id = "rampSizeLabel", visible = isShading and isRGB}
              :modify{id = "rampSize", visible = isShading and isRGB}
              :modify{id = "shadingToleranceLabel", visible = isShading and isRGB}
              :modify{id = "shadingTolerance", visible = isShading and isRGB}
              :modify{id = "rampsSeparator", visible = isShading and isRGB}
        for i = 1, 32 do
            dialog:modify{ id="rampCheck" .. i, visible = not isMinimized and isShading and isRGB }
            dialog:modify{ id="rampShades" .. i, visible = not isMinimized and isShading and isRGB }
        end
        isRefresh = true
        dialog:show{wait = false}
        dialog:close()
        local newBounds = Rectangle(dialog.bounds)
        newBounds.width = (isMinimized and 256 or 192) * app.preferences.general["ui_scale"]
        dialog:show{wait = false, bounds = newBounds}
        if selectedMode == Mode.Shading and sprite.colorMode == ColorMode.RGB then
            UpdateRampsUI()
        end
    end

    local function UpdateLast()
        if app.activeCel then
            lastCel = { image = app.activeCel.image:clone(), position = app.activeCel.position, bounds = app.activeCel.bounds, sprite = sprite }
        else
            lastCel = { image = Image(0, 0), position = Point(0, 0), bounds = Rectangle(0, 0, 0, 0), sprite = sprite, empty = true }
        end
    end

    UpdateLast()

    local skip = false
    local onBeforeCommand = function(ev) skip = true end
    local onAfterCommand = function(ev)
        skip = false
        UpdateLast()
        if ev.name == "ChangePixelFormat" then RefreshDialog() end
    end

    local onSpriteChange = function(ev)
        if skip or app.activeCel == nil then
            UpdateLast()
            return
        end
        local modeProcessor = ModeProcessorProvider:Get(selectedMode)
        if not Tool:IsSupported(app.tool.id, modeProcessor) or selectedMode == Mode.Regular or sprite.colorMode == ColorMode.TILEMAP or app.activeLayer.isTilemap or (app.apiVersion >= 21 and ev.fromUndo) then
            UpdateLast()
            return
        end
        local change = lastCel.empty and CalculateChangeFromEmpty(app.activeCel) or CalculateChange(lastCel, app.activeCel, modeProcessor.canExtend)
        
        local celToDelete = app.activeCel
        if #change.pixels == 0 or (lastCel.empty and modeProcessor.ignoreEmptyCel) then
            -- Ignore
        elseif change.leftPressed or change.rightPressed then
            modeProcessor:Process(change, sprite, lastCel, dialog.data)
        end
        if lastCel.empty and modeProcessor.deleteOnEmptyCel and not celToDelete.sprite then
            -- Cel was already deleted by transparency fix, do nothing
        elseif lastCel.empty and modeProcessor.deleteOnEmptyCel then
            app.activeSprite:deleteCel(celToDelete)
        end
        app.refresh()
        UpdateLast()
    end

    local onBeforeCommandListener = app.events:on('beforecommand', onBeforeCommand)
    local onAfterCommandListener = app.events:on('aftercommand', onAfterCommand)
    local onChangeListener = sprite.events:on('change', onSpriteChange)
    local onSiteChange = app.events:on('sitechange', function()
        if app.activeSprite == sprite then
            UpdateLast()
            return
        end
        if sprite then
            sprite.events:off(onChangeListener)
            sprite = nil
        end
        if app.activeSprite then
            sprite = app.activeSprite
            onChangeListener = sprite.events:on('change', onSpriteChange)
            UpdateLast()
        end
        RefreshDialog()
    end)

    local function ToggleMinimize()
        isMinimized = not isMinimized
        RefreshDialog()
    end

    local function SelectMode(mode, skipColor)
        selectedMode = mode
        local isRGB = sprite and sprite.colorMode == ColorMode.RGB

        dialog:modify{id = "selectedMode", option = selectedMode}
              :modify{id = selectedMode, selected = true}
        local useMaskColor = ModeProcessorProvider:Get(selectedMode).useMaskColor
        if not skipColor then
            if useMaskColor then
                app.fgColor = MagicPink
                app.bgColor = MagicTeal
            else
                app.fgColor = lastFgColor
                app.bgColor = lastBgColor
            end
        end
        local isChange = selectedMode == Mode.Colorize or selectedMode == Mode.Desaturate or selectedMode == Mode.Shift
        local isShading = selectedMode == Mode.Shading
        dialog:modify{id = "outlineColor", visible = selectedMode == Mode.OutlineLive}
              :modify{id = "outlineSize", visible = selectedMode == Mode.OutlineLive}
              :modify{id = "outlineOtherColors", visible = selectedMode == Mode.OutlineLive}
              :modify{id = "outlineErasingEnable", visible = selectedMode == Mode.OutlineLive}
              :modify{id = "graffitiPower", visible = selectedMode == Mode.Graffiti}
              :modify{id = "graffitiSpeckEnabled", visible = selectedMode == Mode.Graffiti}
              :modify{id = "graffitiSpeckPower", visible = selectedMode == Mode.Graffiti and dialog.data.graffitiSpeckEnabled}
              :modify{id = "colorModel", visible = selectedMode == Mode.Shift}
              :modify{id = "shiftFirstOption", visible = selectedMode == Mode.Shift}
              :modify{id = "shiftFirstPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftFirstOption}
              :modify{id = "shiftSecondOption", visible = selectedMode == Mode.Shift}
              :modify{id = "shiftSecondPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftSecondOption}
              :modify{id = "shiftThirdOption", visible = selectedMode == Mode.Shift}
              :modify{id = "shiftThirdPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftThirdOption}
              :modify{id = "indexedModeSeparator", visible = isChange}
              :modify{id = "indexedMode", visible = isChange}
              :modify{id = "rampSizeLabel", visible = isShading and isRGB}
              :modify{id = "rampSize", visible = isShading and isRGB}
              :modify{id = "shadingToleranceLabel", visible = isShading and isRGB}
              :modify{id = "shadingTolerance", visible = isShading and isRGB}
              :modify{id = "rampsSeparator", visible = isShading and isRGB}
        if isShading and isRGB then
            UpdateRampsUI()
        else
            for i = 1, 32 do
                dialog:modify{ id="rampCheck" .. i, visible=false }
                dialog:modify{ id="rampShades" .. i, visible=false }
            end
        end
    end

    local resetColors = false
    local resetColorsTimer
    local onFgColorChange = function()
        local modeProcessor = ModeProcessorProvider:Get(selectedMode)
        if not (app.fgColor.rgbaPixel == MagicPink.rgbaPixel) then
            if modeProcessor.useMaskColor then
                SelectMode(Mode.Regular, true)
                resetColors = true
            end
            lastFgColor = ColorContext:Copy(app.fgColor)
        end
    end
    local onBgColorChange = function()
        local modeProcessor = ModeProcessorProvider:Get(selectedMode)
        if not (app.bgColor.rgbaPixel == MagicTeal.rgbaPixel) then
            if modeProcessor.useMaskColor then
                SelectMode(Mode.Regular, true)
                resetColors = true
            end
            lastBgColor = ColorContext:Copy(app.bgColor)
        end
    end
    local onFgColorListener = app.events:on('fgcolorchange', onFgColorChange)
    local onBgColorListener = app.events:on('bgcolorchange', onBgColorChange)

    dialog = Dialog {
        title = "Magic Pencil",
        onclose = function()
            if isRefresh then isRefresh = false; return end
            if sprite then sprite.events:off(onChangeListener) end
            app.events:off(onSiteChange)
            app.events:off(onFgColorListener)
            app.events:off(onBgColorListener)
            app.fgColor = lastFgColor
            app.bgColor = lastBgColor
            app.events:off(onBeforeCommandListener)
            app.events:off(onAfterCommandListener)
            resetColorsTimer:stop()
            options.onclose(isMinimized)
        end
    }
    local function AddMode(mode, text, selected)
        dialog:radio{id = mode, text = text, selected = selected, visible = not isMinimized, onclick = function() SelectMode(mode) end}:newrow()
    end

    local availableModes = {Mode.Regular, Mode.Graffiti, Mode.OutlineLive, Mode.Cut, Mode.Merge, Mode.Selection, Mode.Mix, Mode.MixProportional, Mode.Outline, Mode.Colorize, Mode.Desaturate, Mode.Shift, Mode.Shading}
    dialog:separator():check{id = "minimize-check", text = "Minimize", selected = isMinimized, onclick = ToggleMinimize}
    dialog:combobox{id = "selectedMode", option = Mode.Regular, options = availableModes, visible = isMinimized, onchange = function() SelectMode(dialog.data.selectedMode) end}
    
    AddMode(Mode.Regular, "Disable", true)
    dialog:separator{id = "effectSeparator", text = "Effect", visible = not isMinimized}
    AddMode(Mode.Graffiti, "Graffiti")
    dialog:slider{id = "graffitiPower", visible = false, min = 0, max = 100, value = 50}:check{id = "graffitiSpeckEnabled", visible = false, selected = true, text = "Speck", onclick = function() dialog:modify{id = "graffitiSpeckPower", visible = dialog.data.graffitiSpeckEnabled} end}:slider{id = "graffitiSpeckPower", visible = false, min = 0, max = 100, value = 20}
    AddMode(Mode.OutlineLive, "Outline")
    dialog:color{id = "outlineColor", visible = false, color = Color {gray = 0, alpha = 255}}:number{id = "outlineSize", visible = false, text = "1", decimals = 0}:check{id = "outlineOtherColors", text = "Over color", visible = false, selected = false}:newrow():check{id = "outlineErasingEnable", text = "Erasing", visible = false, selected = true}
    dialog:separator{id = "transformSeparator", text = "Transform", visible = not isMinimized}
    AddMode(Mode.Cut, "Lift")
    AddMode(Mode.Merge, "Merge")
    AddMode(Mode.Selection, "Selection")
    dialog:separator{id = "mixSeparator", text = "Mix", visible = not isMinimized}
    AddMode(Mode.Mix, "Unique")
    AddMode(Mode.MixProportional, "Proportional")
    dialog:separator{id = "changeSeparator", text = "Change", visible = not isMinimized}
    AddMode(Mode.Outline, "Outline")
    AddMode(Mode.Colorize, "Colorize")
    AddMode(Mode.Desaturate, "Desaturate")
    AddMode(Mode.Shift, "Shift")
    AddMode(Mode.Shading, "Shading")
    
    dialog:label{ id = "rampSizeLabel", text = "Ramp Size:", visible = false }:combobox{ id = "rampSize", options = { "2", "4", "8", "16", "32" }, option = "8", visible = false, onchange = UpdateRampsUI }
    dialog:label{ id = "shadingToleranceLabel", text = "Tolerance:", visible = false }
    toleranceSlider = dialog:slider{ id = "shadingTolerance", min = 0, max = 7, value = 0, visible = false }
    dialog:separator{ id = "rampsSeparator", text = "Active Ramps", visible = false }
    for i = 1, 32 do
        local check = dialog:check{ id = "rampCheck" .. i, text = "Ramp " .. i, selected = true, visible = false }
        dialog:shades{ id = "rampShades" .. i, colors = {}, visible = false, onclick = function() check.selected = not check.selected end }:newrow()
    end

    local onShiftOptionClick = function()
        dialog:modify{id = "shiftFirstPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftFirstOption}
              :modify{id = "shiftSecondPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftSecondOption}
              :modify{id = "shiftThirdPercentage", visible = selectedMode == Mode.Shift and dialog.data.shiftThirdOption}
    end
    dialog:combobox{id = "colorModel", options = ColorModels, option = colorModel, visible = false, onchange = function()
        colorModel = dialog.data.colorModel
        local firstOption = "Red"; local secondOption = "Green"; local thirdOption = "Blue"
        if colorModel == ColorModels.HSV then firstOption = "Hue"; secondOption = "Saturation"; thirdOption = "Value"
        elseif colorModel == ColorModels.HSL then firstOption = "Hue"; secondOption = "Saturation"; thirdOption = "Lightness" end
        dialog:modify{id = "shiftFirstOption", text = firstOption}:modify{id = "shiftSecondOption", text = secondOption}:modify{id = "shiftThirdOption", text = thirdOption}
    end}:check{id = "shiftFirstOption", text = "Hue", selected = true, visible = false, onclick = onShiftOptionClick}:slider{id = "shiftFirstPercentage", min = 1, max = 100, value = 5, visible = false}:check{id = "shiftSecondOption", text = "Saturation", selected = false, visible = false, onclick = onShiftOptionClick}:slider{id = "shiftSecondPercentage", min = 1, max = 100, value = 5, visible = false}:check{id = "shiftThirdOption", text = "Value", selected = false, visible = false, onclick = onShiftOptionClick}:slider{id = "shiftThirdPercentage", min = 1, max = 100, value = 5, visible = false}
    dialog:separator{id = "indexedModeSeparator"}:check{id = "indexedMode", text = "Indexed Mode"}

    resetColorsTimer = Timer {
        interval = 1 / 6,
        ontick = function()
            if resetColors then
                app.fgColor = lastFgColor
                app.bgColor = lastBgColor
                resetColors = false
            end
        end
    }
    RefreshDialog()
    resetColorsTimer:start()
    return dialog
end

return MagicPencilDialog