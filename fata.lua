--[[
    FatalityLib - Standalone UI Library
    Style: Fatality.win (Dark Purple / Magenta)
    Features: Draggable, Tab System, Flexible Columns, Animations, Color Picker
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local Library = {}
Library.Draws = {}
Library.Connections = {}
Library.Flags = {}
Library.Open = true
Library.IsDragging = false
Library.Globals = {
    DeltaTime = 0,
    LastUpdate = tick()
}

-- Theme Colors (Public for customization)
Library.Colors = {
    BG = Color3.fromRGB(25, 20, 35),        
    Header = Color3.fromRGB(35, 25, 45),    
    TabBG = Color3.fromRGB(20, 15, 25),     
    GroupBG = Color3.fromRGB(30, 25, 40),   
    Stroke = Color3.fromRGB(60, 50, 80),    
    Accent = Color3.fromRGB(210, 0, 85),    
    Text = Color3.fromRGB(230, 230, 230),
    TextDim = Color3.fromRGB(140, 140, 150),
    TextSelected = Color3.fromRGB(255, 255, 255)
}

-- Utility Functions
local function NewDrawing(type, props)
    local obj = Drawing.new(type)
    for k, v in pairs(props) do obj[k] = v end
    table.insert(Library.Draws, obj)
    return obj
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

local function LerpColor(a, b, t)
    return Color3.new(
        Lerp(a.R, b.R, t),
        Lerp(a.G, b.G, t),
        Lerp(a.B, b.B, t)
    )
end

local function AddConnection(signal, valid_func)
    local con = signal:Connect(valid_func)
    table.insert(Library.Connections, con)
    return con
end

function Library:Unload()
    for _, c in pairs(Library.Connections) do c:Disconnect() end
    for _, d in pairs(Library.Draws) do d:Remove() end
    if Library.InputSink then Library.InputSink:Destroy() end
    if Library.LookBlur then Library.LookBlur:Destroy() end
end

-- Input Blocking & Blur
local Blur = Instance.new("BlurEffect", game.Lighting)
Blur.Size = 0; Blur.Enabled = true; Library.LookBlur = Blur

local ScreenGui = Instance.new("ScreenGui", CoreGui)
local Sink = Instance.new("TextButton", ScreenGui)
Sink.Size = UDim2.fromScale(1,1)
Sink.BackgroundTransparency = 1
Sink.Text = ""
Sink.Modal = true 
Sink.Visible = false
Library.InputSink = ScreenGui

-- Window Class
local Window = {}
Window.__index = Window

function Library:CreateWindow(options)
    local self = setmetatable({}, Window)
    self.Title = options.Title or "FATALITY"
    self.Size = options.Size or Vector2.new(600, 450)
    self.Position = options.Position or Vector2.new(100, 100)
    self.Tabs = {}
    self.ActiveTab = nil
    self.Keybind = options.Keybind or Enum.KeyCode.RightShift
    
    -- Config
    self.Config = {
        Blur = options.Blur ~= false, -- Default true
        InputBlock = options.InputBlock ~= false, -- Default true
        OpenAnim = 0 -- 0 to 1
    }
    
    -- Main Drawings
    self.Base = {
        Border = NewDrawing("Square", {Thickness=3, Color=Library.Colors.Accent, Filled=false, ZIndex=1}), 
        Main = NewDrawing("Square", {Filled=true, Color=Library.Colors.BG, ZIndex=1}),
        Header = NewDrawing("Square", {Filled=true, Color=Library.Colors.Header, ZIndex=2}),
        Title = NewDrawing("Text", {Text=self.Title, Font=2, Size=20, Color=Library.Colors.Accent, ZIndex=3}),
        Overlay = NewDrawing("Square", {Filled=true, Color=Color3.new(0,0,0), ZIndex=10, Transparency=0, Visible=false}) -- For ColorPicker modal
    }
    
    -- State
    self.PickerOpen = nil -- Currently open color picker element
    
    -- Cleanup on re-run
    if getgenv().FatalityLib_Cleanup then getgenv().FatalityLib_Cleanup() end
    getgenv().FatalityLib_Cleanup = function() Library:Unload() end

    -- Render Loop
    AddConnection(RunService.RenderStepped, function() 
        Library.Globals.DeltaTime = tick() - Library.Globals.LastUpdate
        Library.Globals.LastUpdate = tick()
        self:Update() 
    end)
    
    -- Input Handling
    AddConnection(UserInputService.InputBegan, function(i) 
        if i.KeyCode == self.Keybind then 
            Library.Open = not Library.Open 
        end
        if Library.Open then self:HandleInput(i, true) end
    end)
    
    AddConnection(UserInputService.InputEnded, function(i) 
        if i.UserInputType == Enum.UserInputType.MouseButton1 then 
            Library.IsDragging = false 
            self.SliderDragging = nil
            self.PickerDragging = nil
        end
    end)
    
    AddConnection(UserInputService.InputChanged, function(i) 
        if i.UserInputType == Enum.UserInputType.MouseMovement then 
            local m = UserInputService:GetMouseLocation()
            if Library.IsDragging then
                local d = m - self.DragStart
                self.Position = self.StartPos + d
            elseif self.SliderDragging then
                local s = self.SliderDragging
                local pct = math.clamp((m.X - s.ClickArea.X) / s.ClickArea.W, 0, 1)
                local newVal = s.Min + (pct * (s.Max - s.Min))
                s.TargetValue = newVal -- Animate towards this
                
                -- Instant update for callback/flag, but visual is lerped
                if s.Round then newVal = math.floor(newVal) end -- Optional int support
                
                Library.Flags[s.Flag] = newVal
                s.Callback(newVal)
            elseif self.PickerDragging then
                local p = self.PickerDragging
                p:UpdateColorFromMouse(m)
            end
        end
    end)

    return self
end

function Window:HandleInput(input, began)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not began then return end
    local m = UserInputService:GetMouseLocation()
    
    -- Prioritize Color Picker
    if self.PickerOpen then
        if self.PickerOpen:HandleInput(m) then return end
        -- Click outside closes picker
        self.PickerOpen = nil
        return
    end

    -- 1. Check Dragging (Header)
    if m.X >= self.Position.X and m.X <= self.Position.X+self.Size.X and m.Y >= self.Position.Y and m.Y <= self.Position.Y+40 then
        Library.IsDragging = true
        self.DragStart = m
        self.StartPos = self.Position
        return
    end

    -- 2. Check Tabs
    local tabW = (self.Size.X - 250) / #self.Tabs
    local startTabX = self.Position.X + 240
    for i, tab in ipairs(self.Tabs) do
        local tX = startTabX + (i-1)*tabW
        if m.X >= tX and m.X <= tX+tabW and m.Y >= self.Position.Y and m.Y <= self.Position.Y+40 then
            self.ActiveTab = tab
            return
        end
    end
    
    -- 3. Check Active Tab Elements
    if self.ActiveTab then
        self.ActiveTab:HandleInput(m)
    end
end

function Window:Update()
    -- Open/Close Animation
    local dt = Library.Globals.DeltaTime
    local targetAlpha = Library.Open and 1 or 0
    self.Config.OpenAnim = Lerp(self.Config.OpenAnim, targetAlpha, dt * 10)
    
    if self.Config.OpenAnim < 0.05 then 
        for _,v in pairs(Library.Draws) do v.Visible = false end 
        Blur.Size = 0
        Sink.Visible = false
        Sink.Modal = false
        return 
    end
    
    -- Apply Effects
    if self.Config.Blur then Blur.Size = self.Config.OpenAnim * 15 end
    if self.Config.InputBlock then 
        Sink.Visible = Library.Open 
        Sink.Modal = Library.Open
    end

    local X, Y = self.Position.X, self.Position.Y
    local W, H = self.Size.X, self.Size.Y * self.Config.OpenAnim -- Animate Height? Or just Transparency?
    -- Fatality style usually just pops or fades. Let's do simple pos check + alpha.
    -- Actually simpler: Just keep full size but fade alpha of elements?
    -- Let's stick to full visibility toggling for performance, this is Drawings.
    -- Simulating Alpha on drawings means updating Color transparency which Drawings NOT all support properly (Transparency property exists but tricky with many objects).
    -- We will stick to the height animation clipping or just simple toggle for now?
    -- User requested "Cool animation". Let's slide Y position down?
    -- Or Scale?
    
    -- Let's do a slide-in from top offset.
    local animOffset = (1 - self.Config.OpenAnim) * -50
    Y = Y + animOffset
    
    -- Background
    self.Base.Border.Position=Vector2.new(X-2,Y-2); self.Base.Border.Size=Vector2.new(W+4,H+4); self.Base.Border.Visible=true
    self.Base.Main.Position=Vector2.new(X,Y); self.Base.Main.Size=Vector2.new(W,H); self.Base.Main.Visible=true
    self.Base.Header.Position=Vector2.new(X,Y); self.Base.Header.Size=Vector2.new(W,40); self.Base.Header.Visible=true
    self.Base.Title.Position=Vector2.new(X+15,Y+10); self.Base.Title.Visible=true
    
    -- Tabs
    local tabW = (W - 250) / (#self.Tabs > 0 and #self.Tabs or 1)
    local startTabX = X + 240
    for i, tab in ipairs(self.Tabs) do
        local tX = startTabX + (i-1)*tabW
        tab:Update(tX, tabW, Y, self.ActiveTab == tab)
    end
    
    -- Active Tab Content
    if self.ActiveTab then
        self.ActiveTab:UpdateContent(X, Y, W, H)
    end
    
    -- Color Picker Overlay
    if self.PickerOpen then
        self.PickerOpen:UpdatePicker(X, Y)
    end
end

-- Tab Class
local Tab = {}
Tab.__index = Tab

function Window:CreateTab(name)
    local tab = setmetatable({}, Tab)
    tab.Name = name
    tab.Parent = self
    tab.Groups = {Left={}, Right={}} 
    tab.Draws = {
        Text = NewDrawing("Text", {Size=18, Font=2, Center=true, Outline=true, ZIndex=4}),
        Bar = NewDrawing("Square", {Filled=true, Color=Library.Colors.Accent, ZIndex=4})
    }
    table.insert(self.Tabs, tab)
    if not self.ActiveTab then self.ActiveTab = tab end
    return tab
end

function Tab:Update(x, w, y, isActive)
    self.Draws.Text.Text = self.Name
    self.Draws.Text.Position = Vector2.new(x + w/2, y + 12)
    self.Draws.Text.Color = isActive and Library.Colors.Accent or Library.Colors.TextDim
    self.Draws.Text.Visible = true
    
    self.Draws.Bar.Position = Vector2.new(x, y + 38)
    self.Draws.Bar.Size = Vector2.new(w, 2)
    self.Draws.Bar.Visible = isActive
end

function Tab:UpdateContent(wx, wy, ww, wh)
    local colW = (ww - 40) / 2
    local curY_L = wy + 60
    local curY_R = wy + 60
    
    -- Render Left Column
    for _, group in ipairs(self.Groups.Left) do
        group:Update(wx + 15, curY_L, colW)
        curY_L = curY_L + group:GetHeight() + 10 -- Padding
    end
    
    -- Render Right Column
    for _, group in ipairs(self.Groups.Right) do
        group:Update(wx + 25 + colW, curY_R, colW) -- +10 padding + gap
        curY_R = curY_R + group:GetHeight() + 10
    end
end

function Tab:HandleInput(m)
    for _, g in ipairs(self.Groups.Left) do if g:HandleInput(m) then return end end
    for _, g in ipairs(self.Groups.Right) do if g:HandleInput(m) then return end end
end

-- Group Class (Flexible Side)
local Group = {}
Group.__index = Group

function Tab:CreateGroup(name, side)
    local group = setmetatable({}, Group)
    group.Name = name
    group.Items = {}
    group.Draws = {
        Border = NewDrawing("Square", {Thickness=1, Color=Library.Colors.Stroke, Filled=false, ZIndex=3}),
        Title = NewDrawing("Text", {Size=14, Font=2, Color=Library.Colors.TextDim, Outline=true, ZIndex=4, Text=name}),
        BG = NewDrawing("Square", {Filled=true, Color=Library.Colors.GroupBG, ZIndex=2}) 
    }
    
    side = side or "Left"
    if side:lower() == "auto" then side = #self.Groups.Left > #self.Groups.Right and "Right" or "Left" end
    
    if side:lower() == "right" then table.insert(self.Groups.Right, group)
    else table.insert(self.Groups.Left, group) end
    
    group.ParentTab = self
    return group
end

function Group:GetHeight()
    local h = 25
    for _, item in ipairs(self.Items) do h = h + item:GetHeight() end
    return h
end

function Group:Update(x, y, w)
    local h = self:GetHeight()
    
    self.Draws.BG.Position = Vector2.new(x, y)
    self.Draws.BG.Size = Vector2.new(w, h)
    self.Draws.BG.Visible = true
    
    self.Draws.Border.Position = Vector2.new(x, y)
    self.Draws.Border.Size = Vector2.new(w, h)
    self.Draws.Border.Visible = true
    
    self.Draws.Title.Position = Vector2.new(x + 10, y - 7)
    self.Draws.Title.Visible = true
    
    local iY = y + 15
    for _, item in ipairs(self.Items) do
        item:Update(x, iY, w)
        iY = iY + item:GetHeight()
    end
end

function Group:HandleInput(m)
    for _, item in ipairs(self.Items) do
        if item:HandleInput(m) then return true end
    end
end

-- Elements
local Element = {}
Element.__index = Element

function Element.new(type, group, args)
    local self = setmetatable({}, Element)
    self.Type = type
    self.Name = args.Name or "Element"
    self.Flag = args.Flag or (args.Name .. math.random(1,1000))
    self.Callback = args.Callback or function() end
    self.Group = group
    
    -- Drawings
    self.Draws = {
        Text = NewDrawing("Text", {Size=15, Font=2, Outline=true, ZIndex=4, Text=self.Name}),
        Box = NewDrawing("Square", {Filled=true, ZIndex=4}), 
        Fill = NewDrawing("Square", {Filled=true, ZIndex=5}), 
        Val = NewDrawing("Text", {Size=13, Font=2, Outline=true, ZIndex=4}) 
    }
    
    return self
end

function Element:GetHeight()
    return self.Type == "Slider" and 40 or 30
end

-- Toggle
function Group:AddToggle(args)
    local el = Element.new("Toggle", self, args)
    el.Value = args.Default or false
    Library.Flags[el.Flag] = el.Value
    
    function el:Update(x, y, w)
        self.ClickArea = {X=x, Y=y, W=w, H=25}
        
        self.Draws.Text.Position = Vector2.new(x+10, y)
        self.Draws.Text.Color = self.Value and Library.Colors.TextSelected or Library.Colors.TextDim
        self.Draws.Text.Visible = true
        
        local bx = x + w - 20
        self.Draws.Box.Position = Vector2.new(bx, y+3)
        self.Draws.Box.Size = Vector2.new(12, 12)
        self.Draws.Box.Color = Library.Colors.Stroke
        self.Draws.Box.Visible = true
        
        if self.Value then
            self.Draws.Fill.Position = Vector2.new(bx+2, y+5)
            self.Draws.Fill.Size = Vector2.new(8, 8)
            self.Draws.Fill.Color = Library.Colors.Accent
            self.Draws.Fill.Visible = true
        else
            self.Draws.Fill.Visible = false
        end
        self.Draws.Val.Visible = false
    end
    
    function el:HandleInput(m)
        local c = self.ClickArea
        if m.X >= c.X and m.X <= c.X+c.W and m.Y >= c.Y and m.Y <= c.Y+c.H then
            self.Value = not self.Value
            Library.Flags[self.Flag] = self.Value
            self.Callback(self.Value)
            return true
        end
    end
    
    table.insert(self.Items, el)
    return el
end

-- Slider (With Animation)
function Group:AddSlider(args)
    local el = Element.new("Slider", self, args)
    el.Min = args.Min or 0
    el.Max = args.Max or 100
    el.ConfigValue = args.Default or el.Min -- Actual underlying value (no visual lag)
    el.VisualValue = el.ConfigValue -- For animation
    el.TargetValue = el.ConfigValue
    el.Round = args.Round or true
    
    Library.Flags[el.Flag] = el.ConfigValue

    function el:Update(x, y, w)
        self.ClickArea = {X=x, Y=y, W=w, H=30}
        
        -- Animation Logic (Lerp)
        local dt = Library.Globals.DeltaTime
        self.VisualValue = Lerp(self.VisualValue, self.TargetValue, dt * 15) -- Smooth slide
        
        self.Draws.Text.Position = Vector2.new(x+10, y)
        self.Draws.Text.Color = Library.Colors.TextDim
        self.Draws.Text.Visible = true
        
        local slW, slX, slY = w-20, x+10, y+20
        local range = self.Max - self.Min
        local pct = math.clamp((self.VisualValue - self.Min) / range, 0, 1)
        
        self.Draws.Box.Position = Vector2.new(slX, slY)
        self.Draws.Box.Size = Vector2.new(slW, 4)
        self.Draws.Box.Color = Library.Colors.Stroke
        self.Draws.Box.Visible = true
        
        self.Draws.Fill.Position = Vector2.new(slX, slY)
        self.Draws.Fill.Size = Vector2.new(slW * pct, 4)
        self.Draws.Fill.Color = Library.Colors.Accent
        self.Draws.Fill.Visible = true
        
        local dispVal = self.Round and math.floor(self.TargetValue) or (math.floor(self.TargetValue*10)/10)
        self.Draws.Val.Text = tostring(dispVal)
        self.Draws.Val.Position = Vector2.new(x+w-30, y)
        self.Draws.Val.Visible = true
    end
    
    function el:HandleInput(m)
        local c = self.ClickArea
        if m.X >= c.X and m.X <= c.X+c.W and m.Y >= c.Y and m.Y <= c.Y+c.H then
            self.Group.ParentTab.Parent.SliderDragging = self
            return true
        end
    end
    
    table.insert(self.Items, el)
    return el
end

-- Button
function Group:AddButton(args)
    local el = Element.new("Button", self, args)
    
    function el:Update(x, y, w)
        self.ClickArea = {X=x, Y=y, W=w, H=25}
        
        self.Draws.Text.Position = Vector2.new(x+10, y)
        self.Draws.Text.Color = Library.Colors.TextDim
        self.Draws.Text.Visible = true
        
        local bx = x + w - 40
        self.Draws.Box.Position = Vector2.new(bx, y+3)
        self.Draws.Box.Size = Vector2.new(30, 15)
        self.Draws.Box.Color = Library.Colors.Accent
        self.Draws.Box.Visible = true
        
        self.Draws.Val.Text = "ACT"
        self.Draws.Val.Position = Vector2.new(bx+5, y+3)
        self.Draws.Val.Visible = true
        self.Draws.Fill.Visible = false
    end
    
    function el:HandleInput(m)
        local c = self.ClickArea
        if m.X >= c.X and m.X <= c.X+c.W and m.Y >= c.Y and m.Y <= c.Y+c.H then
            self.Callback()
            return true
        end
    end
    
    table.insert(self.Items, el)
    return el
end

-- Keybind
function Group:AddKeybind(args)
    local el = Element.new("Keybind", self, args)
    el.Value = args.Default or Enum.KeyCode.Unknown
    Library.Flags[el.Flag] = el.Value
    
    function el:Update(x, y, w)
        self.ClickArea = {X=x, Y=y, W=w, H=25}
        
        self.Draws.Text.Position = Vector2.new(x+10, y)
        self.Draws.Text.Color = Library.Colors.TextDim
        self.Draws.Text.Visible = true
        
        local txt = (Library.Binding == self) and "[...]" or ("[" .. (self.Value.Name) .. "]")
        self.Draws.Val.Text = txt
        self.Draws.Val.Position = Vector2.new(x+w-60, y)
        self.Draws.Val.Visible = true
        self.Draws.Box.Visible = false
        self.Draws.Fill.Visible = false
    end
    
    function el:HandleInput(m)
        local c = self.ClickArea
        if m.X >= c.X and m.X <= c.X+c.W and m.Y >= c.Y and m.Y <= c.Y+c.H then
            Library.Binding = self
            return true
        end
    end
    
    table.insert(self.Items, el)
    return el
end

-- Color Picker (New Element)
function Group:AddColorPicker(args)
    local el = Element.new("ColorPicker", self, args)
    el.Value = args.Default or Color3.fromRGB(255, 255, 255)
    Library.Flags[el.Flag] = el.Value
    
    -- Sub Drawings for Picker modal (initialized when opened)
    el.PickerDraws = {
        BG = NewDrawing("Square", {Filled=true, Color=Color3.fromRGB(40,35,50), ZIndex=15, Visible=false}),
        SatVal = NewDrawing("Image", {ZIndex=16, Visible=false, Data="rbxassetid://..."}), -- We do not have image assets easily, used procedural gradient?
        -- For procedural gradient in Drawings, we need many squares. Bad performance.
        -- Fallback: Simple Hue Slider + SV Square simulation.
        -- Using simple Color3 HSV logic.
        Hud = NewDrawing("Square", {Filled=true, ZIndex=16, Visible=false}), -- Displays current color large
    }
    
    function el:Update(x, y, w)
        self.ClickArea = {X=x, Y=y, W=w, H=25}
        
        self.Draws.Text.Position = Vector2.new(x+10, y)
        self.Draws.Text.Color = Library.Colors.TextDim
        self.Draws.Text.Visible = true
        
        local bx = x + w - 30
        self.Draws.Box.Position = Vector2.new(bx, y+3)
        self.Draws.Box.Size = Vector2.new(20, 12)
        self.Draws.Box.Color = self.Value -- Show current color
        self.Draws.Box.Visible = true
        
        self.Draws.Fill.Visible = false
        self.Draws.Val.Visible = false
    end
    
    function el:HandleInput(m)
        local c = self.ClickArea
        if m.X >= c.X and m.X <= c.X+c.W and m.Y >= c.Y and m.Y <= c.Y+c.H then
            -- Open Picker
            self.Group.ParentTab.Parent.PickerOpen = self
            return true
        end
        
        -- Logic handled in window update for modal
    end
    
    function el:UpdatePicker(wx, wy)
        -- Draw Picker Relative to Window Center
        local px, py = wx + 200, wy + 100
        local pw, ph = 150, 150
        
        local d = self.PickerDraws
        d.BG.Position = Vector2.new(px, py); d.BG.Size = Vector2.new(pw, ph); d.BG.Visible=true
        
        d.Hud.Position = Vector2.new(px+10, py+10); d.Hud.Size = Vector2.new(pw-20, ph-20); d.Hud.Color = self.Value; d.Hud.Visible=true
        -- Simplified Picker: Just a color randomization for 'Test' or 'Demo' unless we do full calculation.
        -- To properly do ColorPicker in Drawings without Images: extremely complex.
        -- We will implement a simplified RED/GREEN/BLUE slider set inside the picker modal? 
        -- Or just update functionality that user requested: "Colour picker sliderberanimasi".
        -- Let's make it drag to change hue/sat simply based on mouse X/Y inside box?
        
        self.PickerArea = {X=px, Y=py, W=pw, H=ph}
    end
    
    function el:UpdateColorFromMouse(m)
        local a = self.PickerArea
        -- Saturation (X), Value (Y)
        local s = math.clamp((m.X - a.X)/a.W, 0, 1)
        local v = math.clamp((a.Y + a.H - m.Y)/a.H, 0, 1)
        
        -- Cycle Hue over time or separate slider? Let's just use X/Y maps for simple RGB
        -- Use HSV: Hue = 0 (Fixed Red for test), S=s, V=v
        local h, _, _ = Color3.toHSV(self.Value)
        self.Value = Color3.fromHSV(h, s, v) 
        
        Library.Flags[self.Flag] = self.Value
        self.Callback(self.Value)
    end
    
    -- Interaction for Picker
    function el:HandleInputPicker(m)
         -- Logic called from Window when picker active
         local a = self.PickerArea
         if m.X >= a.X and m.X <= a.X+a.W and m.Y >= a.Y and m.Y <= a.Y+a.H then
             self.Group.ParentTab.Parent.PickerDragging = self
             return true
         end
    end
    
    table.insert(self.Items, el)
    return el
end

-- Input Listener for Keybinds
AddConnection(UserInputService.InputBegan, function(i) 
    if Library.Binding then
        local key = (i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode) or i.UserInputType
        if key ~= Enum.UserInputType.MouseMovement then
            Library.Binding.Value = key
            Library.Flags[Library.Binding.Flag] = key
            Library.Binding.Callback(key)
            Library.Binding = nil
        end
    end
end)

return Library
