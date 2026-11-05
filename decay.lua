-- ==============================================================================
-- TeteKubb Hub (Stable Edition - No Hitbox Expander)
-- Features: Fast Predictive Aimbot (Head/Torso), No Recoil, Fullbright, Auto Spark & Full ESP
-- Supports: PC & Mobile | Anti-Cheat Bypass Included
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ==============================================================================
-- [0] CLEANUP OLD INSTANCE & LIFECYCLE FLAG (ล้างสคริปต์เก่าและคืนค่าพาร์ททั้งหมด)
-- ==============================================================================
local GlobalEnv = (getgenv and getgenv()) or _G

if GlobalEnv.RustHubCleanup then
    pcall(GlobalEnv.RustHubCleanup)
end

for _, bindName in ipairs({
    "RustV6AimbotEngine",
    "RustV7AimbotEngine",
    "RustV8AimbotEngine",
    "RustV9AimbotEngine",
    "RustV10AimbotEngine",
    "RustV11AimbotEngine",
    "TeteKubbAimbotEngine"
}) do
    pcall(function() RunService:UnbindFromRenderStep(bindName) end)
end

local SafeGuiParent = (gethui and gethui()) or CoreGui
for _, parentGui in ipairs({ SafeGuiParent, CoreGui, LocalPlayer:FindFirstChild("PlayerGui") }) do
    if parentGui then
        local old = parentGui:FindFirstChild("RustSafeOverlay")
        if old then pcall(function() old:Destroy() end) end
    end
end

local ScriptRunning = true
local ActiveConnections = {}
local function AddConnection(conn)
    if conn then
        table.insert(ActiveConnections, conn)
    end
    return conn
end

-- ==============================================================================
-- [1] ANTI-CHEAT BYPASS (บล็อกเฉพาะ ReplicatedStorage.AntiCheat.RemoteEvents.Auto)
-- ==============================================================================
local AntiCheatRemote = nil
pcall(function()
    local acFolder = ReplicatedStorage:WaitForChild("AntiCheat", 5)
    local remFolder = acFolder and acFolder:WaitForChild("RemoteEvents", 5)
    AntiCheatRemote = remFolder and remFolder:WaitForChild("Auto", 5)
end)

if hookmetamethod and not GlobalEnv._TeteKubbACBypassed then
    GlobalEnv._TeteKubbACBypassed = true
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if not checkcaller() and (method == "FireServer" or method == "InvokeServer") then
            if (AntiCheatRemote and self == AntiCheatRemote) or (self.Name == "Auto" and self.Parent and self.Parent.Name == "RemoteEvents") then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end))
end

-- ==============================================================================
-- [2] GLOBAL CONFIG (เริ่มต้นปิดไว้ทั้งหมด เปิด-ปิดได้ตามสั่ง 100%)
-- ==============================================================================
local Config = {
    -- ระบบ Aimbot ล็อคหัว / ล็อคตัว + ดักทางคนวิ่ง
    AimlockEnabled = false,
    AimActivationMode = "Always", -- "Always" (ล็อคทันทีในวง FOV), "HoldClick" (ล็อคตอนกดคลิกยิง/ซูม)
    TargetPartMode = "Head", -- "Head" (ล็อคหัว), "Torso" (ล็อคตัว), "ClosestPart" (ส่วนที่ใกล้เป้าสุด)
    AirborneBodyAim = true, -- สลับล็อคลำตัวอัตโนมัติเวลาศัตรูกระโดด
    StickyAim = true, -- ล็อคเกาะเป้าหมายเดิมไม่สวิงมั่ว
    AimSmoothness = 0.55, -- ความไวในการดูดตามคนวิ่ง (0.10 - 0.95)
    UsePrediction = true, -- คำนวณดักหน้าเวลาคนวิ่ง
    PredictionMultiplier = 1.10, -- ตัวคูณระยะดักหน้าคนวิ่ง
    BulletDropCompensation = true, -- ชดเชยกระสุนตกตามระยะทาง
    BreakawayThreshold = 9.5, -- แรงสะบัดเมาส์เพื่อดึงเป้าหลุดล็อค
    MaxAimDistance = 900,
    FOVRadius = 150,
    ShowFOV = false,
    ShowTargetLine = false,
    ShowStatusHUD = false,
    LockScientists = true,
    WallCheck = false,
    TeamCheck = false,

    -- ปุ่มลัดคีย์บอร์ด (Keybinds)
    Key_ToggleAimbot = Enum.KeyCode.X,
    Key_SwitchPart = Enum.KeyCode.V,
    Key_ToggleFullbright = Enum.KeyCode.B,

    -- ระบบลดแรงดีดปืน (No Recoil)
    NoRecoilEnabled = false,
    RecoilScale = 0,

    -- ระบบความสว่างตอนกลางคืน & ตัดหมอก (Fullbright)
    FullbrightEnabled = false,
    FullbrightLevel = 2.5,
    RemoveFogAndShadows = true,

    -- ระบบตีแร่โดนจุด Spark อัตโนมัติ
    AutoSparkEnabled = false,
    ShowSparkESP = true,
    SparkRange = 10,

    -- ระบบ ESP แยกหมวดหมู่
    ESP_Players = false,
    ESP_Scientists = false,
    ESP_Sleepers = false,
    ESP_BodyBags = false,
    ESP_BaseOwner = false,
    ESP_Storage = false,
    ESP_OnlyUnlockedStorage = false,
    ESP_Traps = false,
    ESP_StoneOre = false,
    ESP_MetalOre = false,
    ESP_SulfurOre = false,
    ESP_ClothAndFood = false,
    ESP_DroppedItems = false,
    ESP_WorldCrates = false,
    PlayerRenderDistance = 1200,
    WorldRenderDistance = 600,
}

local CurrentLockedModel = nil
local CurrentLockedPart = nil
local CurrentPredictedPos = nil
local CurrentTargetName = "None"
local CachedScientists = {}

-- ==============================================================================
-- [3] FULLBRIGHT & SETAMBIENT BLOCKER (บล็อก ReplicatedStorage.TimeService.SetAmbient)
-- ==============================================================================
local SetAmbientRemote = nil
pcall(function()
    local ts = ReplicatedStorage:WaitForChild("TimeService", 5)
    SetAmbientRemote = ts and ts:WaitForChild("SetAmbient", 5)
end)

local OriginalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
}

local OriginalAtmosphere = {}
local function SaveAtmosphereState()
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") and not OriginalAtmosphere[child] then
            OriginalAtmosphere[child] = {
                Density = child.Density,
                Haze = child.Haze,
                Glare = child.Glare,
            }
        end
    end
end
SaveAtmosphereState()

local function SetTimeServiceConnections(enableConn)
    if not SetAmbientRemote or not getconnections then return end
    pcall(function()
        for _, conn in ipairs(getconnections(SetAmbientRemote.OnClientEvent)) do
            if enableConn then
                if conn.Enable then conn:Enable() end
            else
                if conn.Disable then conn:Disable() end
            end
        end
    end)
end

local function ApplyFullbrightState(enabled)
    if enabled then
        SetTimeServiceConnections(false)
        Lighting.Ambient = Color3.fromRGB(210, 210, 210)
        Lighting.OutdoorAmbient = Color3.fromRGB(210, 210, 210)
        Lighting.Brightness = Config.FullbrightLevel
        Lighting.ClockTime = 14
        if Config.RemoveFogAndShadows then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
            Lighting.GlobalShadows = false
            SaveAtmosphereState()
            for atmo, _ in pairs(OriginalAtmosphere) do
                if atmo and atmo.Parent then
                    atmo.Density = 0
                    atmo.Haze = 0
                    atmo.Glare = 0
                end
            end
        end
    else
        SetTimeServiceConnections(true)
        Lighting.Ambient = OriginalLighting.Ambient
        Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        Lighting.Brightness = OriginalLighting.Brightness
        Lighting.ClockTime = OriginalLighting.ClockTime
        Lighting.FogEnd = OriginalLighting.FogEnd
        Lighting.FogStart = OriginalLighting.FogStart
        Lighting.GlobalShadows = OriginalLighting.GlobalShadows
        for atmo, data in pairs(OriginalAtmosphere) do
            if atmo and atmo.Parent then
                atmo.Density = data.Density
                atmo.Haze = data.Haze
                atmo.Glare = data.Glare
            end
        end
    end
end

if SetAmbientRemote then
    AddConnection(SetAmbientRemote.OnClientEvent:Connect(function()
        if Config.FullbrightEnabled then
            task.defer(function() ApplyFullbrightState(true) end)
        end
    end))
end

AddConnection(RunService.Heartbeat:Connect(function()
    if Config.FullbrightEnabled then
        Lighting.Ambient = Color3.fromRGB(210, 210, 210)
        Lighting.OutdoorAmbient = Color3.fromRGB(210, 210, 210)
        Lighting.Brightness = Config.FullbrightLevel
        Lighting.ClockTime = 14
        if Config.RemoveFogAndShadows then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
            Lighting.GlobalShadows = false
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("Atmosphere") then
                    if not OriginalAtmosphere[child] then
                        OriginalAtmosphere[child] = { Density = child.Density, Haze = child.Haze, Glare = child.Glare }
                    end
                    child.Density = 0
                    child.Haze = 0
                end
            end
        end
    end
end))

