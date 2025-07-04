-- Magic Pencil/modes/ShadingMode.lua

local ColorContext = dofile("../ColorContext.lua")

local ShadingMode = {
    canExtend = false,
    ignoreEmptyCel = true,
    deleteOnEmptyCel = false,
    useMaskColor = true
}

function ShadingMode:Process(change, sprite, lastCel, options)
    if not change.pixels or #change.pixels == 0 then return end

    local rampSize = tonumber(options.rampSize) or 8
    local palette = app.activeSprite.palettes[1]
    local image = lastCel.image
    local drawPixel = image.drawPixel
    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed
    local tolerance = options.shadingTolerance or 0

    -- "SMART SOURCE" & "DIRECTIONAL TOLERANCE" MODEL:
    local shiftAmount = 0
    if leftButtonPressed then shiftAmount = -1 end -- Shift Lighter
    if rightPressed then shiftAmount = 1 end -- Shift Darker
    if shiftAmount == 0 then return end

    -- 1. Scan all pixels in the stroke to find the "smart" source color.
    local sourceIndexInPalette = -1
    if shiftAmount == 1 then -- Shading Darker: Find the LIGHTEST non-transparent color.
        local lightestIndex = #palette 
        for _, pixel in ipairs(change.pixels) do
            if not ColorContext:IsTransparent(pixel.color) then
                for i = 0, #palette - 1 do
                    if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), pixel.color) then
                        if i < lightestIndex then lightestIndex = i end
                        break
                    end
                end
            end
        end
        if lightestIndex < #palette then sourceIndexInPalette = lightestIndex end

    elseif shiftAmount == -1 then -- Shading Lighter: Find the DARKEST non-transparent color.
        local darkestIndex = -1
        for _, pixel in ipairs(change.pixels) do
            if not ColorContext:IsTransparent(pixel.color) then
                for i = 0, #palette - 1 do
                    if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), pixel.color) then
                        if i > darkestIndex then darkestIndex = i end
                        break
                    end
                end
            end
        end
        if darkestIndex > -1 then sourceIndexInPalette = darkestIndex end
    end

    if sourceIndexInPalette == -1 then return end

    -- 2. Loop through all pixels again and apply the locked shift.
    for _, pixel in ipairs(change.pixels) do
        local originalColor = pixel.color
        local currentIndexInPalette = -1
        for i = 0, #palette - 1 do
            if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), originalColor) then
                currentIndexInPalette = i
                break
            end
        end

        if currentIndexInPalette ~= -1 then
            local currentRampNumber = math.floor(currentIndexInPalette / rampSize) + 1
            
            if options["rampCheck" .. currentRampNumber] then
                -- FIX: The directional tolerance logic was inverted. This is the correct logic.
                local isWithinTolerance = false
                if shiftAmount == 1 then -- Shading Darker: Affect source and colors LIGHTER than it.
                    isWithinTolerance = (currentIndexInPalette <= sourceIndexInPalette + tolerance and currentIndexInPalette >= sourceIndexInPalette)
                elseif shiftAmount == -1 then -- Shading Lighter: Affect source and colors DARKER than it.
                    isWithinTolerance = (currentIndexInPalette >= sourceIndexInPalette - tolerance and currentIndexInPalette <= sourceIndexInPalette)
                end

                if isWithinTolerance then
                    local newIndexInPalette = currentIndexInPalette + shiftAmount
                    local newRampNumber = math.floor(newIndexInPalette / rampSize) + 1

                    if newRampNumber == currentRampNumber and newIndexInPalette >= 0 and newIndexInPalette < #palette then
                        local newColor = palette:getColor(newIndexInPalette)
                        if newColor and not ColorContext:IsTransparent(ColorContext:Create(newColor)) then
                            drawPixel(image, pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, newColor)
                        end
                    end
                end
            end
        end
    end

    app.activeCel.image = image
    app.activeCel.position = lastCel.position
end

return ShadingMode
