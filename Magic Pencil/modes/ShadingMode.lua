-- Magic Pencil/modes/ShadingMode.lua

local ColorContext = dofile("../ColorContext.lua")

local function generateShadingLut(palette, rampSize, options, colorContext)
    local lut = {
        shiftLeft = {},
        shiftRight = {}
    }
    local paletteSize = #palette

    for i = 0, paletteSize - 1 do
        local currentRampNumber = math.floor(i / rampSize) + 1
        local isCurrentRampActive = options["rampCheck" .. currentRampNumber]

        -- Default to no shift (map to self)
        lut.shiftLeft[i] = i
        lut.shiftRight[i] = i

        if isCurrentRampActive then
            -- Calculate for shiftLeft
            local targetLeftIndex = i - 1
            if targetLeftIndex >= 0 then
                local targetLeftRampNumber = math.floor(targetLeftIndex / rampSize) + 1
                if targetLeftRampNumber == currentRampNumber then
                    local targetLeftColor = palette:getColor(targetLeftIndex)
                    if targetLeftColor and not colorContext:IsTransparent(colorContext:Create(targetLeftColor)) then
                        lut.shiftLeft[i] = targetLeftIndex
                    end
                end
            end

            -- Calculate for shiftRight
            local targetRightIndex = i + 1
            if targetRightIndex < paletteSize then
                local targetRightRampNumber = math.floor(targetRightIndex / rampSize) + 1
                if targetRightRampNumber == currentRampNumber then
                    local targetRightColor = palette:getColor(targetRightIndex)
                    if targetRightColor and not colorContext:IsTransparent(colorContext:Create(targetRightColor)) then
                        lut.shiftRight[i] = targetRightIndex
                    end
                end
            end
        end
    end
    return lut
end

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
    local drawPixel = image.drawPixel -- Assuming this is image.drawPixel correctly bound
    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed
    local tolerance = options.shadingTolerance or 0

    local activeLut = generateShadingLut(palette, rampSize, options, ColorContext)

    local shiftAmountForSmartSource = 0 -- Used for smart source direction AND tolerance check direction
    if leftButtonPressed then shiftAmountForSmartSource = -1 end
    if rightPressed then shiftAmountForSmartSource = 1 end
    if shiftAmountForSmartSource == 0 then return end -- No button pressed

    -- Smart Source: Find the single lightest/darkest color in the stroke
    local sourceIndexInPalette = -1
    if shiftAmountForSmartSource == 1 then -- Shading Darker: Find LIGHTEST
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
    elseif shiftAmountForSmartSource == -1 then -- Shading Lighter: Find DARKEST
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

    if sourceIndexInPalette == -1 then return end -- No valid source color found

    -- Determine Primary Ramp details and the target local index from the source's shift
    local primaryRampNumber = math.floor(sourceIndexInPalette / rampSize) + 1

    local shiftedPrimarySourceIndex = sourceIndexInPalette
    if options["rampCheck" .. primaryRampNumber] then -- Only consider shifting source if its own ramp is active
        if leftButtonPressed then
            shiftedPrimarySourceIndex = activeLut.shiftLeft[sourceIndexInPalette]
        elseif rightPressed then
            shiftedPrimarySourceIndex = activeLut.shiftRight[sourceIndexInPalette]
        end
    end
    local targetLocalIndexInRamp = shiftedPrimarySourceIndex % rampSize

    -- Process pixels
    for _, pixel in ipairs(change.pixels) do
        local originalColor = pixel.color
        local currentIndexInPalette = -1
        for i = 0, #palette - 1 do
            if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), originalColor) then
                currentIndexInPalette = i
                break
            end
        end

        if currentIndexInPalette == -1 then goto continue_pixel_loop end -- Skip if color not in palette

        local currentPixelRampNumber = math.floor(currentIndexInPalette / rampSize) + 1
        if not options["rampCheck" .. currentPixelRampNumber] then
            goto continue_pixel_loop -- Skip if this pixel's ramp is inactive
        end

        local newIndexInPalette = currentIndexInPalette -- Default to no change

        if currentPixelRampNumber == primaryRampNumber then
            -- Pixel is in the PRIMARY RAMP: Apply tolerance and standard LUT shift
            local isWithinTolerance = false
            if shiftAmountForSmartSource == 1 then -- Darker
                isWithinTolerance = (currentIndexInPalette <= sourceIndexInPalette + tolerance and currentIndexInPalette >= sourceIndexInPalette)
            elseif shiftAmountForSmartSource == -1 then -- Lighter
                isWithinTolerance = (currentIndexInPalette >= sourceIndexInPalette - tolerance and currentIndexInPalette <= sourceIndexInPalette)
            end

            if isWithinTolerance then
                if leftButtonPressed then
                    newIndexInPalette = activeLut.shiftLeft[currentIndexInPalette]
                elseif rightPressed then
                    newIndexInPalette = activeLut.shiftRight[currentIndexInPalette]
                end
            end
        else
            -- Pixel is in a SECONDARY RAMP: Project targetLocalIndexInRamp
            local currentPixelRampStartIndex = (currentPixelRampNumber - 1) * rampSize
            local projectedIndex = currentPixelRampStartIndex + targetLocalIndexInRamp

            -- Ensure projectedIndex is a valid index within the palette
            if projectedIndex >= 0 and projectedIndex < #palette then
                 -- And ensure it's actually within the conceptual bounds of its ramp
                 -- (e.g. if rampSize is 8, local index should be 0-7. targetLocalIndexInRamp is already 0-7)
                 -- This check is mostly to ensure that `currentPixelRampStartIndex + targetLocalIndexInRamp`
                 -- doesn't accidentally exceed palette bounds if the last ramp is smaller than rampSize.
                 -- However, `palette:getColor(projectedIndex)` will return nil if out of true palette bounds.
                newIndexInPalette = projectedIndex
            else
                 -- This case should be rare if targetLocalIndexInRamp is always < rampSize
                 -- and currentPixelRampStartIndex is valid.
                 -- Potentially clamp to last color of the current secondary ramp if something is off.
                 -- For now, if projection is out of palette, it means no change.
                 newIndexInPalette = currentIndexInPalette
            end
        end

        if newIndexInPalette ~= currentIndexInPalette then
            local newColor = palette:getColor(newIndexInPalette)
            if newColor and not ColorContext:IsTransparent(ColorContext:Create(newColor)) then
                image:drawPixel(pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, newColor)
            end
        end
        ::continue_pixel_loop::
    end

    app.activeCel.image = image
    app.activeCel.position = lastCel.position
end

return ShadingMode
