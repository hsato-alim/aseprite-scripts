-- Magic Pencil/modes/ShadingMode.lua

local ColorContext = dofile("../ColorContext.lua")

local ShadingMode = {
    -- Revert canExtend to false. This mode modifies existing pixels and
    -- does not extend the artwork's boundaries.
    canExtend = false,
    ignoreEmptyCel = true,
    deleteOnEmptyCel = false,
    useMaskColor = true
}

function ShadingMode:Process(change, sprite, lastCel, options)
    -- Get the selected ramp size from the dialog, defaulting to 8.
    local rampSize = options.rampSize or 8
    local palette = app.activeSprite.palettes[1]

    -- Use our new utility function to generate the ramps.
    -- For now, we will assume all generated ramps are active.
    local activeRamps = ColorContext:GetColorRampsByDivision(palette, rampSize)

    if #activeRamps == 0 then return end

    local image = lastCel.image
    local drawPixel = image.drawPixel

    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed

    for _, pixel in ipairs(change.pixels) do
        local originalColor = pixel.color
        local foundRamp = nil
        local foundIndexInRamp = -1

        -- Find which ramp the original color belongs to.
        for _, ramp in ipairs(activeRamps) do
            for i = 1, #ramp do
                if ColorContext:Compare(ramp[i], originalColor) then
                    foundRamp = ramp
                    foundIndexInRamp = i -- This is a 1-based index.
                    break
                end
            end
            if foundRamp then break end
        end

        -- If the color was found in a ramp, proceed with cycling.
        if foundRamp then
            local newColorObject = nil

            -- USABILITY FIX: Swap mouse button logic for more intuitive feel.
            if leftButtonPressed then
                -- LMB: Cycle backward (shift left), stopping at the beginning.
                if foundIndexInRamp > 1 then
                    newColorObject = foundRamp[foundIndexInRamp - 1]
                end

            elseif rightPressed then
                -- RMB: Cycle forward (shift right), stopping at the end.
                if foundIndexInRamp < #foundRamp then
                    newColorObject = foundRamp[foundIndexInRamp + 1]
                end
            end

            -- Check if the potential new color is transparent.
            -- If it is, we set it back to nil so it won't be drawn.
            if newColorObject and ColorContext:IsTransparent(newColorObject) then
                newColorObject = nil
            end

            if newColorObject then
                -- The custom table `newColorObject` contains the native Aseprite
                -- Color object in its `.color` property. We access this directly
                -- and pass it to the drawPixel function.
                local colorToDraw = Color {
                    red = newColorObject.red,
                    green = newColorObject.green,
                    blue = newColorObject.blue,
                    alpha = newColorObject.alpha
                }
                drawPixel(image, pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, colorToDraw)
            end
        end
    end

    app.activeCel.image = image
    -- FIX: After updating the cel's image, explicitly restore its position
    -- to the position it had *before* the operation started. This prevents
    -- the cel from being shifted to the mouse-up location.
    app.activeCel.position = lastCel.position
end

return ShadingMode
