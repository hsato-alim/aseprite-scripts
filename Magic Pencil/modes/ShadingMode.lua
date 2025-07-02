-- Magic Pencil/modes/ShadingMode.lua
-- This is the final, functional version of the Shading brush mode.

local ColorContext = dofile("../ColorContext.lua")

local ShadingMode = {
    -- This mode does not need to draw outside the current artwork.
    canExtend = false,
    -- This mode should not run on a completely empty cel.
    ignoreEmptyCel = true,
    -- This mode does not create new cels, so it shouldn't delete them.
    deleteOnEmptyCel = false,
    -- This property tells the dialog to use the magic pink/teal colors
    -- to detect mouse clicks, which is a pattern used by other modes.
    useMaskColor = true
}

-- The Process function contains the core logic for the brush.
-- It is called by MagicPencilDialog.lua when the user draws on the canvas.
-- @param change A table containing the pixels affected by the brush stroke.
-- @param sprite The active sprite.
-- @param lastCel A snapshot of the cel *before* the user's change.
-- @param options The data table from the dialog.
function ShadingMode:Process(change, sprite, lastCel, options)
    -- This mode doesn't use any special options from the dialog, but the
    -- parameter is here to match the pattern of other modes.

    -- Get a direct reference to the image from the `lastCel` snapshot.
    -- All our drawing will be done on this image. The dialog will then
    -- handle placing this modified image back onto the canvas.
    local image = lastCel.image
    local getPixel = image.getPixel
    local drawPixel = image.drawPixel

    -- The left and right mouse button states are calculated by the dialog
    -- and included in the `change` table.
    local leftButtonPressed = change.leftPressed
    local rightPressed = change.rightPressed

    -- Loop through every pixel in the user's brush stroke.
    for _, pixel in ipairs(change.pixels) do
        -- The `change` object gives us the original color of the pixel.
        local originalColor = pixel.color

        -- We get the palette directly from the active sprite.
        local palette = app.activeSprite.palettes[1]

        -- Find the index of the original color in the palette.
        local currentColorIndex = -1 -- Default to -1 (not found)
        for i = 0, #palette - 1 do
            -- FIX: The `ColorContext:Compare` function expects two custom color tables.
            -- We must convert the native Aseprite color from `palette:getColor(i)`
            -- into a custom color table using `ColorContext:Create()` before comparing.
            if ColorContext:Compare(ColorContext:Create(palette:getColor(i)), originalColor) then
                currentColorIndex = i
                break -- Exit the loop once the color is found
            end
        end

        -- If the color is in the palette (index is not -1), we can proceed.
        if currentColorIndex ~= -1 then
            local newColor = nil

            if leftButtonPressed then
                -- On left-click, cycle forward. The modulo operator (%) ensures
                -- we wrap around from the last color back to the first.
                -- Note: Palette indices are 0-based.
                local newIndex = (currentColorIndex + 1) % #palette
                newColor = palette:getColor(newIndex)

            elseif rightPressed then
                -- On right-click, cycle backward.
                local newIndex = currentColorIndex - 1
                if newIndex < 0 then
                    newIndex = #palette - 1 -- Wrap around to the end.
                end
                newColor = palette:getColor(newIndex)
            end

            -- If a new color was determined, draw it to our working image.
            if newColor then
                -- We must subtract the cel's position to get the correct
                -- coordinates for drawing on the cel's local image.
                drawPixel(image, pixel.x - lastCel.position.x, pixel.y - lastCel.position.y, newColor)
            end
        end
    end

    -- FIX: This is the missing post-processing step.
    -- After modifying the `image` in memory, we must assign it back to the
    -- active cel to make the changes visible on the screen.
    app.activeCel.image = image
end

return ShadingMode