-- ==============================================================================
-- [4] LOAD GAME ITEM DATA & NO RECOIL HOOK
-- ==============================================================================
local GameItemData = nil
local GameAmmoTypes = nil

pcall(function()
    local itemMod = ReplicatedStorage:WaitForChild("ItemData", 5)
    if itemMod then GameItemData = require(itemMod).Items end
    local ammoMod = ReplicatedStorage:WaitForChild("AmmoTypes", 5)
    if ammoMod then GameAmmoTypes = require(ammoMod) end
end)

pcall(function()
    local RecoilConfigModule = ReplicatedStorage:WaitForChild("RecoilConfig", 5)
    if RecoilConfigModule then
        local RecoilConfig = require(RecoilConfigModule)
        if RecoilConfig and type(RecoilConfig.GetRecoil) == "function" then
            if not RecoilConfig._OrigGetRecoil then
                RecoilConfig._OrigGetRecoil = RecoilConfig.GetRecoil
            end
            local origFn = RecoilConfig._OrigGetRecoil
            RecoilConfig.GetRecoil = function(shotIndex, gunName, ...)
                local recoilVec = origFn(shotIndex, gunName, ...)
                if Config.NoRecoilEnabled and typeof(recoilVec) == "Vector3" then
                    return recoilVec * (Config.RecoilScale / 100)
                end
                return recoilVec
            end
        end
    end
end)

local MiningTools = {
    ["Rock"] = true,
    ["Stone Pickaxe"] = true,
    ["Metal Pickaxe"] = true,
    ["Jackhammer"] = true,
}

local function GetLocalCharacter()
    return LocalPlayer.Character or workspace:FindFirstChild(LocalPlayer.Name)
end

local function IsHoldingMiningTool()
    local char = GetLocalCharacter()
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if MiningTools[child.Name] then return true end
        end
    end
    local viewmodel = Camera and Camera:FindFirstChild("Viewmodel")
    if viewmodel then
        for _, child in ipairs(viewmodel:GetChildren()) do
            if MiningTools[child.Name] then return true end
        end
    end
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local inv = pGui and pGui:FindFirstChild("Inventory")
    local hotbar = inv and inv:FindFirstChild("Hotbar")
    local selSlot = hotbar and hotbar:FindFirstChild("SelectedSlot")
    if selSlot and selSlot.Value and selSlot.Value:FindFirstChild("ItemName") then
        if MiningTools[selSlot.Value.ItemName.Value] then return true end
    end
    return false
end

local function IsGameMenuOpen()
    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local inv = pGui and pGui:FindFirstChild("Inventory")
    if inv then
        local inInv = inv:FindFirstChild("InInventory")
        local inUI = inv:FindFirstChild("InUI")
        if (inInv and inInv.Value == true) or (inUI and inUI.Value == true) then
            return true
        end
    end
    return false
end

local function GetCurrentWeaponBallistics()
    local defaultSpeed = 750
    local defaultGravity = 19.6

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    local inv = pGui and pGui:FindFirstChild("Inventory")
    local hotbar = inv and inv:FindFirstChild("Hotbar")
    local selSlot = hotbar and hotbar:FindFirstChild("SelectedSlot")
    local slotObj = selSlot and selSlot.Value

    local weaponName = nil
    if slotObj and slotObj:FindFirstChild("ItemName") and slotObj.ItemName.Value ~= "" then
        weaponName = slotObj.ItemName.Value
    else
        local char = GetLocalCharacter()
        if char then
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") or (child:IsA("Model") and child:FindFirstChild("GunComponents")) then
                    weaponName = child.Name
                    break
                end
            end
        end
    end

    if not weaponName or not GameItemData or not GameItemData[weaponName] then
        return defaultSpeed, defaultGravity
    end

    local data = GameItemData[weaponName]
    local speed = data.BulletSpeed or data.ArrowSpeed or defaultSpeed
    local grav = data.BulletGravity or (data.ArrowGravityMultiplier and (workspace.Gravity * data.ArrowGravityMultiplier)) or defaultGravity

    if slotObj and GameAmmoTypes and type(GameAmmoTypes.Loaded) == "function" then
        local ok, loadedAmmo = pcall(GameAmmoTypes.Loaded, slotObj)
        if ok and loadedAmmo and GameItemData[loadedAmmo] and GameItemData[loadedAmmo].VelocityMultiplier then
            speed = speed * GameItemData[loadedAmmo].VelocityMultiplier
        end
    end

    return speed, grav
end

-- ==============================================================================
-- [5] CHARACTER RESOLVER & TEAM CHECK
-- ==============================================================================
local function GetPlayerCharacter(player)
    if not player then return nil end
    if player.Character and player.Character.Parent then
        return player.Character
    end
    local wsChar = workspace:FindFirstChild(player.Name)
    if wsChar and wsChar:IsA("Model") then
        return wsChar
    end
    return nil
end

local function GetCharacterHealth(char)
    if not char or not char.Parent then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health
    end
    local hpVal = char:FindFirstChild("Health")
    if hpVal and hpVal:IsA("ValueBase") and tonumber(hpVal.Value) then
        return tonumber(hpVal.Value)
    end
    return 0
end

