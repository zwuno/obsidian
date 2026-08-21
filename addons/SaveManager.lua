local cloneref = cloneref or clonereference or function(instance: any)
    return instance
end

local clonefunction = clonefunction or copyfunction or function(func)
    return func
end

local HttpService: HttpService = cloneref(game:GetService("HttpService"))

--// Safe filesystem functions
local isfolder = isfolder
local isfile = isfile
local listfiles = listfiles

local isfolder_copy = clonefunction(isfolder)
local isfile_copy = clonefunction(isfile)
local listfiles_copy = clonefunction(listfiles)

local isfolder_success, isfolder_result = pcall(function()
    return isfolder_copy("test" .. tostring(math.random(1000000, 9999999)))
end)

if not isfolder_success or typeof(isfolder_result) ~= "boolean" then
    isfolder = function(folder)
        local success, result = pcall(isfolder_copy, folder)
        return success and result or false
    end

    isfile = function(file)
        local success, result = pcall(isfile_copy, file)
        return success and result or false
    end

    listfiles = function(folder)
        local success, result = pcall(listfiles_copy, folder)
        return success and result or {}
    end
end

--// Save Manager
local SaveManager = {
    Library = nil,

    Folder = "ObsidianLibSettings",
    SubFolder = "",

    Ignore = {},
    LoadingOrder = {},
    UseLoadingOrder = false,

    AutoloadConfig = nil
}

function SaveManager:SetLibrary(Library)
    SaveManager.Library = Library
end

--// Element Parser
local SpecialValueParser = {
    UDim2 = {
        Encode = function(Value: UDim2)
            return {
                X = {
                    Scale = Value.X.Scale,
                    Offset = Value.X.Offset
                },

                Y = {
                    Scale = Value.Y.Scale,
                    Offset = Value.Y.Offset
                }
            }
        end,

        Decode = function(Data: any)
            local DataType = typeof(Data)

            if DataType == "table" then
                if not Data.X or not Data.Y then
                    return nil
                end

                return UDim2.new(
                    Data.X.Scale,
                    Data.X.Offset,
                    Data.Y.Scale,
                    Data.Y.Offset
                )
            end

            if DataType == "UDim2" then
                return Data
            end

            return nil
        end
    }
}

local ElementParser = {}

