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

    local shiftAmountForSmartSource = 0
    if leftButtonPressed then shiftAmountForSmartSource = -1 end
    if rightPressed then shiftAmountForSmartSource = 1 end
    if shiftAmountForSmartSource == 0 then return end

    local sourceIndexInPalette = -1
    if shiftAmountForSmartSource == 1 then
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
    elseif shiftAmountForSmartSource == -1 then
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
            local isWithinTolerance = false
            if shiftAmountForSmartSource == 1 then
                isWithinTolerance = (currentIndexInPalette <= sourceIndexInPalette + tolerance and currentIndexInPalette >= sourceIndexInPalette)
            elseif shiftAmountForSmartSource == -1 then
                isWithinTolerance = (currentIndexInPalette >= sourceIndexInPalette - tolerance and currentIndexInPalette <= sourceIndexInPalette)
            end

            if isWithinTolerance then
                local newIndexInPalette = currentIndexInPalette -- Default to current if not shifted by LUT interaction

                if leftButtonPressed then
                    newIndexInPalette = activeLut.shiftLeft[currentIndexInPalette]
                elseif rightPressed then
                    newIndexInPalette = activeLut.shiftRight[currentIndexInPalette]
                end

                -- Ensure newIndexInPalette is not nil (it shouldn't be with current LUT gen logic, but good practice)
                if newIndexInPalette ~= nil and newIndexInPalette ~= currentIndexInPalette then
                    -- Boundary check already handled by LUT generation logic effectively,
                    -- as it wouldn't provide an out-of-bounds index.
                    -- Transparency of target also handled by LUT generation.
                    local newColor = palette:getColor(newIndexInPalette)
                    -- A final check on newColor itself, though palette:getColor should be reliable.
                    if newColor then
                        -- The transparency of newColor was already checked by LUT generator.
                        -- If not, an additional check here would be:
                        -- if not ColorContext:IsTransparent(ColorContext:Create(newColor)) then
                        image:drawPixel(pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, newColor)
                        -- end
                    end
                end
            end
        end
    end

    app.activeCel.image = image
    app.activeCel.position = lastCel.position
end

return ShadingMode