local function IsTeammate(player)
    if not Config.TeamCheck then return false end
    if player == LocalPlayer then return true end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local teamUI = playerGui and playerGui:FindFirstChild("TeamUI")
    local teamFrame = teamUI and teamUI:FindFirstChild("Team")

    if teamFrame then
        for _, child in ipairs(teamFrame:GetChildren()) do
            if child.Name == player.Name or child.Name == player.DisplayName or child.Name == tostring(player.UserId) then
                return true
            end
            for _, desc in ipairs(child:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Text ~= "" then
                    if string.find(desc.Text, player.Name, 1, true) or string.find(desc.Text, player.DisplayName, 1, true) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- ==============================================================================
-- [6] REAL-TIME VELOCITY TRACKER & BALLISTICS PREDICTION
-- ==============================================================================
local VelocityTracker = {}

local function GetTargetVelocity(model, rootPart)
    if not model or not rootPart then return Vector3.zero end
    local now = os.clock()
    local currentPos = rootPart.Position
    local record = VelocityTracker[model]

    if not record then
        VelocityTracker[model] = {
            LastPos = currentPos,
            SmoothedVel = rootPart.AssemblyLinearVelocity or Vector3.zero,
            LastTime = now
        }
        return VelocityTracker[model].SmoothedVel
    end

    local dt = now - record.LastTime
    if dt >= 0.008 then
        local deltaVel = (currentPos - record.LastPos) / dt
        local engineVel = rootPart.AssemblyLinearVelocity or Vector3.zero

        local measuredVel = deltaVel
        if engineVel.Magnitude > 1 and deltaVel.Magnitude > 1 then
            measuredVel = (deltaVel * 0.65) + (engineVel * 0.35)
        elseif engineVel.Magnitude > deltaVel.Magnitude then
            measuredVel = engineVel
        end

        if measuredVel.Magnitude > 180 then
            measuredVel = engineVel
        end

        record.SmoothedVel = record.SmoothedVel:Lerp(measuredVel, math.clamp(dt * 18, 0.15, 0.85))
        record.LastPos = currentPos
        record.LastTime = now
    end

    return record.SmoothedVel
end

local function CalculatePredictedAimPosition(targetPart, targetModel)
    if not targetPart then return nil end
    local basePos = targetPart.Position
    if not Config.UsePrediction or not targetModel then
        return basePos
    end

    local rootPart = targetModel:FindFirstChild("HumanoidRootPart") or targetPart
    local velocity = GetTargetVelocity(targetModel, rootPart)

    local camPos = Camera.CFrame.Position
    local distance = (basePos - camPos).Magnitude
    local bulletSpeed, bulletGravity = GetCurrentWeaponBallistics()
    bulletSpeed = math.max(bulletSpeed, 80)

    local timeToHit = distance / bulletSpeed
    local futurePos1 = basePos + Vector3.new(velocity.X, velocity.Y * 0.35, velocity.Z) * timeToHit
    timeToHit = (futurePos1 - camPos).Magnitude / bulletSpeed

    local horizontalLead = Vector3.new(velocity.X, 0, velocity.Z) * (timeToHit * Config.PredictionMultiplier)
    local verticalLead = Vector3.new(0, velocity.Y * 0.30 * timeToHit * Config.PredictionMultiplier, 0)

    local dropOffset = Vector3.zero
    if Config.BulletDropCompensation and distance > 25 then
        local dropY = 0.5 * bulletGravity * (timeToHit ^ 2)
        dropOffset = Vector3.new(0, math.clamp(dropY, 0, 25), 0)
    end

    return basePos + horizontalLead + verticalLead + dropOffset
end

-- ==============================================================================
-- [7] SOLID-HIT WALLCHECK, ORE SPARK FINDER & SMART BONE SELECTOR
-- ==============================================================================
local function IsTargetVisible(targetPart, targetModel)
    if not Config.WallCheck then return true end
    if not targetPart then return false end

    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local filterList = { GetLocalCharacter(), Camera }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    for _ = 1, 10 do
        rayParams.FilterDescendantsInstances = filterList
        local result = workspace:Raycast(origin, direction, rayParams)
        if not result then return true end

        local hitPart = result.Instance
        if targetModel and hitPart:IsDescendantOf(targetModel) then
            return true
        end

        local isSeeThrough = (hitPart ~= workspace.Terrain) and (
            hitPart.Transparency >= 0.9
            or not hitPart.CanCollide
            or hitPart.Name == "Range"
            or hitPart.Name == "Top"
            or hitPart.Name == "Bot"
        )

        if isSeeThrough then
            table.insert(filterList, hitPart)
        else
            return false
        end
    end
    return true
end

local function GetSmartAimPart(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or root

    if Config.AirborneBodyAim and root then
        local velY = math.abs(root.AssemblyLinearVelocity.Y)
        local inAir = (hum and hum.FloorMaterial == Enum.Material.Air) or (velY > 6.5)
        if inAir and torso then
            return torso
        end
    end

    if Config.TargetPartMode == "Torso" then
        return torso or head
    elseif Config.TargetPartMode == "ClosestPart" then
        local screenCenter = Camera.ViewportSize / 2
        local bestPart = head or torso
        local minDist = math.huge
        for _, partName in ipairs({ "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }) do
            local p = character:FindFirstChild(partName)
            if p and p:IsA("BasePart") then
                local sp, onScreen = Camera:WorldToViewportPoint(p.Position)
                if onScreen then
                    local d = (Vector2.new(sp.X, sp.Y) - screenCenter).Magnitude
                    if d < minDist then
                        minDist = d
                        bestPart = p
                    end
                end
            end
        end
        return bestPart
    end

    return head or torso
end

local function GetActiveSparkPart(oreModel)
    if not oreModel or not oreModel.Parent then return nil end
    local sys = oreModel:FindFirstChild("System")
    if not sys then return nil end
    local hp = sys:FindFirstChild("Health")
    if hp and hp.Value <= 0 then return nil end
    local sparkSpots = sys:FindFirstChild("SparkSpots")
    local sparkNum = sys:FindFirstChild("SparkNumber")
    if sparkSpots and sparkNum then
        local spotPart = sparkSpots:FindFirstChild(tostring(sparkNum.Value))
        if spotPart and spotPart:IsA("BasePart") then return spotPart end
        local firstSpot = sparkSpots:FindFirstChildWhichIsA("BasePart")
        if firstSpot then return firstSpot end
    end
    return oreModel.PrimaryPart or oreModel:FindFirstChildWhichIsA("BasePart")
end

local function GetNearestOreSpark(maxDist)
    local char = GetLocalCharacter()
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local oreSpawns = workspace:FindFirstChild("OreSpawns")
    if not root or not oreSpawns then return nil, nil end

    local bestSparkPart, bestOre = nil, nil
    local shortestDist = maxDist or Config.SparkRange

    for _, zone in ipairs(oreSpawns:GetChildren()) do
        for _, ore in ipairs(zone:GetChildren()) do
            local primary = ore.PrimaryPart or ore:FindFirstChild("Top") or ore:FindFirstChildWhichIsA("BasePart")
            if primary then
                local dist = (primary.Position - root.Position).Magnitude
                if dist <= shortestDist then
                    local sparkPart = GetActiveSparkPart(ore)
                    if sparkPart then
                        shortestDist = dist
                        bestSparkPart = sparkPart
                        bestOre = ore
                    end
                end
            end
        end
    end
    return bestSparkPart, bestOre
end

-- ==============================================================================
-- [8] UI OVERLAY (FOV CIRCLE, TARGET LINE, STATUS HUD & ESP)
-- ==============================================================================
local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "RustSafeOverlay"
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.Parent = SafeGuiParent

local StatusHUD = Instance.new("TextLabel")
StatusHUD.Name = "StatusHUD"
StatusHUD.Size = UDim2.fromOffset(520, 28)
StatusHUD.AnchorPoint = Vector2.new(0.5, 0)
StatusHUD.Position = UDim2.new(0.5, 0, 0, 42)
StatusHUD.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
StatusHUD.BackgroundTransparency = 0.25
StatusHUD.Font = Enum.Font.GothamBold
StatusHUD.TextSize = 13
StatusHUD.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusHUD.TextStrokeTransparency = 0.2
StatusHUD.Text = ""
StatusHUD.Visible = false
StatusHUD.Parent = OverlayGui

local HUDCorner = Instance.new("UICorner")
HUDCorner.CornerRadius = UDim.new(0, 8)
HUDCorner.Parent = StatusHUD

local HUDStroke = Instance.new("UIStroke")
HUDStroke.Color = Color3.fromRGB(90, 90, 110)
HUDStroke.Thickness = 1.2
HUDStroke.Parent = StatusHUD

local FOVCircleFrame = Instance.new("Frame")
FOVCircleFrame.Name = "FOVCircle"
FOVCircleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
FOVCircleFrame.BackgroundTransparency = 1
FOVCircleFrame.Visible = false
FOVCircleFrame.Parent = OverlayGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVCircleFrame

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Color = Color3.fromRGB(255, 255, 255)
FOVStroke.Thickness = 1.5
FOVStroke.Transparency = 0.2
FOVStroke.Parent = FOVCircleFrame

local PredictionDot = Instance.new("Frame")
PredictionDot.Name = "PredictionDot"
PredictionDot.Size = UDim2.fromOffset(10, 10)
PredictionDot.AnchorPoint = Vector2.new(0.5, 0.5)
PredictionDot.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
PredictionDot.BorderSizePixel = 0
PredictionDot.Visible = false
PredictionDot.Parent = OverlayGui

local PredCorner = Instance.new("UICorner")
PredCorner.CornerRadius = UDim.new(1, 0)
PredCorner.Parent = PredictionDot

local PredStroke = Instance.new("UIStroke")
PredStroke.Color = Color3.fromRGB(0, 0, 0)
PredStroke.Thickness = 1.5
PredStroke.Parent = PredictionDot

local TargetLine = Instance.new("Frame")
TargetLine.Name = "TargetLine"
TargetLine.AnchorPoint = Vector2.new(0.5, 0.5)
TargetLine.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
TargetLine.BorderSizePixel = 0
TargetLine.Visible = false
TargetLine.Parent = OverlayGui

local SparkMarker = Instance.new("TextLabel")
SparkMarker.Name = "SparkMarker"
SparkMarker.Size = UDim2.fromOffset(100, 26)
SparkMarker.AnchorPoint = Vector2.new(0.5, 0.5)
SparkMarker.BackgroundTransparency = 1
SparkMarker.Font = Enum.Font.GothamBold
SparkMarker.TextSize = 14
SparkMarker.TextColor3 = Color3.fromRGB(0, 255, 255)
SparkMarker.TextStrokeTransparency = 0
SparkMarker.Text = "[★ SPARK]"
SparkMarker.Visible = false
SparkMarker.Parent = OverlayGui

-- ==============================================================================
-- [9] RESPONSIVE AIMBOT ENGINE (ล็อคหัว + ล็อคตัว + ดักทางคนวิ่ง)
-- ==============================================================================
local function FindBestTargetInFOV()
    local screenCenter = Camera.ViewportSize / 2
    local camPos = Camera.CFrame.Position
    local bestPart = nil
    local bestModel = nil
    local bestName = "None"
    local shortestDist = Config.FOVRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not IsTeammate(player) then
            local char = GetPlayerCharacter(player)
            local hp = GetCharacterHealth(char)
            local part = GetSmartAimPart(char)

            if hp > 0 and part then
                local worldDist = (part.Position - camPos).Magnitude
                if worldDist <= Config.MaxAimDistance then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and screenPos.Z > 0 then
                        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if dist2D <= shortestDist and IsTargetVisible(part, char) then
                            shortestDist = dist2D
                            bestPart = part
                            bestModel = char
                            bestName = player.Name
                        end
                    end
                end
            end
        end
    end

    if Config.LockScientists then
        for _, botModel in ipairs(CachedScientists) do
            if botModel and botModel.Parent then
                local hp = GetCharacterHealth(botModel)
                local part = GetSmartAimPart(botModel)
                if hp > 0 and part then
                    local worldDist = (part.Position - camPos).Magnitude
                    if worldDist <= Config.MaxAimDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and screenPos.Z > 0 then
                            local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                            if dist2D <= shortestDist and IsTargetVisible(part, botModel) then
                                shortestDist = dist2D
                                bestPart = part
                                bestModel = botModel
                                bestName = botModel.Name
                            end
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestModel, bestName
end

local IsMobileAttacking = false
local IsMobileAiming = false
pcall(function()
    local mobileGui = LocalPlayer:WaitForChild("PlayerGui", 5):WaitForChild("MobileControls", 5)
    local frame = mobileGui and mobileGui:WaitForChild("Frame", 5)
    if frame then
        local attackBtn = frame:FindFirstChild("Attack")
        if attackBtn then
            AddConnection(attackBtn.MouseButton1Down:Connect(function() IsMobileAttacking = true end))
            AddConnection(attackBtn.MouseButton1Up:Connect(function() IsMobileAttacking = false end))
        end
        local aimBtn = frame:FindFirstChild("Aim")
        if aimBtn and aimBtn:FindFirstChild("Toggle") then
            AddConnection(aimBtn.Toggle.Changed:Connect(function(val) IsMobileAiming = val end))
        end
    end
end)

local function IsAimKeyActive()
    if IsGameMenuOpen() then return false end
    if Config.AimActivationMode == "Always" then return true end
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        or IsMobileAttacking
        or IsMobileAiming
end

local function GetKeyNameSafe(keyItem)
    if typeof(keyItem) == "EnumItem" then return keyItem.Name end
    return tostring(keyItem or "None")
end

local function UpdateAimbotStep()
    if not ScriptRunning then return end
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local screenCenter = Camera.ViewportSize / 2

    FOVCircleFrame.Visible = (Config.ShowFOV == true)
    if Config.ShowFOV then
        FOVCircleFrame.Position = UDim2.fromOffset(screenCenter.X, screenCenter.Y)
        FOVCircleFrame.Size = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2)
    end

    StatusHUD.Visible = (Config.ShowStatusHUD == true)
    if Config.ShowStatusHUD then
        local aimTxt = Config.AimlockEnabled and "ON" or "OFF"
        local fbTxt = Config.FullbrightEnabled and "ON" or "OFF"
        StatusHUD.Text = string.format(
            "TeteKubb | [%s] Aimbot: %s | [%s] เล็ง: %s | [%s] แสง: %s | เป้า: %s",
            GetKeyNameSafe(Config.Key_ToggleAimbot), aimTxt,
            GetKeyNameSafe(Config.Key_SwitchPart), tostring(Config.TargetPartMode),
            GetKeyNameSafe(Config.Key_ToggleFullbright), fbTxt,
            tostring(CurrentTargetName)
        )
    end

    if Config.AutoSparkEnabled then
        local sparkPart = GetNearestOreSpark(Config.SparkRange)
        if sparkPart then
            local spScreen, onScreen = Camera:WorldToViewportPoint(sparkPart.Position)
            if onScreen and Config.ShowSparkESP then
                SparkMarker.Position = UDim2.fromOffset(spScreen.X, spScreen.Y)
                SparkMarker.Visible = true
            else
                SparkMarker.Visible = false
            end

            local isAttacking = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or IsMobileAttacking
            if isAttacking and IsHoldingMiningTool() and not IsGameMenuOpen() then
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, sparkPart.Position), 0.60)
            end
        else
            SparkMarker.Visible = false
        end
    else
        SparkMarker.Visible = false
    end

    if not Config.AimlockEnabled then
        CurrentLockedPart = nil
        CurrentLockedModel = nil
        CurrentPredictedPos = nil
        CurrentTargetName = "None"
        PredictionDot.Visible = false
        TargetLine.Visible = false
        FOVStroke.Color = Color3.fromRGB(255, 255, 255)
        return
    end

    if Config.StickyAim and CurrentLockedModel and CurrentLockedModel.Parent then
        local hp = GetCharacterHealth(CurrentLockedModel)
        CurrentLockedPart = GetSmartAimPart(CurrentLockedModel)
        if CurrentLockedPart then
            local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentLockedPart.Position)
            local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
            local worldDist = (CurrentLockedPart.Position - Camera.CFrame.Position).Magnitude

            if hp <= 0 or not onScreen or dist2D > (Config.FOVRadius * 1.25) or worldDist > Config.MaxAimDistance or not IsTargetVisible(CurrentLockedPart, CurrentLockedModel) then
                CurrentLockedPart = nil
                CurrentLockedModel = nil
                CurrentPredictedPos = nil
                CurrentTargetName = "None"
            end
        else
            CurrentLockedModel = nil
            CurrentPredictedPos = nil
            CurrentTargetName = "None"
        end
    else
        CurrentLockedPart = nil
        CurrentLockedModel = nil
    end

    if not CurrentLockedPart then
        CurrentLockedPart, CurrentLockedModel, CurrentTargetName = FindBestTargetInFOV()
    end

    if CurrentLockedPart and CurrentLockedModel then
        FOVStroke.Color = Color3.fromRGB(255, 65, 65)
        CurrentPredictedPos = CalculatePredictedAimPosition(CurrentLockedPart, CurrentLockedModel)

        local predScreen, predOnScreen = Camera:WorldToViewportPoint(CurrentPredictedPos)
        if predOnScreen and Config.ShowTargetLine then
            local targetVec2 = Vector2.new(predScreen.X, predScreen.Y)
            local diffVec = targetVec2 - screenCenter
            local lineLen = diffVec.Magnitude

            PredictionDot.Position = UDim2.fromOffset(targetVec2.X, targetVec2.Y)
            PredictionDot.Visible = true

            TargetLine.Size = UDim2.fromOffset(lineLen, 1.5)
            TargetLine.Position = UDim2.fromOffset((screenCenter.X + targetVec2.X) / 2, (screenCenter.Y + targetVec2.Y) / 2)
            TargetLine.Rotation = math.deg(math.atan2(diffVec.Y, diffVec.X))
            TargetLine.Visible = true
        else
            PredictionDot.Visible = false
            TargetLine.Visible = false
        end

        if IsAimKeyActive() and not IsHoldingMiningTool() then
            local mouseDelta = UserInputService:GetMouseDelta()
            local deltaMag = mouseDelta.Magnitude
            local effectiveSmooth = Config.AimSmoothness

            -- เร่งความไวในการเกาะเป้าอัตโนมัติเมื่อเป้าหมายกำลังวิ่งสปรินต์
            local targetVel = GetTargetVelocity(CurrentLockedModel, CurrentLockedModel:FindFirstChild("HumanoidRootPart") or CurrentLockedPart)
            if targetVel.Magnitude > 8 then
                effectiveSmooth = math.clamp(effectiveSmooth * 1.40, 0.20, 0.96)
            end

            local isBreakingAway = false
            if deltaMag >= Config.BreakawayThreshold and predOnScreen then
                local toTarget = Vector2.new(predScreen.X, predScreen.Y) - screenCenter
                if toTarget.Magnitude > 2 and mouseDelta.Unit:Dot(toTarget.Unit) < -0.15 then
                    isBreakingAway = true
                end
            end

            if not isBreakingAway and CurrentPredictedPos then
                local goalCFrame = CFrame.lookAt(Camera.CFrame.Position, CurrentPredictedPos)
                Camera.CFrame = Camera.CFrame:Lerp(goalCFrame, effectiveSmooth)

                if mousemoverel and predOnScreen then
                    local dx = math.round((predScreen.X - screenCenter.X) * (effectiveSmooth * 0.55))
                    local dy = math.round((predScreen.Y - screenCenter.Y) * (effectiveSmooth * 0.55))
                    if math.abs(dx) >= 1 or math.abs(dy) >= 1 then
                        pcall(mousemoverel, dx, dy)
                    end
                end
            end
        end
    else
        CurrentTargetName = "None"
        FOVStroke.Color = Color3.fromRGB(255, 255, 255)
        PredictionDot.Visible = false
        TargetLine.Visible = false
    end
