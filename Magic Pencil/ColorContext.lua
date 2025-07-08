local ColorContext = {}

function ColorContext:IsTransparent(color)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then
        return color.alpha == 0
    end

    return color.index == 0
end

function ColorContext:IsTransparentValue(value)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then
        return app.pixelColor.rgbaA(value) == 0
    end

    return value == 0
end

function ColorContext:Create(value)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then return Color(value) end

    return Color {index = value}
end

function ColorContext:Copy(color)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then
        return Color(color.rgbaPixel)
    end

    return Color {index = color.index}
end

function ColorContext:Compare(a, b)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then
        return a.red == b.red and a.green == b.green and a.blue == b.blue
    end

    return a.index == b.index
end

function ColorContext:Equals(a, b)
    local sprite = app.activeSprite
    if sprite and sprite.colorMode == ColorMode.RGB then
        return a.rgbaPixel == b.rgbaPixel
    end

    return a.index == b.index
end

function ColorContext:Distance(a, b)
    return math.sqrt((a.red - b.red) ^ 2 + (a.green - b.green) ^ 2 +
                         (a.blue - b.blue) ^ 2 + (a.alpha - b.alpha) ^ 2)
end

function ColorContext:DistanceRGBOnly(a, b)
    -- Ensure colors have RGB components, default to 0 if nil to avoid errors
    local rA = a.red or 0
    local gA = a.green or 0
    local bA = a.blue or 0
    local rB = b.red or 0
    local gB = b.green or 0
    local bB = b.blue or 0
    return math.sqrt((rA - rB)^2 + (gA - gB)^2 + (bA - bB)^2)
end

function ColorContext:AverageColorsRGB(colors)
    local r, g, b = 0, 0, 0

    for _, color in ipairs(colors) do
        r = r + color.red
        g = g + color.green
        b = b + color.blue
    end

    return Color {
        red = math.floor(r / #colors),
        green = math.floor(g / #colors),
        blue = math.floor(b / #colors),
        alpha = 255
    }
end

function ColorContext:AverageColorsHSV(colors)
    local h1, h2, s, v = 0, 0, 0, 0

    for _, color in ipairs(colors) do
        h1 = h1 + math.cos(math.rad(color.hsvHue))
        h2 = h2 + math.sin(math.rad(color.hsvHue))
        s = s + color.hsvSaturation
        v = v + color.hsvValue
    end

    return Color {
        hue = math.deg(math.atan(h2, h1)) % 360,
        saturation = s / #colors,
        value = v / #colors,
        alpha = 255
    }
end
-- Add this new function to the ColorContext.lua file.

--- Divides a palette into a list of smaller, equally-sized ramps.
-- @param palette The Aseprite palette object to divide.
-- @param rampSize The desired number of colors in each ramp.
-- @return A table containing all the generated ramps.
function ColorContext:GetColorRampsByDivision(palette, rampSize)
    -- FIX: The rampSize from the dialog is a string. Convert it to a number
    -- before using it in comparisons or loops.
    rampSize = tonumber(rampSize)

    local allRamps = {}
    if not palette or #palette == 0 or not rampSize or rampSize <= 0 then
        return allRamps
    end

    local currentRamp = {}
    -- Loop through the palette, 0-indexed.
    for i = 0, #palette - 1 do
        -- Add the color (as a custom ColorContext object) to the current ramp.
        table.insert(currentRamp, self:Create(palette:getColor(i)))

        -- If the current ramp is full, add it to our list of all ramps
        -- and start a new, empty one.
        if #currentRamp == rampSize then
            table.insert(allRamps, currentRamp)
            currentRamp = {}
        end
    end

    -- After the loop, if there's a partially-filled ramp left over,
    -- add that one to the list as well.
    if #currentRamp > 0 then
        table.insert(allRamps, currentRamp)
    end

    return allRamps
end

function ColorContext:GetShiftAmountFromHue(paintedColor)
    local shiftAmount = 0 -- Default to no shift if color is ambiguous or invalid
    if paintedColor then
        -- Grayscale colors might have hsvHue = 0 or nil depending on how they are created or if value is 0.
        -- Pure black/white might also have nil hue.
        -- A color is gray if saturation is 0 or value is 0 (black) or value is max and saturation is 0 (white for HSV).
        -- Aseprite's Color object has an `isGray` property.
        if paintedColor.isGray then
            shiftAmount = 0 -- Explicitly no shift for grayscale colors
        elseif paintedColor.hsvHue ~= nil then
            if paintedColor.hsvHue > 240 and paintedColor.hsvHue <= 360 then -- MagicPink hue is 300
                shiftAmount = -1 -- Assumed MagicPink influence (Lighter)
            elseif paintedColor.hsvHue >= 0 and paintedColor.hsvHue <= 240 then
                -- MagicTeal hue is 180. This range covers it and other non-pinkish hues.
                shiftAmount = 1  -- Assumed MagicTeal influence or other (Darker)
            end
            -- If hsvHue is exactly 0 or 360 (often red), it falls into the +1 shift.
            -- If hsvHue is exactly 240, it falls into the +1 shift.
            -- This logic prioritizes Teal/Darker if not clearly Pink/Lighter.
        end
    end
    return shiftAmount
end

return ColorContext
