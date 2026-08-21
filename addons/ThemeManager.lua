local ThemeManager = {
    Library = nil,

    SchemeIndexes = {
        "BackgroundColor",
        "MainColor",
        "AccentColor",
        "OutlineColor",
        "FontColor"
    }
}

function ThemeManager:SetLibrary(Library)
    ThemeManager.Library = Library
end

function ThemeManager:Update()
    local Library = ThemeManager.Library

    if not Library then
        return
    end

    for _, Index in ThemeManager.SchemeIndexes do
        local Option = Library.Options[Index]

        if not Option then
            continue
        end

        Library.Scheme[Index] = Option.Value
    end

    Library:UpdateColorsUsingRegistry()
end

function ThemeManager:CreateColorPicker(
    Groupbox: any,
    Index: string,
    Text: string
)
    local Library = ThemeManager.Library

    Groupbox:AddLabel(Text):AddColorPicker(Index, {
        Default = Library.Scheme[Index]
    })

    local Option = Library.Options[Index]

    Option:OnChanged(function()
        ThemeManager:Update()
    end)

    return Option
end

function ThemeManager:ApplyToGroupbox(Groupbox: any)
    assert(
        ThemeManager.Library,
        "Library is not set, call ThemeManager:SetLibrary(Library) first."
    )

    ThemeManager:CreateColorPicker(
        Groupbox,
        "BackgroundColor",
        "Background"
    )

    ThemeManager:CreateColorPicker(
        Groupbox,
        "MainColor",
        "Main"
    )

    ThemeManager:CreateColorPicker(
        Groupbox,
        "AccentColor",
        "Accent"
    )

    ThemeManager:CreateColorPicker(
        Groupbox,
        "OutlineColor",
        "Outline"
    )

    ThemeManager:CreateColorPicker(
        Groupbox,
        "FontColor",
        "Font"
    )

    return Groupbox
end

function ThemeManager:ApplyToTab(
    Tab: any,
    IconName: string?
)
    local Groupbox = Tab:AddGroupbox({
        Side = "Left",
        Name = "Theme",
        IconName = nil,
    })

    return ThemeManager:ApplyToGroupbox(Groupbox)
end

return ThemeManager