end

RunService:BindToRenderStep("TeteKubbAimbotEngine", Enum.RenderPriority.Last.Value + 10, UpdateAimbotStep)
AddConnection(RunService.RenderStepped:Connect(function()
    if ScriptRunning and Config.AimlockEnabled and CurrentPredictedPos and IsAimKeyActive() and not IsHoldingMiningTool() then
        Camera = workspace.CurrentCamera
        if Camera then
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, CurrentPredictedPos), Config.AimSmoothness)
        end
    end
end))

-- ==============================================================================
-- [10] HELPER FUNCTIONS FOR ESP & BACKGROUND SCANNER
-- ==============================================================================
local UserIdNameCache = {}

local function GetPlayerNameFromId(userId)
    local numId = tonumber(userId)
    if not numId then return tostring(userId) end
    if UserIdNameCache[numId] then return UserIdNameCache[numId] end

    for _, p in ipairs(Players:GetPlayers()) do
        if p.UserId == numId then
            UserIdNameCache[numId] = p.Name
            return p.Name
        end
    end

    UserIdNameCache[numId] = "ID:" .. tostring(userId)
    task.spawn(function()
        local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(numId) end)
        if ok and name then UserIdNameCache[numId] = name end
    end)
    return UserIdNameCache[numId]
end

local function GetBaseOwnerNames(deployable)
    local authFolder = deployable:FindFirstChild("AuthorizedPlayers")
    if authFolder then
        local names = {}
        for _, child in ipairs(authFolder:GetChildren()) do
            table.insert(names, GetPlayerNameFromId(child.Name))
        end
        if #names > 0 then return table.concat(names, ", ") end
        return "ไม่มีคนยืนยันสิทธิ์"
    end
    local ownerVal = deployable:FindFirstChild("Owner")
    if ownerVal and ownerVal.Value ~= 0 then
        return GetPlayerNameFromId(ownerVal.Value)
    end
    return "ไม่ทราบชื่อ"
