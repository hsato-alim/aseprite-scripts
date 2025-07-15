-- Magic Pencil/modes/ShadingMode.lua

local ColorContext = dofile("../ColorContext.lua")

local ShadingMode = {
    canExtend = false,
    ignoreEmptyCel = true,
    deleteOnEmptyCel = true,
    useMaskColor = true
}

function ShadingMode:Process(change, sprite, lastCel, options)
    if not change.pixels or #change.pixels == 0 then return end

    -- Get options and palette
    local rampSize = tonumber(options.rampSize) or 8
    local tolerance = options.shadingTolerance or 0
    local palette = app.activeSprite.palettes[1]
    local image = lastCel.image
    local drawPixel = image.drawPixel

    -- 1. Determine shift direction from the pre-calculated change object.
    -- The main dialog script has already done the reliable color distance check for us.
    local shiftAmount = 0
    if change.leftPressed then
        shiftAmount = -1 -- Shift Left (Lighter)
    elseif change.rightPressed then
        shiftAmount = 1 -- Shift Right (Darker)
    else
        return -- No relevant button was pressed.
    end

    -- 2. Find the "Smart Source" pixel, ignoring pixels from inactive ramps
    local sourcePixel = nil
    if shiftAmount == 1 then -- Shading Right/Darker: Find the LIGHTEST color touched from an ACTIVE ramp
        local lightestIndex = #palette
        for _, pixel in ipairs(change.pixels) do
            if not ColorContext:IsTransparent(pixel.color) then
                local rampNumber = math.floor(pixel.color.index / rampSize) + 1
                if options["rampCheck" .. rampNumber] then -- Check if the ramp is active
                    if pixel.color.index < lightestIndex then
                        lightestIndex = pixel.color.index
                        sourcePixel = pixel
                    end
                end
            end
        end
    elseif shiftAmount == -1 then -- Shading Left/Lighter: Find the DARKEST color touched from an ACTIVE ramp
        local darkestIndex = -1
        for _, pixel in ipairs(change.pixels) do
            if not ColorContext:IsTransparent(pixel.color) then
                local rampNumber = math.floor(pixel.color.index / rampSize) + 1
                if options["rampCheck" .. rampNumber] then -- Check if the ramp is active
                    if pixel.color.index > darkestIndex then
                        darkestIndex = pixel.color.index
                        sourcePixel = pixel
                    end
                end
            end
        end
    end

    if not sourcePixel then return end

    -- 3. Calculate the source's local index WITHIN its ramp
    local sourceRampIndex = sourcePixel.color.index % rampSize

    -- 4. Apply local shift with directional, ramp-based tolerance check
    for _, pixel in ipairs(change.pixels) do
        if not ColorContext:IsTransparent(pixel.color) then
            local originalPaletteIndex = pixel.color.index
            local rampNumber = math.floor(originalPaletteIndex / rampSize) + 1
            
            -- Check 1: Is the pixel's ramp active in the UI?
            if options["rampCheck" .. rampNumber] then
                local pixelRampIndex = originalPaletteIndex % rampSize

                -- Check 2: Use directional tolerance on the RAMP indices
                local isWithinTolerance = false
                if shiftAmount == 1 then -- Shading Right/Darker: Affect source and colors LIGHTER than it (by ramp index).
                    isWithinTolerance = (pixelRampIndex <= sourceRampIndex + tolerance and pixelRampIndex >= sourceRampIndex)
                elseif shiftAmount == -1 then -- Shading Left/Lighter: Affect source and colors DARKER than it (by ramp index).
                    isWithinTolerance = (pixelRampIndex >= sourceRampIndex - tolerance and pixelRampIndex <= sourceRampIndex)
                end

                if isWithinTolerance then
                    -- Apply shift to the pixel's OWN index
                    local newIndexInPalette = originalPaletteIndex + shiftAmount
                    
                    -- Boundary Check: Ensure the target is within the same ramp
                    if math.floor(newIndexInPalette / rampSize) == (rampNumber - 1) then
                        local newColor = palette:getColor(newIndexInPalette)

                        -- Stopper Check: Ensure the target color is not transparent
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