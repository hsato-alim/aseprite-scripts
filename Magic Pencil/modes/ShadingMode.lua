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

    -- Validate sprite and palette
    if not sprite then
        app.console.print("ShadingMode Error: Process function received a nil sprite.")
        return
    end
    if not sprite.palettes or not sprite.palettes[1] then
        app.console.print("ShadingMode Error: Sprite does not have a valid palette[1]. Sprite ID: " .. (sprite.id or "unknown"))
        return
    end

    local palette = sprite.palettes[1]

    if #palette == 0 then
        app.console.print("ShadingMode Warning: Palette is empty. No shading possible.")
        return
    end

    local image = lastCel.image
    -- Validate image object and its properties
    if not image or type(image.width) ~= "number" or type(image.height) ~= "number" then
        app.console.print("ShadingMode Error: lastCel.image is invalid or missing width/height properties.")
        if image then
             app.console.print("Image type: " .. type(image) .. ", width: " .. tostring(image.width) .. ", height: " .. tostring(image.height))
        else
             app.console.print("lastCel.image is nil.")
        end
        return
    end

    local rampSize = tonumber(options.rampSize) or 8
    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed
    local tolerance = options.shadingTolerance or 0

    local activeLut = generateShadingLut(palette, rampSize, options, ColorContext)

    local shiftAmountForSmartSource = 0
    if leftButtonPressed then shiftAmountForSmartSource = -1 end
    if rightPressed then shiftAmountForSmartSource = 1 end
    if shiftAmountForSmartSource == 0 then return end

    -- Smart Source: Find the single lightest/darkest color IN THE EXISTING CEL IMAGE
    local sourceIndexInPalette = -1
    local lightestIndex = -1
    local darkestIndex = -1

    if shiftAmountForSmartSource == 1 then
        lightestIndex = #palette
    end

    for _, p_coord in ipairs(change.pixels) do
        local cel_x = p_coord.x - lastCel.position.x
        local cel_y = p_coord.y - lastCel.position.y

        if cel_x >= 0 and cel_x < image.width and cel_y >= 0 and cel_y < image.height then
            local originalCelValue = image:getPixel(cel_x, cel_y)

            local r,g,b,a = app.pixelColor.rgba(originalCelValue)

            if a > 0 then
                local celColorForComparison = ColorContext:Create({red=r, green=g, blue=b, alpha=a})
                local currentCelPaletteIndex = -1
                for i = 0, #palette - 1 do
                    if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), celColorForComparison) then
                        currentCelPaletteIndex = i
                        break
                    end
                end

                if currentCelPaletteIndex ~= -1 then
                    if shiftAmountForSmartSource == 1 then
                        if currentCelPaletteIndex < lightestIndex then
                            lightestIndex = currentCelPaletteIndex
                        end
                    elseif shiftAmountForSmartSource == -1 then
                         if darkestIndex == -1 or currentCelPaletteIndex > darkestIndex then
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
            sourceIndexInPalette = -1
        end
    elseif shiftAmountForSmartSource == -1 then
        sourceIndexInPalette = darkestIndex
    end

    if sourceIndexInPalette == -1 then return end

    local primaryRampNumber = math.floor(sourceIndexInPalette / rampSize) + 1

    local shiftedPrimarySourceIndex = sourceIndexInPalette
    local primarySourceDidShift = false
    if options["rampCheck" .. primaryRampNumber] then
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
    local targetLocalIndexInRamp = shiftedPrimarySourceIndex % rampSize

    for _, pixel in ipairs(change.pixels) do
        local originalCelX = pixel.x - lastCel.position.x
        local originalCelY = pixel.y - lastCel.position.y

        if not (originalCelX >= 0 and originalCelX < image.width and originalCelY >= 0 and originalCelY < image.height) then
            goto continue_pixel_loop
        end

        local originalCelValue = image:getPixel(originalCelX, originalCelY)
        local isOriginalCelPixelFullyTransparent = false
        if sprite.colorMode == ColorMode.RGB then
            local r_val, g_val, b_val, a_val = app.pixelColor.rgba(originalCelValue)
            isOriginalCelPixelFullyTransparent = (a_val == 0)
        elseif sprite.colorMode == ColorMode.INDEXED then
            isOriginalCelPixelFullyTransparent = (originalCelValue == sprite.transparentColorIndex)
        elseif sprite.colorMode == ColorMode.GRAY then
            local v_val, a_val = app.pixelColor.graya(originalCelValue)
            isOriginalCelPixelFullyTransparent = (a_val == 0)
        end

        if isOriginalCelPixelFullyTransparent then
            goto continue_pixel_loop
        end

        local originalColor = pixel.color
        local currentIndexInPalette = -1
        for i = 0, #palette - 1 do
            if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), originalColor) then
                currentIndexInPalette = i
                break
            end
        end

        if currentIndexInPalette == -1 then goto continue_pixel_loop end

        local currentPixelRampNumber = math.floor(currentIndexInPalette / rampSize) + 1
        if not options["rampCheck" .. currentPixelRampNumber] then
            goto continue_pixel_loop
        end

        local newIndexInPalette = currentIndexInPalette

        if currentPixelRampNumber == primaryRampNumber then
            local isWithinTolerance = false
            if shiftAmountForSmartSource == 1 then
                isWithinTolerance = (currentIndexInPalette <= sourceIndexInPalette + tolerance and currentIndexInPalette >= sourceIndexInPalette)
            elseif shiftAmountForSmartSource == -1 then
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
            if primarySourceDidShift then
                local currentPixelRampStartIndex = (currentPixelRampNumber - 1) * rampSize
                local projectedIndex = currentPixelRampStartIndex + targetLocalIndexInRamp

                if projectedIndex >= 0 and projectedIndex < #palette then
                    newIndexInPalette = projectedIndex
                else
                    newIndexInPalette = currentIndexInPalette
                end
            else
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