end

local function IsDeployableLocked(instance)
    if typeof(instance) ~= "Instance" then return false end
    local hasLock = instance:FindFirstChild("HasLock")
    local isLocked = instance:FindFirstChild("IsLocked")
    local code = instance:FindFirstChild("Code")

    if hasLock and hasLock.Value == true then
        if isLocked and isLocked.Value == true then return true end
        if code and code.Value == true and (not isLocked or isLocked.Value == false) then return true end
    end
    return false
end

local function IsActiveOnlineCharacter(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model or model.Name == p.Name then return true end
    end
    return false
end

local function GetSleeperInfo(obj)
    if typeof(obj) ~= "Instance" or not obj:IsA("Model") then return false, nil end
    if obj == GetLocalCharacter() or obj.Name == "Viewmodel" then return false, nil end

    local head = obj:FindFirstChild("Head")
    local nameUI = head and head:FindFirstChild("NameUI")
    local nameLabel = nameUI and nameUI:FindFirstChild("NameLabel")
    local sleeperName = (nameLabel and nameLabel.Text ~= "" and nameLabel.Text) or obj.Name

    if obj.Name == "Sleeper" or obj:FindFirstChild("Sleeper") then
        return true, sleeperName
    end

    local hasTorso = obj:FindFirstChild("Torso") or obj:FindFirstChild("UpperTorso") or obj:FindFirstChild("HumanoidRootPart")
    if head and hasTorso and not IsActiveOnlineCharacter(obj) then
        local hum = obj:FindFirstChildOfClass("Humanoid")
        local root = obj:FindFirstChild("HumanoidRootPart") or head
        local isLyingDown = math.abs(root.CFrame.UpVector.Y) < 0.55

        if isLyingDown or (obj.Parent and obj.Parent.Name == "Deployables") or not hum then
            return true, sleeperName
        end
    end
    return false, nil
end

local function IsScientistBot(obj)
    if typeof(obj) ~= "Instance" or not obj:IsA("Model") then return false, nil end
    if obj == GetLocalCharacter() or obj.Name == "Viewmodel" or obj.Name == "StarterCharacter" then return false, nil end
    if IsActiveOnlineCharacter(obj) then return false, nil end

    local hp = GetCharacterHealth(obj)
    local root = obj:FindFirstChild("HumanoidRootPart")
    local head = obj:FindFirstChild("Head")

    if hp > 0 and root and head then
        local lowerName = string.lower(obj.Name)
        if string.find(lowerName, "scientist") then return true, obj.Name end
        local isStanding = math.abs(root.CFrame.UpVector.Y) >= 0.55
        local isNotAnimal = not string.find(lowerName, "bear") and not string.find(lowerName, "boar") and not string.find(lowerName, "wolf")
        if isStanding and isNotAnimal and (not obj.Parent or obj.Parent.Name ~= "Deployables") then
            return true, obj.Name
        end
    end
    return false, nil
end

local function GetTargetPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        return model.PrimaryPart
            or model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Head")
            or model:FindFirstChild("Hitbox")
            or model:FindFirstChild("Core")
            or model:FindFirstChild("Top")
            or model:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function GetHeldWeapon(character)
    if not character then return "Unarmed" end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            return child.Name
        elseif child:IsA("Model") and (child:FindFirstChild("GunComponents") or child:FindFirstChild("ToolComponents") or child:FindFirstChild("Handle")) then
            return child.Name
        end
    end
    return "Unarmed"
end

local TrackedObjects = {}

local StorageTypes = {
    ["Wooden Crate"] = true,
    ["Furnace"] = true,
    ["Large Furnace"] = true,
    ["Drop Stash"] = true,
    ["Workbench"] = true,
    ["Workbench Level 2"] = true,
    ["Research Table"] = true,
}

local TrapTypes = {
    ["Shotgun Trap"] = true,
    ["Flame Turret"] = true,
}

local WorldLootTypes = {
    ["Locked Crate"] = true,
    ["MilitaryCrate"] = true,
    ["HelicopterCrate"] = true,
    ["Crate"] = true,
    ["FoodCrate"] = true,
    ["Barrel"] = true,
    ["FuelBarrel"] = true,
    ["SupplyDrop"] = true,
    ["Supply Drop"] = true,
}

local ClothAndFoodKeywords = {
    ["Cloth"] = "ผ้า (Cloth)",
    ["Hemp"] = "ต้นผ้า (Hemp)",
    ["Mushrooms"] = "เห็ด (Mushroom)",
    ["Mushroom"] = "เห็ด (Mushroom)",
    ["Apple"] = "แอปเปิ้ล (Apple)",
    ["Corn"] = "ข้าวโพด (Corn)",
    ["Pumpkin"] = "ฟักทอง (Pumpkin)",
}

task.spawn(function()
    while ScriptRunning do
        local newTracked = {}
        local newScientists = {}

        local AnyWorldESP = Config.ESP_Scientists or Config.ESP_Sleepers or Config.ESP_BodyBags
            or Config.ESP_BaseOwner or Config.ESP_Storage or Config.ESP_Traps
            or Config.ESP_StoneOre or Config.ESP_MetalOre or Config.ESP_SulfurOre
            or Config.ESP_ClothAndFood or Config.ESP_DroppedItems or Config.ESP_WorldCrates

        if AnyWorldESP or Config.LockScientists then
            local pbs = workspace:FindFirstChild("PlayerBuiltStructures")
            local deployables = pbs and pbs:FindFirstChild("Deployables")
            if deployables and AnyWorldESP then
                for _, obj in ipairs(deployables:GetChildren()) do
                    local part = GetTargetPart(obj)
                    if part then
                        local isSleeper, sleeperName = GetSleeperInfo(obj)
                        if isSleeper and Config.ESP_Sleepers then
                            table.insert(newTracked, {
                                Key = obj, Part = part, Category = "Sleeper",
                                Title = "[SLEEPER] " .. tostring(sleeperName),
                                Color = Color3.fromRGB(185, 115, 255)
                            })
                        elseif obj.Name == "BodyBag" and Config.ESP_BodyBags then
                            table.insert(newTracked, {
                                Key = obj, Part = part, Category = "BodyBag",
                                Title = "[ถุงศพ BodyBag]",
                                Color = Color3.fromRGB(255, 230, 60)
                            })
                        elseif (obj.Name == "Base Claim" or obj.Name == "Sleeping Bag") and Config.ESP_BaseOwner then
                            local ownerStr = GetBaseOwnerNames(obj)
                            local locked = IsDeployableLocked(obj)
                            local lockStatus = (obj.Name == "Base Claim") and (locked and " [ล็อก]" or " [ไม่ล็อก]") or ""
                            local prefix = (obj.Name == "Base Claim") and "[ตู้ TC บ้าน]" or "[เตียง]"
                            table.insert(newTracked, {
                                Key = obj, Part = part, Category = "BaseOwner",
                                Title = string.format("%s%s\nเจ้าของ: %s", prefix, lockStatus, ownerStr),
                                Color = Color3.fromRGB(255, 140, 50)
                            })
                        elseif StorageTypes[obj.Name] and Config.ESP_Storage then
                            local locked = IsDeployableLocked(obj)
                            if not (Config.ESP_OnlyUnlockedStorage and locked) then
                                local lockTag = locked and "[ล็อก]" or "[ไม่ล็อก]"
                                local col = locked and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(80, 230, 255)
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "Storage",
                                    Title = string.format("[%s] %s", obj.Name, lockTag),
                                    Color = col
                                })
                            end
                        elseif TrapTypes[obj.Name] and Config.ESP_Traps then
                            table.insert(newTracked, {
                                Key = obj, Part = part, Category = "Trap",
                                Title = "[กับดัก! " .. obj.Name .. "]",
                                Color = Color3.fromRGB(255, 50, 120)
                            })
                        elseif obj.Name == "Locked Crate" and Config.ESP_WorldCrates then
                            table.insert(newTracked, {
                                Key = obj, Part = part, Category = "WorldCrate",
                                Title = "[Locked Crate]",
                                Color = Color3.fromRGB(255, 215, 0)
                            })
                        end
                    end
                end
            end

            if Config.ESP_StoneOre or Config.ESP_MetalOre or Config.ESP_SulfurOre then
                local oreSpawns = workspace:FindFirstChild("OreSpawns")
                if oreSpawns then
                    for _, zone in ipairs(oreSpawns:GetChildren()) do
                        for _, ore in ipairs(zone:GetChildren()) do
                            local wantStone = Config.ESP_StoneOre and ore.Name == "Stone"
                            local wantMetal = Config.ESP_MetalOre and ore.Name == "Metal Ore"
                            local wantSulfur = Config.ESP_SulfurOre and ore.Name == "Sulfur Ore"

                            if wantStone or wantMetal or wantSulfur then
                                local sys = ore:FindFirstChild("System")
                                local hpVal = sys and sys:FindFirstChild("Health")
                                local hp = hpVal and hpVal.Value or 30
                                if hp > 0 then
                                    local part = ore.PrimaryPart or ore:FindFirstChild("Top") or ore:FindFirstChildWhichIsA("BasePart")
                                    if part then
                                        local col, label
                                        if ore.Name == "Stone" then
                                            col = Color3.fromRGB(200, 200, 200)
                                            label = "[แร่หิน Stone]"
                                        elseif ore.Name == "Metal Ore" then
                                            col = Color3.fromRGB(255, 165, 90)
                                            label = "[แร่เหล็ก Metal Ore]"
                                        else
                                            col = Color3.fromRGB(245, 255, 90)
                                            label = "[แร่กำมะถัน Sulfur Ore]"
                                        end
                                        table.insert(newTracked, {
                                            Key = ore, Part = part, Category = "Ore",
                                            Title = string.format("%s (%d HP)", label, math.floor(hp)),
                                            Color = col
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end

            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Model") and obj ~= GetLocalCharacter() and obj.Name ~= "Viewmodel" then
                    local itemNameVal = obj:FindFirstChild("ItemName")
                    local amountVal = obj:FindFirstChild("Amount")

                    if itemNameVal and itemNameVal:IsA("StringValue") then
                        local itemName = itemNameVal.Value ~= "" and itemNameVal.Value or obj.Name
                        local amt = (amountVal and amountVal.Value) or 1
                        local part = GetTargetPart(obj)

                        if part then
                            if ClothAndFoodKeywords[itemName] and Config.ESP_ClothAndFood then
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "Cloth",
                                    Title = string.format("[%s] x%d", ClothAndFoodKeywords[itemName], amt),
                                    Color = Color3.fromRGB(100, 255, 160)
                                })
                            elseif Config.ESP_DroppedItems then
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "DroppedItem",
                                    Title = string.format("[ของตก: %s] x%d", itemName, amt),
                                    Color = Color3.fromRGB(120, 255, 220)
                                })
                            end
                        end
                    else
                        local isSci, sciName = IsScientistBot(obj)
                        local isSlp, slpName = GetSleeperInfo(obj)

                        if isSci then
                            table.insert(newScientists, obj)
                            if Config.ESP_Scientists then
                                local part = GetTargetPart(obj)
                                local hp = GetCharacterHealth(obj)
                                if part then
                                    table.insert(newTracked, {
                                        Key = obj, Part = part, Category = "Scientist",
                                        Title = string.format("[BOT: %s] [%d HP]", tostring(sciName), math.floor(hp)),
                                        Color = Color3.fromRGB(255, 120, 40)
                                    })
                                end
                            end
                        elseif isSlp and Config.ESP_Sleepers then
                            local part = GetTargetPart(obj)
                            if part then
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "Sleeper",
                                    Title = "[SLEEPER] " .. tostring(slpName),
                                    Color = Color3.fromRGB(185, 115, 255)
                                })
                            end
                        elseif ClothAndFoodKeywords[obj.Name] and Config.ESP_ClothAndFood then
                            local part = GetTargetPart(obj)
                            if part then
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "Cloth",
                                    Title = "[" .. ClothAndFoodKeywords[obj.Name] .. "]",
                                    Color = Color3.fromRGB(100, 255, 160)
                                })
                            end
                        elseif WorldLootTypes[obj.Name] and Config.ESP_WorldCrates then
                            local part = GetTargetPart(obj)
                            if part then
                                table.insert(newTracked, {
                                    Key = obj, Part = part, Category = "WorldCrate",
                                    Title = "[" .. obj.Name .. "]",
                                    Color = Color3.fromRGB(255, 215, 0)
                                })
                            end
                        end
                    end
                end
            end

            if Config.ESP_Scientists or Config.LockScientists or Config.ESP_ClothAndFood or Config.ESP_WorldCrates then
                local monuments = workspace:FindFirstChild("Monuments")
                if monuments then
                    for _, desc in ipairs(monuments:GetDescendants()) do
                        if desc:IsA("Model") then
                            local isSci, sciName = IsScientistBot(desc)
                            if isSci then
                                table.insert(newScientists, desc)
                                if Config.ESP_Scientists then
                                    local part = GetTargetPart(desc)
                                    local hp = GetCharacterHealth(desc)
                                    if part then
                                        table.insert(newTracked, {
                                            Key = desc, Part = part, Category = "Scientist",
                                            Title = string.format("[BOT: %s] [%d HP]", tostring(sciName), math.floor(hp)),
                                            Color = Color3.fromRGB(255, 120, 40)
                                        })
                                    end
                                end
                            elseif Config.ESP_ClothAndFood and ClothAndFoodKeywords[desc.Name] then
                                local part = GetTargetPart(desc)
                                if part then
                                    table.insert(newTracked, {
                                        Key = desc, Part = part, Category = "Cloth",
                                        Title = "[" .. ClothAndFoodKeywords[desc.Name] .. "]",
                                        Color = Color3.fromRGB(100, 255, 160)
                                    })
                                end
                            elseif Config.ESP_WorldCrates and WorldLootTypes[desc.Name] then
                                local part = GetTargetPart(desc)
                                if part then
                                    table.insert(newTracked, {
                                        Key = desc, Part = part, Category = "WorldCrate",
                                        Title = "[" .. desc.Name .. "]",
                                        Color = Color3.fromRGB(255, 215, 0)
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        TrackedObjects = newTracked
        CachedScientists = newScientists
        task.wait(0.8)
    end
end)

-- ==============================================================================
-- [11] ESP RENDERER
-- ==============================================================================
local ESPPool = {}

local function CreateESPItem(key)
    local container = Instance.new("Frame")
    container.Name = "ESP_Item"
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = OverlayGui

    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 1.4
    boxStroke.Parent = container

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0, 240, 0, 50)
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 0, -3)
    label.Font = Enum.Font.RobotoMono
    label.TextSize = 13
    label.TextStrokeTransparency = 0.15
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Parent = container

    ESPPool[key] = {
        Frame = container,
        Stroke = boxStroke,
        Label = label
    }
    return ESPPool[key]