do
    local function CreateParser(
        ElementType: string,
        LibraryIndex: string,
        Save: (string, any, ...any) -> any,
        Load: (any?, any) -> any,
        CustomElementFetcher: boolean?
    )
        ElementParser[ElementType] = {
            Save = function(Index: string, Element: any, ...)
                local Data = Save(Index, Element, ...)

                Data.type = ElementType
                Data.idx = Index

                return Data
            end,

            Load = function(Index: string?, Data: any)
                if CustomElementFetcher == true then
                    return Load(nil, Data)
                end

                local Elements = SaveManager.Library
                    and SaveManager.Library[LibraryIndex]

                local Element = Elements and Elements[Index]

                return Load(Element, Data)
            end
        }
    end

    CreateParser(
        "Toggle",
        "Toggles",

        function(Index: string, Toggle: any)
            return {
                value = Toggle.Value
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            if Element.Value == Data.value then
                Element:RunChanged()
                return
            end

            Element:SetValue(Data.value)
        end
    )

    CreateParser(
        "Slider",
        "Options",

        function(Index: string, Slider: any)
            return {
                value = tostring(Slider.Value)
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            if Element.Value == Data.value then
                Element:RunChanged()
                return
            end

            Element:SetValue(Data.value)
        end
    )

    CreateParser(
        "Dropdown",
        "Options",

        function(Index: string, Dropdown: any)
            return {
                value = Dropdown.Value,
                multi = Dropdown.Multi
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            if Element.Value == Data.value then
                Element:RunChanged()
                return
            end

            Element:SetValue(Data.value)
        end
    )

    CreateParser(
        "ColorPicker",
        "Options",

        function(Index: string, ColorPicker: any)
            return {
                value = ColorPicker.Value:ToHex(),
                transparency = ColorPicker.Transparency
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            Element:SetValueRGB(
                Color3.fromHex(Data.value),
                Data.transparency
            )
        end
    )

    CreateParser(
        "KeyPicker",
        "Options",

        function(Index: string, KeyPicker: any)
            return {
                mode = KeyPicker.Mode,
                key = KeyPicker.Value,
                modifiers = KeyPicker.Modifiers,
                toggled = KeyPicker.Toggled
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            Element:SetValue({
                Data.key,
                Data.mode,
                Data.modifiers
            })

            if Data.mode == "Toggle" and Data.toggled ~= nil then
                Element.Toggled = Data.toggled
                Element:Update()
            end
        end
    )

    CreateParser(
        "Input",
        "Options",

        function(Index: string, Input: any)
            return {
                text = Input.Value
            }
        end,

        function(Element: any?, Data: any)
            if not Element then
                return
            end

            if typeof(Data.text) ~= "string" then
                return
            end

            if Element.Value == Data.text then
                Element:RunChanged()
                return
            end

            Element:SetValue(Data.text)
        end
    )

    CreateParser(
        "Groupbox",
        "Tabs",

        function(Index: string, Groupbox: any, TabIndex: string)
            return {
                collapsed = Groupbox.Collapsed,
                tabIdx = TabIndex
            }
        end,

        function(_, Data: any)
            local TabIndex = Data.tabIdx
            local Index = Data.idx

            if typeof(TabIndex) ~= "string"
                or typeof(Index) ~= "string" then
                return
            end

            local Tabs = SaveManager.Library
                and SaveManager.Library.Tabs

            local Tab = Tabs and Tabs[TabIndex]

            if not Tab then
                return
            end

            local Groupbox = Tab.Groupboxes[Index]

            if not Groupbox then
                return
            end

            if Groupbox.Collapsed == Data.collapsed then
                return
            end

            Groupbox:SetCollapsed(Data.collapsed == true)
        end,

        true
    )
end

--// Helpers
local function Trim(Text: string)
    return Text:match("^%s*(.-)%s*$")
end

local function IsStringEmpty(String: string): boolean
    return typeof(String) ~= "string" or Trim(String) == ""
end

local function IsValidFolderPath(Name: string): boolean
    return typeof(Name) == "string"
        and Trim(Name) ~= ""
        and not Name:match("^%s*$")
        and not Name:find('[<>:"|%?%*%z]')
end

--// Folder helpers
local function SplitPath(Path: string): {string}
    local Result = {}
    local Current = ""

    for Part in string.gmatch(Path, "[^/]+") do
        Current = Current == ""
            and Part
            or Current .. "/" .. Part

        table.insert(Result, Current)
    end

    return Result
end

local function GetFolderPath(): false | string
    if IsStringEmpty(SaveManager.Folder) then
        return false
    end

    return string.format(
        "%s/settings",
        SaveManager.Folder
    )
end

local function GetSubFolderPath(): false | string
    if IsStringEmpty(SaveManager.Folder)
        or IsStringEmpty(SaveManager.SubFolder) then
        return false
    end

    return string.format(
        "%s/settings/%s",
        SaveManager.Folder,
        SaveManager.SubFolder
    )
end

local function GetCurrentSettingsPath(): false | string
    local SubFolderPath = GetSubFolderPath()

    if SubFolderPath ~= false then
        return SubFolderPath
    end

    return GetFolderPath()
end

--// File helpers
local function GetConfigPath(ConfigName: string): false | string
    local SettingsPath = GetCurrentSettingsPath()

    if SettingsPath == false then
        return false
    end

    return string.format(
        "%s/%s.json",
        SettingsPath,
        ConfigName
    )
end

local function DoesConfigExist(ConfigName: string): boolean
    local ConfigPath = GetConfigPath(ConfigName)

    return ConfigPath ~= false and isfile(ConfigPath)
end

local function GetAutoloadPath(): false | string
    local SettingsPath = GetCurrentSettingsPath()

    if SettingsPath == false then
        return false
    end

    return string.format(
        "%s/autoload.txt",
        SettingsPath
    )
end

--// Indexes
function SaveManager:SetLoadingOrder(
    Enabled: boolean,
    Order: {string}?
)
    SaveManager.UseLoadingOrder = Enabled == true

    if typeof(Order) == "table" then
        SaveManager.LoadingOrder = Order
    end
end

function SaveManager:SetIgnoreIndexes(Indexes: {string}?)
    assert(
        typeof(Indexes) == "table",
        "Expected table, got " .. typeof(Indexes)
    )

    for _, Index in Indexes do
        SaveManager.Ignore[Index] = true
    end
end

function SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({
        "BackgroundColor",
        "MainColor",
        "AccentColor",
        "OutlineColor",
        "FontColor",
        "FontFace",
        "BackgroundImage",

        "ThemeManager_ThemeList",
        "ThemeManager_CustomThemeList",
        "ThemeManager_CustomThemeName"
    })
end

--// Folders
function SaveManager:GetPaths(): {string}
    local SettingsPath = GetCurrentSettingsPath()

    if SettingsPath == false then
        return {}
    end

    return SplitPath(SettingsPath)
end

function SaveManager:BuildFolderTree()
    local Paths = SaveManager:GetPaths()

    if #Paths == 0 then
        return false
    end

    for _, Path in Paths do
        if not isfolder(Path) then
            local Success = pcall(makefolder, Path)

            if not Success and not isfolder(Path) then
                return false
            end
        end
    end

    return true
end

function SaveManager:CheckFolderTree()
    return SaveManager:BuildFolderTree()
end

function SaveManager:CheckSubFolder(CreateFolder: boolean)
    local SubFolderPath = GetSubFolderPath()

    if SubFolderPath == false then
        return false
    end

    local Exists = isfolder(SubFolderPath)

    if not CreateFolder then
        return Exists
    end

    if not Exists then
        local Success = pcall(makefolder, SubFolderPath)

        if not Success and not isfolder(SubFolderPath) then
            return false
        end
    end

    return true
end

function SaveManager:SetFolder(Folder: string)
    assert(
        IsValidFolderPath(Folder),
        "Invalid path provided"
    )

    SaveManager.Folder = Folder
    SaveManager:BuildFolderTree()
end

function SaveManager:SetSubFolder(SubFolder: string)
    assert(
        IsValidFolderPath(SubFolder),
        "Invalid path provided"
    )

    SaveManager.SubFolder = SubFolder
    SaveManager:BuildFolderTree()
end

--// Config Management
function SaveManager:RefreshConfigList()
    local SettingsPath = GetCurrentSettingsPath()

    if SettingsPath == false then
        return {}
    end

    local Files = listfiles(SettingsPath)

    if typeof(Files) ~= "table" then
        return {}
    end

    local FileNames = {}

    for _, FilePath in Files do
        local RawFileName = FilePath:match("(.+)%..+$")

        if not RawFileName then
            continue
        end

        local NormalizedPath = RawFileName:gsub("\\", "/")
        local FileName = NormalizedPath:match(".*/([^/]*)$")

        if not FileName then
            FileName = NormalizedPath
        end

        if FileName == "autoload" then
            continue
        end

        table.insert(FileNames, FileName)
    end

    table.sort(FileNames)

    return FileNames
end

function SaveManager:SaveJSON(ConfigName)
    local Library = SaveManager.Library
    local IgnoreIndexes = SaveManager.Ignore

    local CurrentData = {
        timestamp = os.date("%d.%m.%Y %H:%M:%S"),
        name = ConfigName or "",

        objects = {},

        keybindMenu = if Library.KeybindFrame then {
            visible = Library.KeybindFrame.Visible,

            position = SpecialValueParser.UDim2.Encode(
                Library.KeybindFrame.Position
            )
        } else nil
    }

    --// Toggles
    for Index, Toggle in Library.Toggles do
        if not Toggle.Type then
            continue
        end

        if IgnoreIndexes[Index] then
            continue
        end

        local Parser = ElementParser[Toggle.Type]

        if not Parser then
            continue
        end

        table.insert(
            CurrentData.objects,
            Parser.Save(Index, Toggle)
        )
    end

    --// Options
    for Index, Option in Library.Options do
        if not Option.Type then
            continue
        end

        if IgnoreIndexes[Index] then
            continue
        end

        local Parser = ElementParser[Option.Type]

        if not Parser then
            continue
        end

        table.insert(
            CurrentData.objects,
            Parser.Save(Index, Option)
        )
    end

    --// Groupboxes
    for TabIndex, Tab in Library.Tabs do
        if not Tab.Groupboxes then
            continue
        end

        for Index, Groupbox in Tab.Groupboxes do
            if IgnoreIndexes[Index] then
                continue
            end

            local Parser = ElementParser.Groupbox

            if not Parser then
                continue
            end

            table.insert(
                CurrentData.objects,
                Parser.Save(
                    Index,
                    Groupbox,
                    TabIndex
                )
            )
        end
    end

    local Success, EncodedData = pcall(
        HttpService.JSONEncode,
        HttpService,
        CurrentData
    )

    if not Success then
        return "", false, "Failed to encode data"
    end

    return EncodedData, true
end

function SaveManager:Save(ConfigName: string): (boolean, string?)
    if IsStringEmpty(ConfigName) then
        return false, "Invalid config name provided"
    end

    if string.lower(ConfigName) == "autoload" then
        return false, "Invalid config name provided"
    end

    local ConfigPath = GetConfigPath(ConfigName)

    if ConfigPath == false then
        return false, "Invalid config name provided"
    end

    if not SaveManager:CheckFolderTree() then
        return false, "Failed to create settings folder"
    end

    local EncodedData, SuccessEncode, EncodeErrorMessage =
        SaveManager:SaveJSON(ConfigName)

    if not SuccessEncode then
        return false, EncodeErrorMessage
    end

    local SuccessWrite, ErrorMessage =
        pcall(writefile, ConfigPath, EncodedData)

    if not SuccessWrite then
        return false,
            "Failed to write config file: "
            .. tostring(ErrorMessage)
    end

    return true
end

function SaveManager:LoadJSON(Content: string)
    if IsStringEmpty(Content) then
        return false, "No JSON provided"
    end

    local SuccessDecode, Decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            Content
        )

    if not SuccessDecode
        or typeof(Decoded) ~= "table"
        or typeof(Decoded.objects) ~= "table" then
        return false, "Failed to decode config data"
    end

    local Library = SaveManager.Library
    local LoadingOrder = SaveManager.LoadingOrder
    local IgnoreIndexes = SaveManager.Ignore

    if SaveManager.UseLoadingOrder
        and typeof(LoadingOrder) == "table" then

        table.sort(
            Decoded.objects,
            function(a, b)
                local aIndex =
                    table.find(LoadingOrder, a.type)
                    or math.huge

                local bIndex =
                    table.find(LoadingOrder, b.type)
                    or math.huge

                return aIndex < bIndex
            end
        )
    end

    --// Keybind menu
    if Library.KeybindFrame
        and typeof(Decoded.keybindMenu) == "table" then

        local Data = Decoded.keybindMenu

        local IsVisible = Data.visible == true

        local Position =
            SpecialValueParser.UDim2.Decode(
                Data.position
            )

        Library.KeybindFrame.Visible = IsVisible

        Library.KeybindFrame.Position =
            Position
            or Library.KeybindFrame.Position

        local KeybindMenuToggle =
            Library.Options
            and Library.Options.KeybindMenuOpen

        if KeybindMenuToggle then
            KeybindMenuToggle:SetValue(IsVisible)
        end
    end

    --// Elements
    for _, Object in Decoded.objects do
        if not Object.type then
            continue
        end

        if IgnoreIndexes[Object.idx] then
            continue
        end

        local Parser = ElementParser[Object.type]

        if not Parser then
            continue
        end

        task.defer(
            Parser.Load,
            Object.idx,
            Object
        )
    end

    return true
end

function SaveManager:Load(ConfigName: string): (boolean, string?)
    if IsStringEmpty(ConfigName) then
        return false, "No config is selected"
    end

    local ConfigPath = GetConfigPath(ConfigName)

    if ConfigPath == false
        or not isfile(ConfigPath) then
        return false, "Config file does not exist"
    end

    local SuccessRead, Content =
        pcall(readfile, ConfigPath)

    if not SuccessRead then
        return false, "Failed to read config file"
    end

    return SaveManager:LoadJSON(Content)
end

function SaveManager:Delete(ConfigName: string): (boolean, string?)
    if IsStringEmpty(ConfigName) then
        return false, "No config is selected"
    end

    local ConfigPath = GetConfigPath(ConfigName)

    if ConfigPath == false
        or not isfile(ConfigPath) then
        return false, "Config file does not exist"
    end

    local SuccessDelete, ErrorMessage =
        pcall(delfile, ConfigPath)

    if not SuccessDelete then
        return false,
            "Failed to delete config file: "
            .. tostring(ErrorMessage)
    end

    if ConfigName == SaveManager.AutoloadConfig then
        SaveManager:DeleteAutoLoadConfig()
    end

    return true
end

--// Autoload
function SaveManager:GetAutoloadConfig()
    SaveManager:CheckFolderTree()

    local AutoloadPath = GetAutoloadPath()

    if AutoloadPath == false then
        return "none", false, "Invalid path provided"
    end

    if not isfile(AutoloadPath) then
        return "none", false, "Autoload config is not set"
    end

    local SuccessRead, ConfigName =
        pcall(readfile, AutoloadPath)

    if not SuccessRead
        or typeof(ConfigName) ~= "string" then
        return "none", false, ConfigName
    end

    if not DoesConfigExist(ConfigName) then
        return "none", false, "Config file not found"
    end

    SaveManager.AutoloadConfig = ConfigName

    return ConfigName, true
end

function SaveManager:SaveAutoloadConfig(
    ConfigName: string
): (boolean, string?)
    if IsStringEmpty(ConfigName) then
        return false, "No config is selected"
    end

    if not SaveManager:CheckFolderTree() then
        return false, "Failed to create settings folder"
    end

    local AutoloadPath = GetAutoloadPath()

    if AutoloadPath == false then
        return false, "Invalid path provided"
    end

    if not DoesConfigExist(ConfigName) then
        return false, "Config does not exist"
    end

    local SuccessWrite, ErrorMessage =
        pcall(
            writefile,
            AutoloadPath,
            ConfigName
        )

    if not SuccessWrite then
        return false, ErrorMessage
    end

    SaveManager.AutoloadConfig = ConfigName

    return true
end

function SaveManager:LoadAutoloadConfig()
    local ConfigName, Success, ErrorMessage =
        SaveManager:GetAutoloadConfig()

    if not Success or ErrorMessage then
        if ErrorMessage ~= "Autoload config is not set" then
            SaveManager.Library:Notify(
                string.format(
                    "Failed to load autoload config: %s",
                    ErrorMessage
                )
            )
        end

        return
    end

    local SuccessLoad, LoadErrorMessage =
        SaveManager:Load(ConfigName)

    if not SuccessLoad then
        SaveManager.Library:Notify(
            string.format(
                "Failed to load autoload config: %s",
                LoadErrorMessage
            )
        )

        return
    end

    SaveManager.Library:Notify(
        string.format(
            "Successfully loaded autoload config %q",
            ConfigName
        )
    )
end

function SaveManager:DeleteAutoLoadConfig(): (boolean, string?)
    SaveManager:CheckFolderTree()

    local AutoloadPath = GetAutoloadPath()

    if AutoloadPath == false then
        return false, "Invalid path provided"
    end

    if not isfile(AutoloadPath) then
        SaveManager.AutoloadConfig = nil

        return false, "Autoload config is not set"
    end

    local SuccessDelete, ErrorMessage =
        pcall(delfile, AutoloadPath)

    if not SuccessDelete then
        return false, ErrorMessage
    end

    SaveManager.AutoloadConfig = nil

    return true
end

--// Dialog
local function Confirm(
    Index: string,
    Title: string,
    Description: string,
    ActionText: string,
    Action: () -> ()
)
    return SaveManager.Library.Window:AddDialog(Index, {
        Title = Title,
        Description = Description,
        AutoDismiss = false,

        FooterButtons = {
            Cancel = {
                Title = "Cancel",
                Variant = "Ghost",
                Order = 1,

                Callback = function(Dialog)
                    Dialog:Dismiss()
                end
            },

            Action = {
                Title = ActionText,
                Variant = "Destructive",
                Order = 2,

                Callback = function(Dialog)
                    Dialog:Dismiss()
                    Action()
                end
            }
        }
    })
end

--// Configuration UI
function SaveManager:BuildConfigSection(
    Tab: any,
    IconName: string?
)
    assert(
        SaveManager.Library,
        "Library is not set, call SaveManager:SetLibrary(Library) first."
    )

    local ConfigurationBox = Tab:AddGroupbox({
        Side = "Right",
        Name = "Configuration"
    })

    local ConfigNameInput
    local ConfigList
    local AutoloadConfigLabel

    local function Notify(Message)
        SaveManager.Library:Notify(Message)
    end

    local function RefreshList()
        ConfigList:SetValues(
            SaveManager:RefreshConfigList()
        )

        ConfigList:SetValue(nil)
    end

    local function RefreshAutoloadLabel()
        local ConfigName =
            SaveManager:GetAutoloadConfig()

        if ConfigName and ConfigName ~= "none" then
            AutoloadConfigLabel:SetText(
                "Autoload: " .. ConfigName
            )
        else
            AutoloadConfigLabel:SetText(
                "Autoload: None"
            )
        end
    end

    --// Name
    ConfigNameInput =
        ConfigurationBox:AddInput(
            "SaveManager_ConfigName",
            {
                Text = "Name"
            }
        )

    --// Create
    ConfigurationBox:AddButton(
        "Create",
        function()
            local ConfigName =
                ConfigNameInput.Value

            if IsStringEmpty(ConfigName) then
                Notify(
                    "Configuration name cannot be empty."
                )

                return
            end

            if string.lower(ConfigName) == "autoload" then
                Notify("Invalid config name provided.")
                return
            end

            if DoesConfigExist(ConfigName) then
                Notify(
                    string.format(
                        "Config %q already exists. Use Save to overwrite it.",
                        ConfigName
                    )
                )

                return
            end

            local Success, ErrorMessage =
                SaveManager:Save(ConfigName)

            if not Success then
                Notify(
                    string.format(
                        "Failed to create config %q: %s",
                        ConfigName,
                        ErrorMessage
                    )
                )

                return
            end

            Notify(
                string.format(
                    "Successfully created config %q",
                    ConfigName
                )
            )

            RefreshList()
            ConfigList:SetValue(ConfigName)
        end
    )

    --// List
    ConfigList =
        ConfigurationBox:AddDropdown(
            "SaveManager_ConfigList",
            {
                Text = "List",

                Values =
                    SaveManager:RefreshConfigList(),

                AllowNull = true,
                Multi = false,

                FormatDisplayValue = function(Value)
                    if Value == SaveManager.AutoloadConfig then
                        return Value .. " (autoload)"
                    end

                    return Value
                end,

                FormatListValue = function(Value)
                    if Value == SaveManager.AutoloadConfig then
                        return Value .. " (autoload)"
                    end

                    return Value
                end
            }
        )

    --// Load
    ConfigurationBox:AddButton(
        "Load",
        function()
            local ConfigName = ConfigList.Value

            if IsStringEmpty(ConfigName) then
                Notify("Please select a config first.")
                return
            end

            Confirm(
                "SaveManager_LoadConfig",
                "Load config",
                string.format(
                    "Are you sure you want to load %q? Your current settings will be overwritten.",
                    ConfigName
                ),
                "Load",

                function()
                    local Success, ErrorMessage =
                        SaveManager:Load(ConfigName)

                    if not Success then
                        Notify(
                            string.format(
                                "Failed to load config %q: %s",
                                ConfigName,
                                ErrorMessage
                            )
                        )

                        return
                    end

                    Notify(
                        string.format(
                            "Successfully loaded config %q",
                            ConfigName
                        )
                    )
                end
            )
        end
    )

    --// Save
    ConfigurationBox:AddButton(
        "Save",
        function()
            local ConfigName = ConfigList.Value

            if IsStringEmpty(ConfigName) then
                Notify("Please select a config first.")
                return
            end

            Confirm(
                "SaveManager_SaveConfig",
                "Save config",
                string.format(
                    "Are you sure you want to overwrite %q with your current settings?",
                    ConfigName
                ),
                "Save",

                function()
                    local Success, ErrorMessage =
                        SaveManager:Save(ConfigName)

                    if not Success then
                        Notify(
                            string.format(
                                "Failed to save config %q: %s",
                                ConfigName,
                                ErrorMessage
                            )
                        )

                        return
                    end

                    Notify(
                        string.format(
                            "Successfully saved config %q",
                            ConfigName
                        )
                    )
                end
            )
        end
    )

    --// Delete
    ConfigurationBox:AddButton(
        "Delete",
        function()
            local ConfigName = ConfigList.Value

            if IsStringEmpty(ConfigName) then
                Notify("Please select a config first.")
                return
            end

            Confirm(
                "SaveManager_DeleteConfig",
                "Delete config",
                string.format(
                    "Are you sure you want to delete %q? This cannot be undone.",
                    ConfigName
                ),
                "Delete",

                function()
                    local Success, ErrorMessage =
                        SaveManager:Delete(ConfigName)

                    if not Success then
                        Notify(
                            string.format(
                                "Failed to delete config %q: %s",
                                ConfigName,
                                ErrorMessage
                            )
                        )

                        return
                    end

                    Notify(
                        string.format(
                            "Successfully deleted config %q",
                            ConfigName
                        )
                    )

                    RefreshList()
                    RefreshAutoloadLabel()
                end
            )
        end
    )

    --// Set As Autoload
    ConfigurationBox:AddButton(
        "Set As Autoload",
        function()
            local ConfigName = ConfigList.Value

            if IsStringEmpty(ConfigName) then
                Notify("Please select a config first.")
                return
            end

            local Success, ErrorMessage =
                SaveManager:SaveAutoloadConfig(
                    ConfigName
                )

            if not Success then
                Notify(
                    string.format(
                        "Failed to set autoload config %q: %s",
                        ConfigName,
                        ErrorMessage
                    )
                )

                return
            end

            Notify(
                string.format(
                    "Successfully set %q as autoload",
                    ConfigName
                )
            )

            RefreshList()
            RefreshAutoloadLabel()
        end
    )

    --// Remove Autoload
    ConfigurationBox:AddButton(
        "Remove Autoload",
        function()
            Confirm(
                "SaveManager_RemoveAutoload",
                "Remove autoload",
                "Are you sure you want to remove the current autoload config?",
                "Remove",

                function()
                    local Success, ErrorMessage =
                        SaveManager:DeleteAutoLoadConfig()

                    if not Success then
                        Notify(
                            string.format(
                                "Failed to remove autoload config: %s",
                                ErrorMessage
                            )
                        )

                        return
                    end

                    Notify(
                        "Successfully removed autoload config."
                    )

                    RefreshList()
                    RefreshAutoloadLabel()
                end
            )
        end
    )

    --// Status
    AutoloadConfigLabel =
        ConfigurationBox:AddLabel(
            "Autoload: None",
            true
        )

    --// Ignore SaveManager UI
    SaveManager:SetIgnoreIndexes({
        "SaveManager_ConfigName",
        "SaveManager_ConfigList"
    })

    RefreshAutoloadLabel()

    return ConfigurationBox
end

--// Initialize
SaveManager:BuildFolderTree()

return SaveManager
