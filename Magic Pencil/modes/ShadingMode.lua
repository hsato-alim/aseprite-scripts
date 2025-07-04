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

    -- Smart Source: Find the single lightest/darkest color IN THE EXISTING CEL IMAGE
    local sourceIndexInPalette = -1
    local lightestIndex = -1
    local darkestIndex = -1

    if shiftAmountForSmartSource == 1 then -- Shading Darker: Find LIGHTEST from cel
        lightestIndex = #palette -- Start with a value higher than any possible index
    end
    -- For darkestIndex, initial -1 is fine.

    for _, p_coord in ipairs(change.pixels) do -- Iterate through brush coordinates
        local cel_x = p_coord.x - lastCel.position.x
        local cel_y = p_coord.y - lastCel.position.y

        if cel_x >= 0 and cel_x < image.width and cel_y >= 0 and cel_y < image.height then
            local originalCelValue = image:getPixel(cel_x, cel_y) -- Read from lastCel.image (aliased as 'image')

            -- Assuming RGBA mode as per user instruction
            local r,g,b,a = app.pixelColor.rgba(originalCelValue)

            if a > 0 then -- Only consider non-transparent pixels FROM THE CEL
                -- Create a color object for comparison that ColorContext understands
                -- This assumes ColorContext:Create can handle a table like {red=r, green=g, blue=b, alpha=a}
                -- or that pixel.color from change.pixels was already in a format Create could use.
                -- For direct RGBA values, it's often better to construct an app.Color if ColorContext expects that.
                -- However, to match existing pattern of comparing with palette colors:
                local celColorForComparison = ColorContext:Create({red=r, green=g, blue=b, alpha=a})

                local currentCelPaletteIndex = -1
                for i = 0, #palette - 1 do
                    if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), celColorForComparison) then
                        currentCelPaletteIndex = i
                        break
                    end
                end

                if currentCelPaletteIndex ~= -1 then
                    if shiftAmountForSmartSource == 1 then -- Darker: Find LIGHTEST
                        if currentCelPaletteIndex < lightestIndex then
                            lightestIndex = currentCelPaletteIndex
                        end
                    elseif shiftAmountForSmartSource == -1 then -- Lighter: Find DARKEST
                         if darkestIndex == -1 or currentCelPaletteIndex > darkestIndex then -- check for initial -1
                            darkestIndex = currentCelPaletteIndex
                        end
                    end
                end
            end
        end
    end

    if shiftAmountForSmartSource == 1 then
        if lightestIndex < #palette then
            sourceIndexInPalette = lightestIndex
        else
            sourceIndexInPalette = -1 -- Ensure -1 if no valid lightest color found
        end
    elseif shiftAmountForSmartSource == -1 then
        -- darkestIndex remains -1 if no valid darkest color found
        sourceIndexInPalette = darkestIndex
    end

    if sourceIndexInPalette == -1 then return end -- No valid non-transparent source color found on the cel, so exit.

    -- Determine Primary Ramp details and the target local index from the source's shift
    local primaryRampNumber = math.floor(sourceIndexInPalette / rampSize) + 1

    local shiftedPrimarySourceIndex = sourceIndexInPalette
    local primarySourceDidShift = false
    if options["rampCheck" .. primaryRampNumber] then -- Only consider shifting source if its own ramp is active
        local initiallyShiftedIndex = sourceIndexInPalette
        if leftButtonPressed then
            initiallyShiftedIndex = activeLut.shiftLeft[sourceIndexInPalette]
        elseif rightPressed then
            initiallyShiftedIndex = activeLut.shiftRight[sourceIndexInPalette]
        end

        if initiallyShiftedIndex ~= sourceIndexInPalette then
            shiftedPrimarySourceIndex = initiallyShiftedIndex
            primarySourceDidShift = true
        end
    end
    local targetLocalIndexInRamp = shiftedPrimarySourceIndex % rampSize -- Will be local index of original if no shift occurred

    -- Process pixels
    for _, pixel in ipairs(change.pixels) do
        -- Determine original cel pixel's transparency
        local originalCelX = pixel.x - lastCel.position.x
        local originalCelY = pixel.y - lastCel.position.y
        local originalCelValue = 0 -- Default to transparent for safety if getPixel fails, though it shouldn't.
        -- Ensure coordinates are within image bounds before calling getPixel
        if originalCelX >= 0 and originalCelX < image.width and originalCelY >= 0 and originalCelY < image.height then
            originalCelValue = lastCel.image:getPixel(originalCelX, originalCelY)
        else
            goto continue_pixel_loop -- Pixel from change data is outside cel bounds, skip.
        end

        local isOriginalCelPixelFullyTransparent = false
        if sprite.colorMode == ColorMode.RGB then -- Primary RGBA case
            local r_val, g_val, b_val, a_val = app.pixelColor.rgba(originalCelValue) -- Use app.pixelColor for direct values
            isOriginalCelPixelFullyTransparent = (a_val == 0) -- Only skip if fully transparent
        elseif sprite.colorMode == ColorMode.INDEXED then
            isOriginalCelPixelFullyTransparent = (originalCelValue == sprite.transparentColorIndex)
        elseif sprite.colorMode == ColorMode.GRAY then
            local v_val, a_val = app.pixelColor.graya(originalCelValue) -- Use app.pixelColor for direct values
            isOriginalCelPixelFullyTransparent = (a_val == 0) -- Only skip if fully transparent
        end

        if isOriginalCelPixelFullyTransparent then
            goto continue_pixel_loop -- Skip this pixel if the cel was originally *fully* transparent here
        end

        local originalColor = pixel.color -- This is the color from the brush stroke/change.pixels (e.g. app.fgColor, or existing cel color if not transparent)
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
            -- Pixel is in a SECONDARY RAMP: Project targetLocalIndexInRamp,
            -- but only if the primary source actually shifted.
            if primarySourceDidShift then
                local currentPixelRampStartIndex = (currentPixelRampNumber - 1) * rampSize
                local projectedIndex = currentPixelRampStartIndex + targetLocalIndexInRamp

                -- Ensure projectedIndex is a valid index within the palette
                if projectedIndex >= 0 and projectedIndex < #palette then
                    newIndexInPalette = projectedIndex
                else
                    -- If projection is out of overall palette bounds, do not change.
                    newIndexInPalette = currentIndexInPalette
                end
            else
                -- If primary source didn't shift, secondary ramps also don't change via projection.
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