end

local function CleanupESP(activeKeys)
    for key, item in pairs(ESPPool) do
        if not activeKeys[key] then
            item.Frame.Visible = false
            if typeof(key) == "Instance" and not key.Parent then
                item.Frame:Destroy()
                ESPPool[key] = nil
            end
        end
    end
end

AddConnection(RunService.RenderStepped:Connect(function()
    if not ScriptRunning then return end
    local activeKeys = {}
    local myChar = GetLocalCharacter()
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local refPos = (myRoot and myRoot.Position) or Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = GetPlayerCharacter(player)
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then GetTargetVelocity(char, root) end
        end
    end

    if Config.ESP_Players then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = GetPlayerCharacter(player)
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local head = char and char:FindFirstChild("Head")
                local hp = GetCharacterHealth(char)

                if root and head and hp > 0 then
                    local dist = (root.Position - refPos).Magnitude
                    if dist <= Config.PlayerRenderDistance then
                        local topPos, onScreenTop = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.2, 0))
                        local botPos, onScreenBot = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

                        if onScreenTop or onScreenBot then
                            activeKeys[player] = true
                            local esp = ESPPool[player] or CreateESPItem(player)
                            local isTeam = IsTeammate(player)
                            local color = isTeam and Color3.fromRGB(60, 255, 100) or Color3.fromRGB(255, 65, 65)

                            local height = math.abs(botPos.Y - topPos.Y)
                            local width = height * 0.6
                            local weapon = GetHeldWeapon(char)

                            esp.Frame.Size = UDim2.fromOffset(width, height)
                            esp.Frame.Position = UDim2.fromOffset(topPos.X - width / 2, topPos.Y)
                            esp.Stroke.Color = color
                            esp.Label.TextColor3 = color
                            esp.Label.Text = string.format(
                                "%s [%d HP]\nถือ: %s (%d m)",
                                player.Name,
                                math.floor(hp),
                                weapon,
                                math.floor(dist)
                            )
                            esp.Frame.Visible = true
                        end
                    end
                end
            end
        end
    end

    for _, data in ipairs(TrackedObjects) do
        local obj = data.Key
        local part = data.Part
        if obj and obj.Parent and part and part.Parent then
            local dist = (part.Position - refPos).Magnitude
            local maxDist = (data.Category == "Scientist") and Config.PlayerRenderDistance or Config.WorldRenderDistance
            if dist <= maxDist then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    activeKeys[obj] = true
                    local esp = ESPPool[obj] or CreateESPItem(obj)

                    local boxSize = (data.Category == "Scientist") and 28 or 20
                    esp.Frame.Size = UDim2.fromOffset(boxSize, boxSize)
                    esp.Frame.Position = UDim2.fromOffset(screenPos.X - boxSize / 2, screenPos.Y - boxSize / 2)
                    esp.Stroke.Color = data.Color
                    esp.Label.TextColor3 = data.Color
                    esp.Label.Text = string.format("%s (%d m)", data.Title, math.floor(dist))
                    esp.Frame.Visible = true
                end
            end
        end
    end

    CleanupESP(activeKeys)
