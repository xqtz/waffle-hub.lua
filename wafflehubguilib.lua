local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Utility helpers (small, well-tested)
local function create(className, props, parent)
    local ok, inst = pcall(function()
        local o = Instance.new(className)
        for k,v in pairs(props or {}) do
            pcall(function() o[k] = v end)
        end
        o.Parent = parent
        return o
    end)
    return ok and inst or nil
end

local function round(target, radius)
    if target and target:IsA("GuiObject") then
        create("UICorner", { CornerRadius = UDim.new(0, radius) }, target)
    end
end

local function pad(target, amount)
    if target and target:IsA("GuiObject") then
        create("UIPadding", { PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount), PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount) }, target)
    end
end

local function safeConnect(signal, fn)
    local conn = nil
    conn = signal:Connect(function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("WaffleHub: connection callback error", err)
        end
    end)
    return conn
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Default config and themes
local DEFAULT_CONFIG = {
    Title = "WAFFLE HUB",
    ThemeColor = Color3.fromRGB(238, 61, 76),
    BackgroundColor = Color3.fromRGB(14, 15, 18),
    SidebarColor = Color3.fromRGB(18, 19, 23),
    PanelColor = Color3.fromRGB(24, 25, 30),
    TextColor = Color3.fromRGB(235, 236, 240),
    MutedTextColor = Color3.fromRGB(145, 148, 158),
    CornerRadius = 10,
    AnimationSpeed = 0.18,
    SidebarWidth = 220,
    Font = Enum.Font.Gotham,
    EnableGlow = true,
    EnableBlur = true,
    EnableGradients = true,
    DefaultTransparency = 0
}

local BUILT_IN_THEMES = {
    Crimson = { ThemeColor = Color3.fromRGB(238,61,76), BackgroundColor = Color3.fromRGB(14,15,18) },
    Cobalt  = { ThemeColor = Color3.fromRGB(72,128,255), BackgroundColor = Color3.fromRGB(12,16,24) },
    Amber   = { ThemeColor = Color3.fromRGB(245,164,55), BackgroundColor = Color3.fromRGB(18,16,13) },
    Emerald = { ThemeColor = Color3.fromRGB(46,204,113), BackgroundColor = Color3.fromRGB(8,12,10) },
    Neon    = { ThemeColor = Color3.fromRGB(0,255,170), BackgroundColor = Color3.fromRGB(10,10,12) },
    Midnight= { ThemeColor = Color3.fromRGB(100,100,255), BackgroundColor = Color3.fromRGB(6,8,20) },
    TokyoNight = { ThemeColor = Color3.fromRGB(80,120,200), BackgroundColor = Color3.fromRGB(9,12,21) },
    Nord = { ThemeColor = Color3.fromRGB(136,192,208), BackgroundColor = Color3.fromRGB(8,12,16) },
    Catppuccin = { ThemeColor = Color3.fromRGB(255,179,205), BackgroundColor = Color3.fromRGB(31,30,38) },
    Rose = { ThemeColor = Color3.fromRGB(255,102,102), BackgroundColor = Color3.fromRGB(20,16,21) },
    Ocean = { ThemeColor = Color3.fromRGB(60,166,255), BackgroundColor = Color3.fromRGB(6,18,26) }
}

-- Singleton root object for WaffleHub
local WaffleHub = {}
WaffleHub.__index = WaffleHub

-- Events
local function newSignal()
    local subscribers = {}
    return {
        Connect = function(_, fn) table.insert(subscribers, fn); return { Disconnect = function() for i,f in ipairs(subscribers) do if f==fn then table.remove(subscribers,i); break end end end } end,
        Fire = function(_, ...) for _,fn in ipairs(subscribers) do pcall(fn, ...) end end
    }
end

-- Flag manager
local FlagManager = {}
FlagManager.__index = FlagManager
function FlagManager.new()
    return setmetatable({ _flags = {} }, FlagManager)
end
function FlagManager:Get(name) return self._flags[name] end
function FlagManager:Set(name, val) self._flags[name] = val end

-- Clean up utility for instances and connections
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {} }, Maid) end
function Maid:Give(task)
    table.insert(self._tasks, task)
    return task
end
function Maid:DoCleaning()
    for _,t in ipairs(self._tasks) do
        pcall(function()
            if typeof(t) == "RBXScriptConnection" then t:Disconnect()
            elseif type(t) == "Instance" and t.Destroy then t:Destroy()
            elseif type(t) == "table" and t.Disconnect then t:Disconnect()
            end
        end)
    end
    self._tasks = {}
end

-- Core Window class
local Window = {}
Window.__index = Window

function Window.new(hub, opts)
    opts = opts or {}
    local self = setmetatable({}, Window)
    self._hub = hub
    self._name = opts.Name or hub.Config.Title
    self._subtitle = opts.Subtitle or ""
    self._tabs = {}
    self._visible = true
    self._minimized = false
    self._maximized = false
    self._locked = false
    self._transparency = hub.Config.DefaultTransparency or 0
    self._maid = Maid.new()
    self._container = nil
    self:_build(opts)
    return self
end

