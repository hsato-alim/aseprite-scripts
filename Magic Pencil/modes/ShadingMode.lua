-- Magic Pencil/modes/ShadingMode.lua

local ColorContext = dofile("../ColorContext.lua")

local ShadingMode = {
    -- Return to the stable, proven Stage 1 configuration.
    -- This mode does not introduce new pixels.
    canExtend = false,
    ignoreEmptyCel = true,
    deleteOnEmptyCel = false,
    useMaskColor = true
}

function ShadingMode:Process(change, sprite, lastCel, options)
    local rampSize = tonumber(options.rampSize) or 8
    local palette = app.activeSprite.palettes[1]

    -- Work directly on the snapshot of the original image, as we did in Stage 1.
    local image = lastCel.image
    local drawPixel = image.drawPixel

    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed

    for _, pixel in ipairs(change.pixels) do
        local originalColor = pixel.color
        
        -- First, find the absolute index of the pixel's color in the main palette.
        local colorIndexInPalette = -1
        for i = 0, #palette - 1 do
            if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), originalColor) then
                colorIndexInPalette = i
                break
            end
        end

        -- If the color was found in the palette, proceed.
        if colorIndexInPalette ~= -1 then
            -- MATHEMATICAL APPROACH:
            -- 1. Calculate which ramp the color belongs to (1-based).
            local rampNumber = math.floor(colorIndexInPalette / rampSize) + 1
            
            -- 2. Check if that ramp's corresponding checkbox is active.
            if options["rampCheck" .. rampNumber] then
                -- 3. Calculate the color's position within its own ramp (1-based).
                local indexInRamp = (colorIndexInPalette % rampSize) + 1
                
                local newColor = nil

                -- Use the intuitive mouse button logic.
                if leftButtonPressed then
                    -- LMB: Decrement, but only if it's not the first color in the ramp.
                    if indexInRamp > 1 then
                        newColor = palette:getColor(colorIndexInPalette - 1)
                    end
                elseif rightPressed then
                    -- RMB: Increment, but only if it's not the last color in the ramp
                    -- AND not the last color in the entire palette.
                    if indexInRamp < rampSize and colorIndexInPalette + 1 < #palette then
                        newColor = palette:getColor(colorIndexInPalette + 1)
                    end
                end

                -- If a valid new color was found, and it's not transparent, draw it.
                if newColor and not ColorContext:IsTransparent(ColorContext:Create(newColor)) then
                    drawPixel(image, pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, newColor)
                end
            end
        end
    end

    -- Apply the final, corrected image and restore the original position.
    app.activeCel.image = image
    app.activeCel.position = lastCel.position
end

return ShadingMode