end))

-- ==============================================================================
-- [12] FLUENT UI SETUP (TeteKubb Hub) & KEYBIND HANDLER
-- ==============================================================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "TeteKubb Hub",
    SubTitle = "Pro Aimbot + No Recoil + Fullbright + ESP",
    TabWidth = 155,
    Size = UDim2.fromOffset(610, 480),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Aimbot & ลดแรงดีด", Icon = "crosshair" }),
    PlayerBaseESP = Window:AddTab({ Title = "ESP คน & แสงแมพ", Icon = "users" }),
    ResourceESP = Window:AddTab({ Title = "ESP แร่ & ตี Spark", Icon = "pickaxe" }),
    LootESP = Window:AddTab({ Title = "ESP ของตก & กล่อง", Icon = "box" }),
}

local function ReadToggleVal(val, toggleObj)
    if type(val) == "boolean" then return val end
    if toggleObj and type(toggleObj.Value) == "boolean" then return toggleObj.Value end
    return false
end

-- ------------------------------------------------------------------------------
-- TAB 1: PRO AIMBOT & NO RECOIL
-- ------------------------------------------------------------------------------
local AimToggle = Tabs.Combat:AddToggle("AimToggle", {
    Title = "เปิดใช้งาน Aimbot ล็อคเป้า (ปุ่มลัด: X)",
    Description = "ล็อคหัว/ตัวพร้อมคำนวณดักทางคนวิ่งอัตโนมัติ (ไม่ใช้ระบบขยายหัว ดาเมจเข้า 100%)",
    Default = false
})
AimToggle:OnChanged(function(val)
    Config.AimlockEnabled = ReadToggleVal(val, AimToggle)
end)

local TargetPartDropdown = Tabs.Combat:AddDropdown("TargetPartDropdown", {
    Title = "ส่วนที่ต้องการให้ Aimbot ล็อค (ปุ่มลัดสลับ หัว/ตัว: V)",
    Values = { "Head", "Torso", "ClosestPart" },
    Default = "Head",
})
TargetPartDropdown:OnChanged(function(val) Config.TargetPartMode = val end)

local AimActDropdown = Tabs.Combat:AddDropdown("AimActDropdown", {
    Title = "จังหวะการล็อคของ Aimbot",
    Values = { "Always", "HoldClick" },
    Default = "Always",
})
AimActDropdown:OnChanged(function(val) Config.AimActivationMode = val end)

local FOVToggle = Tabs.Combat:AddToggle("FOVToggle", {
    Title = "แสดงวงกลมระยะล็อค (FOV Circle)",
    Default = false
})
FOVToggle:OnChanged(function(val)
    Config.ShowFOV = ReadToggleVal(val, FOVToggle)
    FOVCircleFrame.Visible = Config.ShowFOV
end)

local LineToggle = Tabs.Combat:AddToggle("LineToggle", {
    Title = "แสดงเส้นชี้เป้าและจุดเขียวดักหน้า (Target Line)",
    Default = false
})
LineToggle:OnChanged(function(val)
    Config.ShowTargetLine = ReadToggleVal(val, LineToggle)
    if not Config.ShowTargetLine then
        PredictionDot.Visible = false
        TargetLine.Visible = false
    end
end)

local HUDToggle = Tabs.Combat:AddToggle("HUDToggle", {
    Title = "แสดงแถบสถานะปุ่มลัดด้านบนจอ (Status HUD)",
    Default = false
})
HUDToggle:OnChanged(function(val)
    Config.ShowStatusHUD = ReadToggleVal(val, HUDToggle)
    StatusHUD.Visible = Config.ShowStatusHUD
end)

Tabs.Combat:AddSlider("FOVRadiusSlider", {
    Title = "ขนาดวงกลม FOV (px)",
    Default = 150,
    Min = 40,
    Max = 450,
    Rounding = 0,
    Callback = function(val) Config.FOVRadius = val end
})

Tabs.Combat:AddSlider("SmoothnessSlider", {
    Title = "ความไวในการล็อคตามคนวิ่ง (Aim Speed)",
    Description = "0.55 = ตามคนวิ่งทันและสมูท | 0.85 = ล็อคติดทันที",
    Default = 0.55,
    Min = 0.10,
    Max = 0.95,
    Rounding = 2,
    Callback = function(val) Config.AimSmoothness = val end
})

local PredictToggle = Tabs.Combat:AddToggle("PredictToggle", {
    Title = "คำนวณดักหน้าเวลาคนวิ่งหนี (Velocity Prediction)",
    Default = true
})
PredictToggle:OnChanged(function(val) Config.UsePrediction = ReadToggleVal(val, PredictToggle) end)

Tabs.Combat:AddSlider("PredictionMultSlider", {
    Title = "ตัวคูณระยะดักหน้าคนวิ่ง (Prediction Multiplier)",
    Default = 1.10,
    Min = 0.50,
    Max = 2.00,
    Rounding = 2,
    Callback = function(val) Config.PredictionMultiplier = val end
})

local DropCompToggle = Tabs.Combat:AddToggle("DropCompToggle", {
    Title = "ชดเชยวิถีกระสุนตกตามระยะทาง (Bullet Drop Compensation)",
    Default = true
})
DropCompToggle:OnChanged(function(val) Config.BulletDropCompensation = ReadToggleVal(val, DropCompToggle) end)

local AirborneBodyToggle = Tabs.Combat:AddToggle("AirborneBodyToggle", {
    Title = "สลับล็อคลำตัวอัตโนมัติเมื่อศัตรูกระโดด (Airborne Body-Switch)",
    Default = true
})
AirborneBodyToggle:OnChanged(function(val) Config.AirborneBodyAim = ReadToggleVal(val, AirborneBodyToggle) end)

local NoRecoilToggle = Tabs.Combat:AddToggle("NoRecoilToggle", {
    Title = "เปิดใช้งานลดแรงดีดปืน (No Recoil)",
    Default = false
})
NoRecoilToggle:OnChanged(function(val) Config.NoRecoilEnabled = ReadToggleVal(val, NoRecoilToggle) end)

Tabs.Combat:AddSlider("RecoilScaleSlider", {
    Title = "เปอร์เซ็นต์แรงดีดปืน (Recoil Percentage %)",
    Default = 0,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(val) Config.RecoilScale = val end
})

local LockBotToggle = Tabs.Combat:AddToggle("LockBotToggle", {
    Title = "ล็อคเป้าบอทนักวิทยาศาสตร์ด้วย (Lock Scientists)",
    Default = true
})
LockBotToggle:OnChanged(function(val)
    Config.LockScientists = ReadToggleVal(val, LockBotToggle)
end)

local WallCheckToggle = Tabs.Combat:AddToggle("WallCheckToggle", {
    Title = "เช็กกำแพงกั้น (SolidHit WallCheck)",
    Default = false
})
WallCheckToggle:OnChanged(function(val) Config.WallCheck = ReadToggleVal(val, WallCheckToggle) end)

local TeamCheckToggle = Tabs.Combat:AddToggle("TeamCheckToggle", {
    Title = "ข้ามเพื่อนในปาร์ตี้ (TeamUI Check)",
    Default = false
})
TeamCheckToggle:OnChanged(function(val) Config.TeamCheck = ReadToggleVal(val, TeamCheckToggle) end)

-- ------------------------------------------------------------------------------
-- TAB 2: FULLBRIGHT & ESP ผู้เล่น / บอท / เจ้าของบ้าน
-- ------------------------------------------------------------------------------
local FullbrightToggle = Tabs.PlayerBaseESP:AddToggle("FullbrightToggle", {
    Title = "เปิดใช้งาน Fullbright & ตัดหมอก (ปุ่มลัด: B)",
    Description = "สว่างเหมือนกลางวันตลอดเวลาและบล็อกรีโมท TimeService.SetAmbient",
    Default = false
})
FullbrightToggle:OnChanged(function(val)
    Config.FullbrightEnabled = ReadToggleVal(val, FullbrightToggle)
    ApplyFullbrightState(Config.FullbrightEnabled)
end)

Tabs.PlayerBaseESP:AddSlider("FullbrightLevelSlider", {
    Title = "ระดับความสว่างของแมพ (Brightness Level)",
    Default = 2.5,
    Min = 1.0,
    Max = 5.0,
    Rounding = 1,
    Callback = function(val)
        Config.FullbrightLevel = val
        if Config.FullbrightEnabled then Lighting.Brightness = val end
    end
})

local T_Players = Tabs.PlayerBaseESP:AddToggle("T_Players", { Title = "ESP ผู้เล่นออนไลน์ (ชื่อ + เลือด + ปืนที่ถือ)", Default = false })
T_Players:OnChanged(function(val) Config.ESP_Players = ReadToggleVal(val, T_Players) end)

local T_Scientists = Tabs.PlayerBaseESP:AddToggle("T_Scientists", { Title = "ESP บอทนักวิทยาศาสตร์ (Road / Monument Scientist)", Default = false })
T_Scientists:OnChanged(function(val) Config.ESP_Scientists = ReadToggleVal(val, T_Scientists) end)