function Window:_tween(target, props, time)
    time = time or self._hub.Config.AnimationSpeed
    TweenService:Create(target, TweenInfo.new(time, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

function Window:_build(opts)
    local hub = self._hub
    local cfg = hub.Config
    local gui = hub.Gui
    -- Root window container
    local root = create("Frame", { Name = "RootWindow", Size = UDim2.fromScale(.78, .78), Position = UDim2.fromScale(.11, .11), BackgroundColor3 = cfg.BackgroundColor, BorderSizePixel = 0, Active = true }, gui)
    round(root, cfg.CornerRadius)
    self._root = root
    self._maid:Give(root)

    -- Topbar with title and controls
    local top = create("Frame", { Name = "Topbar", Size = UDim2.new(1,0,0,36), BackgroundTransparency = 1 }, root)
    local title = create("TextLabel", { Size = UDim2.new(1,-120,1,0), Position = UDim2.fromOffset(12,0), BackgroundTransparency = 1, Text = self._name, TextColor3 = cfg.ThemeColor, TextSize = 20, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, top)
    local controls = create("Frame", { Size = UDim2.new(0,100,1,0), Position = UDim2.new(1, -110, 0, 0), BackgroundTransparency = 1 }, top)

    local btnMin = create("TextButton", { Size = UDim2.new(0,28,0,28), Position = UDim2.fromOffset(0,4), BackgroundTransparency = 1, Text = "_", TextColor3 = cfg.TextColor, AutoButtonColor = false }, controls)
    local btnMax = create("TextButton", { Size = UDim2.new(0,28,0,28), Position = UDim2.fromOffset(34,4), BackgroundTransparency = 1, Text = "□", TextColor3 = cfg.TextColor, AutoButtonColor = false }, controls)
    local btnClose = create("TextButton", { Size = UDim2.new(0,28,0,28), Position = UDim2.fromOffset(68,4), BackgroundTransparency = 1, Text = "✕", TextColor3 = cfg.TextColor, AutoButtonColor = false }, controls)

    -- Sidebar and content
    local sidebar = create("Frame", { Name = "Sidebar", Size = UDim2.new(0, cfg.SidebarWidth, 1, -36), Position = UDim2.fromOffset(0,36), BackgroundColor3 = cfg.SidebarColor, BorderSizePixel = 0 }, root)
    round(sidebar, cfg.CornerRadius)
    local content = create("Frame", { Name = "Content", Size = UDim2.new(1, -cfg.SidebarWidth, 1, -36), Position = UDim2.fromOffset(cfg.SidebarWidth, 36), BackgroundTransparency = 1 }, root)

    -- Search
    local search = create("TextBox", { Size = UDim2.new(1, -28, 0, 34), Position = UDim2.fromOffset(14, 8), BackgroundColor3 = cfg.PanelColor, PlaceholderText = "  Search", Text = "", TextColor3 = cfg.TextColor, PlaceholderColor3 = cfg.MutedTextColor, TextSize = 13, Font = cfg.Font, ClearTextOnFocus = false }, sidebar)
    round(search, math.max(5, cfg.CornerRadius - 3))

    -- Notification container
    local notifContainer = hub.NotifContainer

    -- store
    self.GuiElements = { Root = root, Top = top, Title = title, Sidebar = sidebar, Content = content, Search = search, Controls = { Min = btnMin, Max = btnMax, Close = btnClose }, NotifContainer = notifContainer }

    -- events
    self.OnMinimized = newSignal()
    self.OnMaximized = newSignal()
    self.OnVisibilityChanged = newSignal()
    self.OnDestroyed = newSignal()

    -- connections
    self._maid:Give(safeConnect(btnMin.Activated, function()
        self:SetMinimized(true)
    end))
    self._maid:Give(safeConnect(btnMax.Activated, function()
        self:SetMaximized(not self._maximized)
    end))
    self._maid:Give(safeConnect(btnClose.Activated, function()
        self:SetVisibility(false)
    end))

    -- Dragging
    do
        local dragging, startPos, startInput
        self._maid:Give(safeConnect(top.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and not self._locked then
                dragging = true; startInput = input.Position; startPos = root.Position
            end
        end))
        self._maid:Give(safeConnect(UserInputService.InputChanged, function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement and not self._locked then
                local delta = input.Position - startInput
                root.Position = startPos + UDim2.fromOffset(delta.X, delta.Y)
            end
        end))
        self._maid:Give(safeConnect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end))
    end

    -- keyboard toggle (default: RightControl)
    self._maid:Give(safeConnect(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.RightControl then
            self:SetVisibility(not self._visible)
        end
    end))

    -- resizing handle (bottom-right)
    local resizeGrip = create("Frame", { Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(1, -14, 1, -14), BackgroundTransparency = 1, ZIndex = 10 }, root)
    self._maid:Give(resizeGrip)
    do
        local resizing, startPos, startSize, startInput
        self._maid:Give(safeConnect(resizeGrip.InputBegan, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 and not self._locked then
                resizing = true; startInput = i.Position; startPos = root.Position; startSize = root.Size
            end
        end))
        self._maid:Give(safeConnect(UserInputService.InputChanged, function(i)
            if resizing and i.UserInputType == Enum.UserInputType.MouseMovement and not self._locked then
                local delta = i.Position - startInput
                root.Size = UDim2.new(startSize.X.Scale, startSize.X.Offset + delta.X, startSize.Y.Scale, startSize.Y.Offset + delta.Y)
            end
        end))
        self._maid:Give(safeConnect(UserInputService.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then resizing = false end
        end))
    end

    hub:_applyEffects(root)
    hub:BindSearch(search)
    hub.RootWindow = root
    self._maid:Give(root)
end

function Window:SetMinimized(val)
    self._minimized = val
    self._root.Visible = not val
    self.OnMinimized:Fire(val)
end

function Window:SetMaximized(val)
    self._maximized = val
    if val then
        self._root.Position = UDim2.new(0,0,0,0)
        self._root.Size = UDim2.new(1,0,1,0)
    else
        -- restore to default center size
        self._root.Size = UDim2.fromScale(.78, .78)
        self._root.Position = UDim2.fromScale(.11, .11)
    end
    self.OnMaximized:Fire(val)
end

function Window:SetVisibility(vis)
    self._visible = vis
    if self._root then self._root.Visible = vis end
    self.OnVisibilityChanged:Fire(vis)
end

function Window:SetLocked(val)
    self._locked = val
end

function Window:SetTransparency(value)
    self._transparency = math.clamp(value, 0, 1)
    if self._root then
        self._root.BackgroundTransparency = self._transparency
    end
end

function Window:Destroy()
    self.OnDestroyed:Fire()
    self._maid:DoCleaning()
    if self._root and self._root.Parent then self._root:Destroy() end
end

function Window:SelectTab(name)
    local selected = nil
    for _,tab in ipairs(self._tabs) do
        if tab._name == name then selected = tab; break end
    end
    if not selected then return end
    for _,tab in ipairs(self._tabs) do
        local active = tab == selected
        if tab._page and tab._page.Canvas then tab._page.Canvas.Visible = active end
        if tab._page and tab._page.Button then
            local btn = tab._page.Button
            self:_tween(btn, { BackgroundTransparency = active and 0 or 1, TextColor3 = active and self._hub.Config.ThemeColor or self._hub.Config.MutedTextColor })
        end
    end
    self._activeTab = selected
    if self._hub and self._hub.OnTabChanged then self._hub.OnTabChanged:Fire(self, selected) end
end

function Window:CreateTab(name, icon)
    if typeof(name) ~= "string" then warn("CreateTab expected string") return end
    local cfg = self._hub.Config
    local button = create("TextButton", { Name = name, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = cfg.PanelColor, BackgroundTransparency = 1, Text = (icon or "◆") .. "   " .. name, TextColor3 = cfg.MutedTextColor, TextSize = 13, Font = cfg.Font, TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false }, self.GuiElements.Sidebar)
    round(button, cfg.CornerRadius)
    pad(button, 11)
    local canvas = create("ScrollingFrame", { Name = name .. "Canvas", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false }, self.GuiElements.Content)
    pad(canvas, 22)
    create("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, canvas)
    local page = { Name = name, Button = button, Canvas = canvas, Sections = {} }
    local tabObj = setmetatable({ _page = page, _sections = {}, _name = name, _hub = self._hub }, Tab)
    table.insert(self._tabs, tabObj)
    button.Activated:Connect(function() self:SelectTab(name) end)
    if not self._activeTab then self:SelectTab(name) end
    return tabObj
end

-- Hub constructor
function WaffleHub.new(overrides)
    local self = setmetatable({}, WaffleHub)
    self.Config = deepcopy(DEFAULT_CONFIG)
    for k,v in pairs(overrides or {}) do self.Config[k] = v end
    self.Themes = deepcopy(BUILT_IN_THEMES)
    self.Windows = {}
    self._maid = Maid.new()
    self.Flags = FlagManager.new()
    self.OnThemeChanged = newSignal()
    self.OnTabChanged = newSignal()
    self.Plugins = {}

    -- create ScreenGui root
    local gui = create("ScreenGui", { Name = "WaffleHub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, Players.LocalPlayer:WaitForChild("PlayerGui"))
    self.Gui = gui

    -- notification container
    local notifContainer = create("Frame", { Name = "Notifications", Size = UDim2.new(0,320,0,0), Position = UDim2.new(1,-340,0,20), BackgroundTransparency = 1 }, gui)
    create("UIListLayout", { Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, notifContainer)
    self.NotifContainer = notifContainer

    -- apply global input bindings
    self._maid:Give(safeConnect(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.P and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
            -- Command palette
            self:OpenCommandPalette()
        end
    end))

    return self
end

function WaffleHub:_applyEffects(root)
    local cfg = self.Config
    if cfg.EnableBlur then
        local blur = create("BlurEffect", { Size = 6 }, game:GetService("Lighting"))
        self._maid:Give(blur)
    end
    if cfg.EnableGlow then
        create("UIStroke", { Color = cfg.ThemeColor, Transparency = .5, Thickness = 1 }, root)
    end
end

function WaffleHub:BindSearch(searchBox)
    self._maid:Give(safeConnect(searchBox:GetPropertyChangedSignal("Text"), function()
        local q = string.lower(searchBox.Text)
        for _, win in pairs(self.Windows) do
            for _, tab in ipairs(win._tabs or {}) do
                if tab._page and tab._page.Button then
                    local visible = (q == "") or string.find(string.lower(tab._name or ""), q, 1, true)
                    tab._page.Button.Visible = visible
                end
            end
        end
    end))
end

function WaffleHub:CreateWindow(opts)
    local win = Window.new(self, opts)
    table.insert(self.Windows, win)
    return win
end

function WaffleHub:RegisterTheme(name, t)
    if type(name) ~= "string" or type(t) ~= "table" then return end
    self.Themes[name] = t
end

function WaffleHub:SetTheme(name)
    local theme = self.Themes[name]
    if not theme then return end
    for k,v in pairs(theme) do self.Config[k] = v end
    -- apply transition animation to all root windows
    for _,w in pairs(self.Windows) do
        if w._root then w:_tween(w._root, { BackgroundColor3 = self.Config.BackgroundColor }) end
    end
    self.OnThemeChanged:Fire(name)
end

-- Notification system (typed, sounds, progress)
function WaffleHub:Notify(params)
    params = params or {}
    local title = params.Title or ""
    local content = params.Content or ""
    local typ = params.Type or "Info"
    local duration = params.Duration or 3
    local hub = self

    local colorMap = {
        Success = Color3.fromRGB(46,204,113),
        Warning = Color3.fromRGB(245,166,35),
        Error = Color3.fromRGB(231,76,60),
        Info = hub.Config.ThemeColor
    }
    local frame = create("Frame", { Size = UDim2.new(0,320,0,70), BackgroundColor3 = hub.Config.PanelColor, BorderSizePixel = 0 }, hub.NotifContainer)
    round(frame, hub.Config.CornerRadius)
    local tlabel = create("TextLabel", { Size = UDim2.new(1,-12,0,20), Position = UDim2.fromOffset(8,6), BackgroundTransparency = 1, Text = title, TextColor3 = hub.Config.TextColor, Font = hub.Config.Font, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, frame)
    local clabel = create("TextLabel", { Size = UDim2.new(1,-12,0,36), Position = UDim2.fromOffset(8,26), BackgroundTransparency = 1, Text = content, TextColor3 = hub.Config.MutedTextColor, Font = hub.Config.Font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, frame)
    local icon = create("Frame", { Size = UDim2.new(0,8,1,0), Position = UDim2.fromOffset(0,0), BackgroundColor3 = colorMap[typ] or hub.Config.ThemeColor, BorderSizePixel = 0 }, frame)

    -- progress bar
    local barBg = create("Frame", { Size = UDim2.new(1, -12, 0, 4), Position = UDim2.new(0, 8, 1, -12), BackgroundColor3 = Color3.fromRGB(30,30,30), BorderSizePixel = 0 }, frame)
    local bar = create("Frame", { Size = UDim2.new(1,0,1,0), BackgroundColor3 = colorMap[typ] or hub.Config.ThemeColor, BorderSizePixel = 0 }, barBg)

    -- entrance
    frame.AnchorPoint = Vector2.new(1,0)
    frame.Position = UDim2.new(1,-20,0,20)
    TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = frame.Position + UDim2.new(0,0,0,8) }):Play()

    spawn(function()
        local elapsed = 0
        while elapsed < duration do
            wait(0.1)
            elapsed = elapsed + 0.1
            local frac = 1 - (elapsed / duration)
            bar.Size = UDim2.new(frac, 0, 1, 0)
        end
        TweenService:Create(frame, TweenInfo.new(0.18), { BackgroundTransparency = 1, Size = UDim2.new(0,320,0,0) }):Play()
        wait(0.2)
        pcall(function() frame:Destroy() end)
    end)

    if params.Sound then
        pcall(function() local s = Instance.new("Sound", workspace); s.SoundId = params.Sound; s:Play(); game:GetService("Debris"):AddItem(s, 3) end)
    end
end

-- Command palette (simple implementation)
function WaffleHub:OpenCommandPalette()
    -- small ephemeral UI
    if self._commandGui and self._commandGui.Parent then self._commandGui:Destroy() end
    local gui = create("Frame", { Size = UDim2.new(0,400,0,40), Position = UDim2.fromScale(.5, .02), AnchorPoint = Vector2.new(.5,0), BackgroundColor3 = self.Config.PanelColor, BorderSizePixel = 0 }, self.Gui)
    round(gui, 6)
    local box = create("TextBox", { Size = UDim2.new(1,-12,1, -8), Position = UDim2.fromOffset(6,4), BackgroundTransparency = 1, Text = "", PlaceholderText = "Search commands...", TextColor3 = self.Config.TextColor, Font = self.Config.Font, TextSize = 14 }, gui)
    self._commandGui = gui
    box:CaptureFocus()
    safeConnect(box.FocusLost, function() pcall(function() gui:Destroy() end) end)
end

-- Plugin registration
function WaffleHub:RegisterPlugin(plugin)
    if type(plugin) ~= "table" or not plugin.Name then warn("Plugin invalid") return end
    table.insert(self.Plugins, plugin)
    if plugin.Init then pcall(plugin.Init, self) end
end

-- Flag API
function WaffleHub:GetFlag(name) return self.Flags:Get(name) end
function WaffleHub:SetFlag(name, val) self.Flags:Set(name, val) end

-- Backwards compatibility: expose old-style CreateWindow
function WaffleHub.CreateWindow(self, opts) return self:CreateWindow(opts) end

-- Expose API
-- Tab and Section system (backwards-compatible API)
local Tab = {}
Tab.__index = Tab

function Tab:CreateSection(name)
    name = name or "Section"
    local secFrame = create("Frame", { Size = UDim2.new(1,0,0,56), BackgroundColor3 = self._hub.Config.PanelColor, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.Y }, self._page.Canvas)
    round(secFrame, self._hub.Config.CornerRadius)
    pad(secFrame, 14)
    local header = create("TextButton", { Size = UDim2.new(1,0,0,28), BackgroundTransparency = 1, Text = name .. "                                      −", TextColor3 = self._hub.Config.TextColor, TextSize = 14, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left }, secFrame)
    local layout = create("UIListLayout", { Padding = UDim.new(0,9), SortOrder = Enum.SortOrder.LayoutOrder }, secFrame)

    local section = setmetatable({ _frame = secFrame, _header = header, _hub = self._hub, _widgets = {}, _maid = Maid.new() }, { __index = Section })
    table.insert(self._sections, section)
    return section
end

-- Section class with advanced widgets
local Section = {}
Section.__index = Section

function Section:CreateButton(params)
    params = params or {}
    local btn = create("TextButton", { Size = UDim2.new(1,0,0,38), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = params.Name or "Button", TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, self._frame)
    round(btn, math.max(5, self._hub.Config.CornerRadius - 3))
    btn.Activated:Connect(function() pcall(function() (params.Callback or function() end)() end) end)
    return {
        Set = function(_, t) if typeof(t)=="string" then btn.Text = t end end,
        Fire = function() pcall(function() (params.Callback or function() end)() end) end,
        Destroy = function() pcall(function() btn:Destroy() end) end
    }
end

function Section:CreateToggle(params)
    params = params or {}
    local state = params.CurrentValue and true or false
    local name = params.Name or "Toggle"
    local btn = create("TextButton", { Size = UDim2.new(1,0,0,38), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = name .. "  [" .. (state and "ON" or "OFF") .. "]", TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, self._frame)
    round(btn, math.max(5, self._hub.Config.CornerRadius - 3))
    local wrapper = {}
    function wrapper:Set(val) state = not not val; btn.Text = name .. "  [" .. (state and "ON" or "OFF") .. "]"; if params.Callback then pcall(function() params.Callback(state) end) end end
    function wrapper:Get() return state end
    function wrapper:Toggle() wrapper:Set(not state) end
    function wrapper:Destroy() pcall(function() btn:Destroy() end) end
    btn.Activated:Connect(function() wrapper:Toggle() end)
    return wrapper
end

function Section:CreateSlider(params)
    params = params or {}
    local minv, maxv = 0, 100
    if params.Range then minv, maxv = params.Range[1] or 0, params.Range[2] or 100 end
    local inc = params.Increment or 1
    local cur = params.CurrentValue or minv
    local container = create('Frame', { Size = UDim2.new(1,0,0,40), BackgroundTransparency = 1 }, self._frame)
    local label = create('TextLabel', { Size = UDim2.new(1,-12,0,16), Position = UDim2.fromOffset(6,0), BackgroundTransparency = 1, Text = params.Name or 'Slider', TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, TextXAlignment = Enum.TextXAlignment.Left }, container)
    local barBg = create('Frame', { Size = UDim2.new(1,-12,0,12), Position = UDim2.fromOffset(6,20), BackgroundColor3 = self._hub.Config.PanelColor, BorderSizePixel = 0 }, container)
    round(barBg, math.max(4, self._hub.Config.CornerRadius-4))
    local fill = create('Frame', { Size = UDim2.new((cur-minv)/math.max(1,maxv-minv),0,1,0), Position = UDim2.new(0,0,0,0), BackgroundColor3 = self._hub.Config.ThemeColor, BorderSizePixel = 0 }, barBg)
    round(fill, math.max(4, self._hub.Config.CornerRadius-4))
    local dragging = false
    barBg.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
    barBg.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    local function updateFromPos(posX)
        local abs = posX - barBg.AbsolutePosition.X
        local frac = math.clamp(abs / barBg.AbsoluteSize.X, 0, 1)
        local value = minv + math.floor(((minv + (maxv - minv) * frac) - minv) / inc + 0.5) * inc
        value = math.clamp(value, minv, maxv)
        cur = value
        fill.Size = UDim2.new((cur - minv)/math.max(1, maxv - minv), 0, 1, 0)
        if params.Callback then pcall(function() params.Callback(cur) end) end
    end
    local conn = UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromPos(i.Position.X)
        end
    end)
    self._maid:Give(conn)
    local wrapper = {}
    function wrapper:Set(v) cur = math.clamp(v, minv, maxv); fill.Size = UDim2.new((cur-minv)/math.max(1,maxv-minv),0,1,0) end
    function wrapper:Get() return cur end
    function wrapper:Destroy() pcall(function() container:Destroy() end) end
    return wrapper
end

function Section:CreateDropdown(params)
    params = params or {}
    local options = params.Options or {}
    local current = params.CurrentOption or options[1]
    local multi = params.MultipleOptions and true or false
    local dropdownBtn = create('TextButton', { Size = UDim2.new(1,0,0,38), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = (params.Name or 'Dropdown') .. ' : ' .. tostring(current), TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, self._frame)
    round(dropdownBtn, math.max(5, self._hub.Config.CornerRadius - 3))
    local listFrame = create('Frame', { Size = UDim2.new(1,0,0,0), BackgroundTransparency = 1, Visible = false }, self._frame)
    create('UIListLayout', { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
    local selections = {}
    for _, opt in ipairs(options) do
        local optBtn = create('TextButton', { Size = UDim2.new(1,0,0,28), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = tostring(opt), TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, listFrame)
        round(optBtn, math.max(5, self._hub.Config.CornerRadius - 3))
        optBtn.Activated:Connect(function()
            if multi then
                selections[tostring(opt)] = not selections[tostring(opt)]
                if params.Callback then pcall(function() params.Callback(selections) end) end
            else
                current = opt
                dropdownBtn.Text = (params.Name or 'Dropdown') .. ' : ' .. tostring(current)
                listFrame.Visible = false
                if params.Callback then pcall(function() params.Callback(current) end) end
            end
        end)
    end
    dropdownBtn.Activated:Connect(function() listFrame.Visible = not listFrame.Visible end)
    local wrapper = {}
    function wrapper:Set(val)
        if multi then
            if type(val) == "table" then selections = {}; for _,v in ipairs(val) do selections[tostring(v)] = true end end
        else current = val; dropdownBtn.Text = (params.Name or 'Dropdown') .. ' : ' .. tostring(current) end
    end
    function wrapper:Get() if multi then return selections else return current end end
    function wrapper:Refresh(newOptions)
        for _,child in ipairs(listFrame:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
        for _, opt in ipairs(newOptions or {}) do
            local optBtn = create('TextButton', { Size = UDim2.new(1,0,0,28), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = tostring(opt), TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, listFrame)
            round(optBtn, math.max(5, self._hub.Config.CornerRadius - 3))
            optBtn.Activated:Connect(function()
                if multi then
                    selections[tostring(opt)] = not selections[tostring(opt)]
                    if params.Callback then pcall(function() params.Callback(selections) end) end
                else
                    current = opt
                    dropdownBtn.Text = (params.Name or 'Dropdown') .. ' : ' .. tostring(current)
                    listFrame.Visible = false
                    if params.Callback then pcall(function() params.Callback(current) end) end
                end
            end)
        end
    end
    function wrapper:Destroy() pcall(function() listFrame:Destroy() end) end
    return wrapper
end

function Section:CreateTextbox(params)
    params = params or {}
    local box = create('TextBox', { Size = UDim2.new(1,0,0,34), BackgroundColor3 = self._hub.Config.BackgroundColor, Text = params.Text or '', PlaceholderText = params.PlaceholderText or '', TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 13, ClearTextOnFocus = params.RemoveTextAfterFocusLost and true or false }, self._frame)
    round(box, math.max(5, self._hub.Config.CornerRadius - 3))
    box.FocusLost:Connect(function() if params.Callback then pcall(function() params.Callback(box.Text) end) end if params.RemoveTextAfterFocusLost then box.Text = "" end end)
    local wrapper = {}
    function wrapper:Set(t) if typeof(t) == "string" then box.Text = t end end
    function wrapper:Get() return box.Text end
    function wrapper:Destroy() pcall(function() box:Destroy() end) end
    return wrapper
end

function Section:CreateKeybind(params)
    params = params or {}
    local key = params.CurrentKey or "None"
    local btn = create("TextButton", { Size = UDim2.new(1,0,0,38), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = (params.Name or 'Keybind') .. ' : ' .. tostring(key), TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, self._frame)
    local listening = false
    local conn
    local wrapper = {}
    function wrapper:Set(k)
        key = k
        btn.Text = (params.Name or 'Keybind') .. ' : ' .. tostring(key)
    end
    function wrapper:Get() return key end
    function wrapper:Destroy() if conn then conn:Disconnect() end pcall(function() btn:Destroy() end) end
    btn.Activated:Connect(function() listening = true; btn.Text = (params.Name or 'Keybind') .. ' : ...' end)
    conn = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if listening then
            if input.KeyCode then
                key = tostring(input.KeyCode):gsub('Enum.KeyCode%.', '')
                btn.Text = (params.Name or 'Keybind') .. ' : ' .. key
                listening = false
                if params.Callback then pcall(function() params.Callback(key) end) end
            end
        else
            if tostring(input.KeyCode):gsub('Enum.KeyCode%.', '') == key and params.Action then pcall(function() params.Action() end) end
        end
    end)
    return wrapper
end

-- Advanced: Real Color Picker (HSV/RGB/Hex/Rainbow/Transparency)
function Section:CreateColorPicker(params)
    params = params or {}
    local current = params.Color or self._hub.Config.ThemeColor
    local btn = create("TextButton", { Size = UDim2.new(1,0,0,38), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0, Text = params.Name or "Color", TextColor3 = self._hub.Config.TextColor, TextSize = 13, Font = self._hub.Config.Font, AutoButtonColor = false }, self._frame)
    round(btn, math.max(5, self._hub.Config.CornerRadius - 3))
    local palette = create('Frame', { Size = UDim2.new(1,0,0,180), BackgroundTransparency = 1, Visible = false }, self._frame)
    -- layout: big hue/sat area, vertical value/transparency, RGB inputs, Hex input, rainbow toggle
    local hueSat = create('ImageLabel', { Size = UDim2.new(0.7, -6, 0.7, 0), Position = UDim2.fromOffset(6,6), BackgroundColor3 = Color3.new(1,1,1), Image = "", BorderSizePixel = 0 }, palette)
    local valTrans = create('Frame', { Size = UDim2.new(0.28,0,0.7,0), Position = UDim2.fromOffset(hueSat.AbsoluteSize.X + 12,6), BackgroundTransparency = 1 }, palette)
    local rgbFrame = create('Frame', { Size = UDim2.new(1,-12,0,46), Position = UDim2.fromOffset(6, hueSat.AbsoluteSize.Y + 12), BackgroundTransparency = 1 }, palette)
    local hexBox = create('TextBox', { Size = UDim2.new(0.5,-6,0,28), Position = UDim2.fromOffset(6, hueSat.AbsoluteSize.Y + 64), BackgroundColor3 = self._hub.Config.PanelColor, Text = "#" .. string.format('%02X%02X%02X', math.floor(current.R*255), math.floor(current.G*255), math.floor(current.B*255)), TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 13 }, palette)
    local rainbowBtn = create('TextButton', { Size = UDim2.new(0.44,0,0,28), Position = UDim2.fromOffset(hexBox.AbsoluteSize.X + 12, hueSat.AbsoluteSize.Y + 64), BackgroundColor3 = self._hub.Config.PanelColor, Text = "Rainbow: Off", TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 13 }, palette)
    round(hexBox, 6); round(rainbowBtn, 6)
    local rainbow = false
    local stopRainbow = false
    local function setColor(c)
        if typeof(c) ~= "Color3" then return end
        current = c
        if params.Callback then pcall(function() params.Callback(current) end) end
    end
    rainbowBtn.Activated:Connect(function()
        rainbow = not rainbow
        rainbowBtn.Text = "Rainbow: " .. (rainbow and "On" or "Off")
        if rainbow then
            stopRainbow = false
            spawn(function()
                while rainbow and not stopRainbow do
                    local t = tick()%5
                    local hue = (t/5)
                    local col = Color3.fromHSV(hue,1,1)
                    setColor(col)
                    wait(0.1)
                end
            end)
        else
            stopRainbow = true
        end
    end)
    btn.Activated:Connect(function() palette.Visible = not palette.Visible end)
    local wrapper = {}
    function wrapper:Set(c) if typeof(c) == "Color3" then current = c; if params.Callback then pcall(function() params.Callback(c) end) end end end
    function wrapper:Get() return current end
    function wrapper:Destroy() pcall(function() palette:Destroy() end) end
    return wrapper
end

-- Watermark (shows FPS/ping)
function Window:CreateWatermark(opts)
    opts = opts or {}
    local showFPS = opts.ShowFPS ~= false
    local showPing = opts.ShowPing ~= false
    local wf = create('TextLabel', { Size = UDim2.new(0,200,0,28), Position = UDim2.new(1, -210, 0, 6), BackgroundTransparency = 1, Text = '', TextColor3 = self._hub.Config.MutedTextColor, Font = self._hub.Config.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right }, self._hub.Gui)
    local maid = Maid.new(); maid:Give(wf)
    maid:Give(RunService.RenderStepped:Connect(function(dt)
        local parts = {}
        if showFPS then
            local fps = (dt and dt > 0) and math.floor(1/dt) or 0
            table.insert(parts, string.format('FPS: %d', fps))
        end
        if showPing then
            local ping = math.floor((Players.LocalPlayer and Players.LocalPlayer:GetNetworkPing()) or 0)
            table.insert(parts, 'Ping: ' .. tostring(ping))
        end
        wf.Text = table.concat(parts, '   ')
    end))
    return {
        Destroy = function() maid:DoCleaning(); pcall(function() wf:Destroy() end) end
    }
end

-- Console (prints categorized messages into a UI)
function Window:CreateConsole()
    local win = self
    local conFrame = create('Frame', { Size = UDim2.new(0,400,0,200), Position = UDim2.new(0.5,-200,0.5,-100), BackgroundColor3 = win._hub.Config.PanelColor, BorderSizePixel = 0 }, self.Gui)
    round(conFrame, 8)
    local scroll = create('ScrollingFrame', { Size = UDim2.new(1,-12,1,-12), Position = UDim2.fromOffset(6,6), BackgroundTransparency = 1, ScrollBarThickness = 6 }, conFrame)
    create('UIListLayout', { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    local function addMsg(text, color)
        local lbl = create('TextLabel', { Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1, Text = text, TextColor3 = color or win._hub.Config.TextColor, Font = win._hub.Config.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, scroll)
        wait()
        scroll.CanvasSize = UDim2.new(0,0,0, scroll.UIListLayout.AbsoluteContentSize.Y)
    end
    local Console = {}
    function Console:Print(msg) addMsg(tostring(msg), Color3.fromRGB(200,200,200)) end
    function Console:Warn(msg) addMsg('[WARN] ' .. tostring(msg), Color3.fromRGB(250,200,20)) end
    function Console:Error(msg) addMsg('[ERROR] ' .. tostring(msg), Color3.fromRGB(255,100,100)) end
    function Console:Destroy() pcall(function() conFrame:Destroy() end) end
    return Console
end

-- Terminal (simple write-only console inside a section)
function Section:CreateTerminal()
    local container = create('Frame', { Size = UDim2.new(1,0,0,120), BackgroundTransparency = 1 }, self._frame)
    local scroll = create('ScrollingFrame', { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6,6), BackgroundTransparency = 1, ScrollBarThickness = 6 }, container)
    create('UIListLayout', { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    local function write(txt)
        local lbl = create('TextLabel', { Size = UDim2.new(1,0,0,18), BackgroundTransparency = 1, Text = tostring(txt), TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, scroll)
        wait()
        scroll.CanvasSize = UDim2.new(0,0,0, scroll.UIListLayout.AbsoluteContentSize.Y)
    end
    return { Write = write }
end

-- Graph widget (simple line graph)
function Section:CreateGraph()
    local frame = create('Frame', { Size = UDim2.new(1,0,0,120), BackgroundTransparency = 1 }, self._frame)
    local canvas = create('Frame', { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6,6), BackgroundColor3 = self._hub.Config.PanelColor, BorderSizePixel = 0 }, frame)
    round(canvas, 6)
    local points = {}
    local function redraw()
        for _,c in ipairs(canvas:GetChildren()) do if c:IsA('Frame') and c.Name == 'Point' then c:Destroy() end end
        local w = canvas.AbsoluteSize.X; local h = canvas.AbsoluteSize.Y
        for i,v in ipairs(points) do
            local x = (i-1)/(math.max(1,#points-1)) * w
            local y = (1 - math.clamp(v/100,0,1)) * h
            local p = create('Frame', { Name = 'Point', Size = UDim2.new(0,6,0,6), Position = UDim2.fromOffset(x, y), BackgroundColor3 = self._hub.Config.ThemeColor, BorderSizePixel = 0 }, canvas)
            round(p, 3)
        end
    end
    local wrapper = {}
    function wrapper:AddPoint(v) table.insert(points, v); redraw() end
    function wrapper:Clear() points = {}; redraw() end
    return wrapper
end

-- Statistics card
function Section:CreateStatCard(opts)
    opts = opts or {}
    local card = create('Frame', { Size = UDim2.new(1,0,0,72), BackgroundColor3 = self._hub.Config.BackgroundColor, BorderSizePixel = 0 }, self._frame)
    round(card, math.max(5, self._hub.Config.CornerRadius - 3))
    local title = create('TextLabel', { Size = UDim2.new(1,-12,0,20), Position = UDim2.fromOffset(6,6), BackgroundTransparency = 1, Text = opts.Name or 'Stat', TextColor3 = self._hub.Config.MutedTextColor, Font = self._hub.Config.Font, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, card)
    local value = create('TextLabel', { Size = UDim2.new(1,-12,0,36), Position = UDim2.fromOffset(6,26), BackgroundTransparency = 1, Text = opts.Value or '-', TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left }, card)
    return {
        Set = function(_, v) value.Text = tostring(v) end,
        Get = function() return value.Text end,
        Destroy = function() pcall(function() card:Destroy() end) end
    }
end

-- Progress bar
function Section:CreateProgressBar()
    local container = create('Frame', { Size = UDim2.new(1,0,0,34), BackgroundTransparency = 1 }, self._frame)
    local barBg = create('Frame', { Size = UDim2.new(1, -12, 0, 12), Position = UDim2.fromOffset(6,12), BackgroundColor3 = self._hub.Config.PanelColor, BorderSizePixel = 0 }, container)
    round(barBg, 6)
    local fill = create('Frame', { Size = UDim2.new(0,0,1,0), BackgroundColor3 = self._hub.Config.ThemeColor, BorderSizePixel = 0 }, barBg)
    round(fill, 6)
    local wrapper = {}
    function wrapper:Set(p) fill:TweenSize(UDim2.new(math.clamp(p/100,0,1),0,1,0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true) end
    function wrapper:Get() return fill.Size.X.Scale * 100 end
    function wrapper:Destroy() pcall(function() container:Destroy() end) end
    return wrapper
end

-- Player list (auto-updating)
function Section:CreatePlayerList(params)
    params = params or {}
    local container = create('Frame', { Size = UDim2.new(1,0,0,200), BackgroundTransparency = 1 }, self._frame)
    local scroll = create('ScrollingFrame', { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6,6), BackgroundTransparency = 1, ScrollBarThickness = 6 }, container)
    local layout = create('UIListLayout', { Padding = UDim.new(0,4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    local entries = {}
    local function rebuild()
        for _,v in pairs(entries) do pcall(function() v:Destroy() end) end
        entries = {}
        for _,p in ipairs(Players:GetPlayers()) do
            local b = create('TextButton', { Size = UDim2.new(1,0,0,28), BackgroundColor3 = self._hub.Config.BackgroundColor, Text = p.Name, TextColor3 = self._hub.Config.TextColor, Font = self._hub.Config.Font, TextSize = 13, AutoButtonColor = false }, scroll)
            round(b, 6)
            if params.Callback then self._maid:Give(b.Activated:Connect(function() pcall(function() params.Callback(p) end) end)) end
            table.insert(entries, b)
        end
        scroll.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y)
    end
    self._maid:Give(Players.PlayerAdded:Connect(rebuild)); self._maid:Give(Players.PlayerRemoving:Connect(rebuild))
    rebuild()
    return { Destroy = function() pcall(function() container:Destroy() end) end }
end

-- Target selector (dropdown of players)
function Section:CreateTargetSelector()
    local function getPlayers()
        local list = {}
        for _,p in ipairs(Players:GetPlayers()) do table.insert(list, p.Name) end
        return list
    end
    local dd = self:CreateDropdown({ Name = "Target", Options = getPlayers() })
    self._maid:Give(Players.PlayerAdded:Connect(function() dd:Refresh(getPlayers()) end))
    self._maid:Give(Players.PlayerRemoving:Connect(function() dd:Refresh(getPlayers()) end))
    return dd
end

-- Return public constructor
return setmetatable({
    new = function(opts) return WaffleHub.new(opts) end,
}, { __index = WaffleHub })