local T_Sleepers = Tabs.PlayerBaseESP:AddToggle("T_Sleepers", { Title = "ESP คนนอนออฟไลน์ (Sleeper)", Default = false })
T_Sleepers:OnChanged(function(val) Config.ESP_Sleepers = ReadToggleVal(val, T_Sleepers) end)

local T_BodyBags = Tabs.PlayerBaseESP:AddToggle("T_BodyBags", { Title = "ESP ถุงศพคนตาย (BodyBag)", Default = false })
T_BodyBags:OnChanged(function(val) Config.ESP_BodyBags = ReadToggleVal(val, T_BodyBags) end)

local T_BaseOwner = Tabs.PlayerBaseESP:AddToggle("T_BaseOwner", { Title = "ESP ดูชื่อเจ้าของบ้าน (สแกนตู้ TC & เตียงนอน)", Default = false })
T_BaseOwner:OnChanged(function(val) Config.ESP_BaseOwner = ReadToggleVal(val, T_BaseOwner) end)

local T_Traps = Tabs.PlayerBaseESP:AddToggle("T_Traps", { Title = "ESP กับดักในบ้าน (Shotgun Trap / Flame Turret)", Default = false })
T_Traps:OnChanged(function(val) Config.ESP_Traps = ReadToggleVal(val, T_Traps) end)

Tabs.PlayerBaseESP:AddSlider("PlayerDistSlider", {
    Title = "ระยะมองเห็นผู้เล่นและบอทสูงสุด (Studs)",
    Default = 1200,
    Min = 200,
    Max = 3000,
    Rounding = 0,
    Callback = function(val) Config.PlayerRenderDistance = val end
})

-- ------------------------------------------------------------------------------
-- TAB 3: AUTO SPARK & ESP แร่ + ผ้า
-- ------------------------------------------------------------------------------
local AutoSparkToggle = Tabs.ResourceESP:AddToggle("AutoSparkToggle", { Title = "หันกล้องตีจุด Spark ของแร่อัตโนมัติ (Auto-Hit Ore Spark)", Default = false })
AutoSparkToggle:OnChanged(function(val) Config.AutoSparkEnabled = ReadToggleVal(val, AutoSparkToggle) end)

local T_Stone = Tabs.ResourceESP:AddToggle("T_Stone", { Title = "ESP แร่หิน (Stone Ore)", Default = false })
T_Stone:OnChanged(function(val) Config.ESP_StoneOre = ReadToggleVal(val, T_Stone) end)

local T_Metal = Tabs.ResourceESP:AddToggle("T_Metal", { Title = "ESP แร่เหล็ก (Metal Ore)", Default = false })
T_Metal:OnChanged(function(val) Config.ESP_MetalOre = ReadToggleVal(val, T_Metal) end)

local T_Sulfur = Tabs.ResourceESP:AddToggle("T_Sulfur", { Title = "ESP แร่กำมะถัน (Sulfur Ore)", Default = false })
T_Sulfur:OnChanged(function(val) Config.ESP_SulfurOre = ReadToggleVal(val, T_Sulfur) end)

local T_Cloth = Tabs.ResourceESP:AddToggle("T_Cloth", { Title = "ESP ผ้า & ของป่า (Cloth / Hemp / Mushrooms)", Default = false })
T_Cloth:OnChanged(function(val) Config.ESP_ClothAndFood = ReadToggleVal(val, T_Cloth) end)

-- ------------------------------------------------------------------------------
-- TAB 4: ESP กล่องเก็บของ & ของตกพื้น
-- ------------------------------------------------------------------------------
local T_Storage = Tabs.LootESP:AddToggle("T_Storage", { Title = "ESP กล่องเก็บของ & เตาเผา (Crate / Furnace / Stash)", Default = false })
T_Storage:OnChanged(function(val) Config.ESP_Storage = ReadToggleVal(val, T_Storage) end)

local T_UnlockedOnly = Tabs.LootESP:AddToggle("T_UnlockedOnly", { Title = "กรองเฉพาะกล่องที่ไม่ได้ล็อก (Unlocked Only)", Default = false })
T_UnlockedOnly:OnChanged(function(val) Config.ESP_OnlyUnlockedStorage = ReadToggleVal(val, T_UnlockedOnly) end)

local T_Dropped = Tabs.LootESP:AddToggle("T_Dropped", { Title = "ESP ของและอาวุธที่ดรอปบนพื้น (Dropped Items)", Default = false })
T_Dropped:OnChanged(function(val) Config.ESP_DroppedItems = ReadToggleVal(val, T_Dropped) end)

local T_WorldCrates = Tabs.LootESP:AddToggle("T_WorldCrates", { Title = "ESP กล่องฟาร์มตามแมพ & แอร์ดรอป (Military / Locked Crate / Barrel)", Default = false })
T_WorldCrates:OnChanged(function(val) Config.ESP_WorldCrates = ReadToggleVal(val, T_WorldCrates) end)

Tabs.LootESP:AddSlider("WorldDistSlider", {
    Title = "ระยะมองเห็นแร่และสิ่งของสูงสุด (Studs)",
    Default = 600,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(val) Config.WorldRenderDistance = val end
})

-- ==============================================================================
-- [ระบบปุ่มลัดคีย์บอร์ด X / V / B (ตัดปุ่มขยายหัวออกแล้ว)]
-- ==============================================================================
AddConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or not ScriptRunning then return end
    if input.KeyCode == Config.Key_ToggleAimbot then
        AimToggle:SetValue(not Config.AimlockEnabled)
        Fluent:Notify({
            Title = "TeteKubb Hub (ปุ่ม X)",
            Content = Config.AimlockEnabled and "เปิด Aimbot ล็อคเป้าแล้ว" or "ปิด Aimbot แล้ว",
            Duration = 1.5
        })
    elseif input.KeyCode == Config.Key_SwitchPart then
        local nextMode = (Config.TargetPartMode == "Head") and "Torso" or "Head"
        TargetPartDropdown:SetValue(nextMode)
        Fluent:Notify({
            Title = "TeteKubb Hub (ปุ่ม V)",
            Content = "สลับจุดล็อคเป็น: " .. nextMode,
            Duration = 1.5
        })
    elseif input.KeyCode == Config.Key_ToggleFullbright then
        FullbrightToggle:SetValue(not Config.FullbrightEnabled)
        Fluent:Notify({
            Title = "TeteKubb Hub (ปุ่ม B)",
            Content = Config.FullbrightEnabled and "เปิดแสงสว่าง + ตัดหมอกแล้ว" or "คืนค่าแสงแมพปกติแล้ว",
            Duration = 1.5
        })
    end
end))

-- ==============================================================================
-- [ปุ่มลอยสำหรับมือถือ & ฟังก์ชัน Cleanup]
-- ==============================================================================
local MobileToggleBtn = Instance.new("TextButton")
MobileToggleBtn.Name = "MobileToggleUI"
MobileToggleBtn.Size = UDim2.fromOffset(52, 52)
MobileToggleBtn.Position = UDim2.new(0, 16, 0.45, -26)
MobileToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
MobileToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileToggleBtn.Font = Enum.Font.GothamBold
MobileToggleBtn.TextSize = 11
MobileToggleBtn.Text = "TETE"
MobileToggleBtn.Draggable = true
MobileToggleBtn.Active = true
MobileToggleBtn.Parent = OverlayGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 12)
BtnCorner.Parent = MobileToggleBtn

AddConnection(MobileToggleBtn.MouseButton1Click:Connect(function()
    Window:Minimize()
end))

local QuickLockBtn = Instance.new("TextButton")
QuickLockBtn.Name = "QuickLockBtn"
QuickLockBtn.Size = UDim2.fromOffset(52, 52)
QuickLockBtn.Position = UDim2.new(0, 16, 0.55, -26)
QuickLockBtn.BackgroundColor3 = Color3.fromRGB(45, 30, 65)
QuickLockBtn.TextColor3 = Color3.fromRGB(220, 180, 255)
QuickLockBtn.Font = Enum.Font.GothamBold
QuickLockBtn.TextSize = 11
QuickLockBtn.Text = "AIM"
QuickLockBtn.Draggable = true
QuickLockBtn.Active = true
QuickLockBtn.Parent = OverlayGui

local LockBtnCorner = Instance.new("UICorner")
LockBtnCorner.CornerRadius = UDim.new(0, 12)
LockBtnCorner.Parent = QuickLockBtn

AddConnection(QuickLockBtn.MouseButton1Click:Connect(function()
    AimToggle:SetValue(not Config.AimlockEnabled)
end))

GlobalEnv.RustHubCleanup = function()
    ScriptRunning = false
    pcall(function() RunService:UnbindFromRenderStep("TeteKubbAimbotEngine") end)
    for _, conn in ipairs(ActiveConnections) do
        pcall(function() conn:Disconnect() end)
    end
    ActiveConnections = {}
    pcall(function() ApplyFullbrightState(false) end)
    if OverlayGui and OverlayGui.Parent then
        pcall(function() OverlayGui:Destroy() end)
    end
end

Window:SelectTab(1)
