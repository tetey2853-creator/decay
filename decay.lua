-- ==============================================================================
-- Rust Roblox Script V6 (True Ballistics Predictive Aimbot & Full Modular ESP)
-- Fixed Camera Priority, SolidHit WallCheck, Real-Time Velocity Tracking
-- ==============================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ==============================================================================
-- [0] ANTI-CHEAT BYPASS (บล็อก ReplicatedStorage.AntiCheat.RemoteEvents.Auto)
-- ==============================================================================
local AntiCheatRemote = nil
pcall(function()
    AntiCheatRemote = ReplicatedStorage:WaitForChild("AntiCheat", 5)
        and ReplicatedStorage.AntiCheat:WaitForChild("RemoteEvents", 5)
        and ReplicatedStorage.AntiCheat.RemoteEvents:WaitForChild("Auto", 5)
end)

if hookmetamethod then
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
-- [GLOBAL CONFIG]
-- ==============================================================================
local Config = {
    -- ระบบ Aimbot & Prediction ขั้นสูง
    AimlockEnabled = false,
    AimActivationMode = "Always", -- "Always" (ล็อคตลอดเมื่ออยู่ในวง), "HoldClick" (ล็อคตอนคลิกขวา/ยิง)
    AimMode = "Camera + Raycast", -- "Camera + Raycast", "MouseMove + Raycast"
    TargetPartName = "Head", -- "Head", "HumanoidRootPart"
    LockScientists = true, -- ล็อคหัวบอทนักวิทยาศาสตร์ด้วย
    ShowFOV = true,
    ShowTargetLine = true, -- แสดงเส้นล็อคเป้าและจุดดักหน้า
    FOVRadius = 150,
    AimSmoothness = 0.45, -- ความไวในการล็อคหัว (ปรับเพิ่มให้เกาะติดคนวิ่งทัน)
    UsePrediction = true,
    PredictionMultiplier = 1.05, -- ตัวคูณดักหน้าคนวิ่ง (1.0 = คำนวณตามความเร็วกระสุนจริง)
    BulletDropCompensation = true, -- ชดเชยกระสุนตกตามระยะทาง
    BreakawayThreshold = 8.5, -- แรงสะบัดเมาส์เพื่อดึงเป้าออก
    WallCheck = false, -- ปิดเป็นค่าเริ่มต้นเพื่อให้ล็อคติดทันที (เปิดเช็กกำแพงได้ในเมนู)
    TeamCheck = false, -- เช็กเฉพาะรายชื่อใน TeamUI.Team

    -- ระบบลดแรงดีดปืน (No Recoil)
    NoRecoilEnabled = false,
    RecoilScale = 0,

    -- ระบบตีแร่โดนจุด Spark อัตโนมัติ (Auto-Hit Spark)
    AutoSparkEnabled = false,
    AutoSparkCameraAssist = true,
    ShowSparkESP = true,
    SparkRange = 10,

    -- หมวดที่ 1: ESP ผู้เล่น, บอท และศพ
    ESP_Players = false,
    ESP_Scientists = false,
    ESP_Sleepers = false,
    ESP_BodyBags = false,

    -- หมวดที่ 2: ESP เจ้าของบ้าน & ตู้บ้าน & กับดัก
    ESP_BaseOwner = false,
    ESP_Storage = false,
    ESP_OnlyUnlockedStorage = false,
    ESP_Traps = false,

    -- หมวดที่ 3: ESP แร่และทรัพยากร
    ESP_StoneOre = false,
    ESP_MetalOre = false,
    ESP_SulfurOre = false,
    ESP_ClothAndFood = false,

    -- หมวดที่ 4: ESP ของตกพื้น & กล่องฟาร์มตามแมพ
    ESP_DroppedItems = false,
    ESP_WorldCrates = false,

    -- ระยะการแสดงผล
    PlayerRenderDistance = 1200,
    WorldRenderDistance = 600,
}

-- ==============================================================================
-- [1] LOAD GAME ITEM DATA & NO RECOIL HOOK
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
            local oldGetRecoil = RecoilConfig.GetRecoil
            RecoilConfig.GetRecoil = function(shotIndex, gunName, ...)
                local recoilVec = oldGetRecoil(shotIndex, gunName, ...)
                if Config.NoRecoilEnabled and typeof(recoilVec) == "Vector3" then
                    return recoilVec * (Config.RecoilScale / 100)
                end
                return recoilVec
            end
        end
    end
end)

-- ดึงข้อมูลความเร็วกระสุนและแรงโน้มถ่วงของปืนที่ผู้เล่นกำลังถืออยู่
local function GetCurrentWeaponBallistics()
    local defaultSpeed = 750 -- ความเร็วกระสุนมาตรฐานของปืนในเกม
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
        local char = LocalPlayer.Character
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

    -- เช็กว่าใส่ลูกกระสุน HV (High Velocity) ที่เพิ่มความเร็ว 1.5 เท่าอยู่หรือไม่
    if slotObj and GameAmmoTypes and type(GameAmmoTypes.Loaded) == "function" then
        local ok, loadedAmmo = pcall(GameAmmoTypes.Loaded, slotObj)
        if ok and loadedAmmo and GameItemData[loadedAmmo] and GameItemData[loadedAmmo].VelocityMultiplier then
            speed = speed * GameItemData[loadedAmmo].VelocityMultiplier
        end
    end

    return speed, grav
end

-- ==============================================================================
-- [2] REAL-TIME VELOCITY TRACKER (คำนวณความเร็วการวิ่งของทุกคนแม่นยำสูง)
-- ==============================================================================
local VelocityTracker = {} -- [model] = { LastPos = Vector3, SmoothedVel = Vector3, LastTime = clock }

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

        -- ผสมค่าความเร็วจากการเคลื่อนที่จริง (Delta) กับความเร็วฟิสิกส์ (AssemblyLinearVelocity)
        local measuredVel = deltaVel
        if engineVel.Magnitude > 1 and deltaVel.Magnitude > 1 then
            measuredVel = (deltaVel * 0.65) + (engineVel * 0.35)
        elseif engineVel.Magnitude > deltaVel.Magnitude then
            measuredVel = engineVel
        end

        -- กรองกรณีวาร์ปหรือค่ากระโดดผิดปกติเกินจริง
        if measuredVel.Magnitude > 180 then
            measuredVel = engineVel
        end

        -- ทำ Smoothing ด้วย Exponential Moving Average เพื่อให้เป้าดักหน้าสมูทไม่สั่น
        record.SmoothedVel = record.SmoothedVel:Lerp(measuredVel, math.clamp(dt * 18, 0.15, 0.85))
        record.LastPos = currentPos
        record.LastTime = now
    end

    return record.SmoothedVel
end

-- คำนวณจุดเล็งดักหน้าตามความเร็ววิ่ง + ความเร็วกระสุน + แรงโน้มถ่วง
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

    -- คำนวณเวลาที่กระสุนใช้เดินทางไปถึงเป้าหมายแบบ 2 ขั้น (Iterative Time-of-Flight)
    local timeToHit = distance / bulletSpeed
    local futurePos1 = basePos + Vector3.new(velocity.X, velocity.Y * 0.35, velocity.Z) * timeToHit
    timeToHit = (futurePos1 - camPos).Magnitude / bulletSpeed

    -- คำนวณตำแหน่งดักหน้า
    local horizontalLead = Vector3.new(velocity.X, 0, velocity.Z) * (timeToHit * Config.PredictionMultiplier)
    local verticalLead = Vector3.new(0, velocity.Y * 0.30 * timeToHit * Config.PredictionMultiplier, 0)

    -- คำนวณชดเชยกระสุนตก (Bullet Drop)
    local dropOffset = Vector3.zero
    if Config.BulletDropCompensation and distance > 25 then
        local dropY = 0.5 * bulletGravity * (timeToHit ^ 2)
        dropOffset = Vector3.new(0, math.clamp(dropY, 0, 25), 0)
    end

    return basePos + horizontalLead + verticalLead + dropOffset
end

-- ==============================================================================
-- [3] SOLID-HIT WALLCHECK & TEAM CHECK (แก้ปัญหาติดพาร์ทล่องหนและบั๊กทีม)
-- ==============================================================================
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

-- ยิง Raycast ทะลุพาร์ทล่องหน (Range, Viewmodel, หญ้า, พาร์ทไม่มีการชน) ตามลอจิก BuildingSockets.SolidHit
local function IsTargetVisible(targetPart, targetModel)
    if not Config.WallCheck then return true end
    if not targetPart then return false end

    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local filterList = { LocalPlayer.Character, Camera }

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    for _ = 1, 10 do
        rayParams.FilterDescendantsInstances = filterList
        local result = workspace:Raycast(origin, direction, rayParams)

        if not result then
            return true
        end

        local hitPart = result.Instance
        if targetModel and hitPart:IsDescendantOf(targetModel) then
            return true
        end

        -- ข้ามพาร์ทโปร่งใส พาร์ทที่ไม่มีการชน หรือโซน Range ของตู้ TC
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

-- ==============================================================================
-- [4] AUTO-HIT ORE SPARK & RAYCAST REDIRECT (AIMBOT + SPARK)
-- ==============================================================================
local CurrentLockedModel = nil
local CurrentLockedPart = nil
local CurrentPredictedPos = nil

local MiningTools = {
    ["Rock"] = true,
    ["Stone Pickaxe"] = true,
    ["Metal Pickaxe"] = true,
    ["Jackhammer"] = true,
}

local function IsHoldingMiningTool()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, child in ipairs(char:GetChildren()) do
        if MiningTools[child.Name] then return true end
    end
    local viewmodel = Camera:FindFirstChild("Viewmodel")
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
    local char = LocalPlayer.Character
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

-- ดักจับ CenterScreenRaycast เพื่อส่งทั้งจุดเล็งดักหน้าของ Aimbot และจุด Spark ของแร่
local function HookRaycastModule(modInstance)
    pcall(function()
        if not modInstance or not modInstance:IsA("ModuleScript") then return end
        local RayMod = require(modInstance)
        if type(RayMod) ~= "table" or RayMod._V6Hooked then return end
        RayMod._V6Hooked = true

        if type(RayMod.GetPosition) == "function" then
            local oldGetPos = RayMod.GetPosition
            RayMod.GetPosition = function(dist, filter, ...)
                if Config.AimlockEnabled and CurrentPredictedPos and not IsHoldingMiningTool() then
                    return CurrentPredictedPos
                end
                if Config.AutoSparkEnabled and IsHoldingMiningTool() then
                    local sparkPart = GetNearestOreSpark(Config.SparkRange)
                    if sparkPart then return sparkPart.Position end
                end
                return oldGetPos(dist, filter, ...)
            end
        end

        if type(RayMod.GetInstance) == "function" then
            local oldGetInst = RayMod.GetInstance
            RayMod.GetInstance = function(dist, filter, ...)
                if Config.AimlockEnabled and CurrentLockedPart and not IsHoldingMiningTool() then
                    return CurrentLockedPart
                end
                if Config.AutoSparkEnabled and IsHoldingMiningTool() then
                    local sparkPart = GetNearestOreSpark(Config.SparkRange)
                    if sparkPart then return sparkPart end
                end
                return oldGetInst(dist, filter, ...)
            end
        end
    end)
end

HookRaycastModule(ReplicatedStorage:FindFirstChild("CenterScreenRaycast"))
if ReplicatedStorage:FindFirstChild("Deployables") and ReplicatedStorage.Deployables:FindFirstChild("Modules") then
    HookRaycastModule(ReplicatedStorage.Deployables.Modules:FindFirstChild("CenterScreenRaycast"))
end

-- ==============================================================================
-- [5] UI OVERLAY (FOV CIRCLE, TARGET LINE, PREDICTION DOT & ESP)
-- ==============================================================================
local SafeGuiParent = (gethui and gethui()) or CoreGui
local OldOverlay = SafeGuiParent:FindFirstChild("RustSafeOverlay")
if OldOverlay then OldOverlay:Destroy() end

local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "RustSafeOverlay"
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.Parent = SafeGuiParent

-- วงกลม FOV
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
FOVStroke.Parent = OverlayGui

-- จุดชี้ตำแหน่งเล็งดักหน้า (Prediction Dot)
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

-- เส้นเชื่อมจากกลางจอไปยังจุดดักหน้า (Target Lock Line)
local TargetLine = Instance.new("Frame")
TargetLine.Name = "TargetLine"
TargetLine.AnchorPoint = Vector2.new(0.5, 0.5)
TargetLine.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
TargetLine.BorderSizePixel = 0
TargetLine.Visible = false
TargetLine.Parent = OverlayGui

-- ป้ายชี้จุด Spark ของก้อนแร่
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
-- [6] AIMBOT TARGET SELECTION & BINDTORENDERSTEP LOCK ENGINE
-- ==============================================================================
local CachedScientists = {}

local function GetAimbotTargetPart(character)
    if not character then return nil end
    return character:FindFirstChild(Config.TargetPartName)
        or character:FindFirstChild("Head")
        or character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
end

local function FindBestTargetInFOV()
    local screenCenter = Camera.ViewportSize / 2
    local bestPart = nil
    local bestModel = nil
    local shortestDist = Config.FOVRadius

    -- 1. เช็กผู้เล่นออนไลน์ทุกคน
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not IsTeammate(player) then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local part = GetAimbotTargetPart(char)

            if hum and hum.Health > 0 and part then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and screenPos.Z > 0 then
                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if dist2D <= shortestDist and IsTargetVisible(part, char) then
                        shortestDist = dist2D
                        bestPart = part
                        bestModel = char
                    end
                end
            end
        end
    end

    -- 2. เช็กบอทนักวิทยาศาสตร์ (ถ้าเปิดใช้งาน LockScientists)
    if Config.LockScientists then
        for _, botModel in ipairs(CachedScientists) do
            if botModel and botModel.Parent then
                local hum = botModel:FindFirstChildOfClass("Humanoid")
                local part = GetAimbotTargetPart(botModel)
                if hum and hum.Health > 0 and part then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen and screenPos.Z > 0 then
                        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if dist2D <= shortestDist and IsTargetVisible(part, botModel) then
                            shortestDist = dist2D
                            bestPart = part
                            bestModel = botModel
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestModel
end

local IsMobileAttacking = false
local IsMobileAiming = false
pcall(function()
    local mobileGui = LocalPlayer:WaitForChild("PlayerGui", 5):WaitForChild("MobileControls", 5)
    local frame = mobileGui and mobileGui:WaitForChild("Frame", 5)
    if frame then
        local attackBtn = frame:FindFirstChild("Attack")
        if attackBtn then
            attackBtn.MouseButton1Down:Connect(function() IsMobileAttacking = true end)
            attackBtn.MouseButton1Up:Connect(function() IsMobileAttacking = false end)
        end
        local aimBtn = frame:FindFirstChild("Aim")
        if aimBtn and aimBtn:FindFirstChild("Toggle") then
            aimBtn.Toggle.Changed:Connect(function(val) IsMobileAiming = val end)
        end
    end
end)

local function IsAimKeyActive()
    if Config.AimActivationMode == "Always" then
        return true
    end
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        or IsMobileAttacking
        or IsMobileAiming
end

-- ยกเลิก Bind เก่า (ถ้ารันซ้ำ) แล้วผูก RenderStep ที่ลำดับสุดท้ายหลังสคริปต์กล้องของเกม!
pcall(function() RunService:UnbindFromRenderStep("RustV6AimbotEngine") end)

RunService:BindToRenderStep("RustV6AimbotEngine", Enum.RenderPriority.Last.Value + 1, function()
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local screenCenter = Camera.ViewportSize / 2
    FOVCircleFrame.Position = UDim2.fromOffset(screenCenter.X, screenCenter.Y)
    FOVCircleFrame.Size = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2)
    FOVCircleFrame.Visible = Config.ShowFOV

    -- 1. ระบบช่วยตีแร่โดนจุด Spark
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
            if Config.AutoSparkCameraAssist and isAttacking and IsHoldingMiningTool() then
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, sparkPart.Position), 0.55)
            end
        else
            SparkMarker.Visible = false
        end
    else
        SparkMarker.Visible = false
    end

    -- 2. ระบบ Aimbot ล็อคหัว + ดักทางวิ่ง
    if not Config.AimlockEnabled then
        CurrentLockedPart = nil
        CurrentLockedModel = nil
        CurrentPredictedPos = nil
        PredictionDot.Visible = false
        TargetLine.Visible = false
        FOVStroke.Color = Color3.fromRGB(255, 255, 255)
        return
    end

    -- ตรวจสอบว่าเป้าหมายที่ล็อคอยู่ยังมีชีวิตและอยู่ในวง FOV หรือไม่
    if CurrentLockedPart and CurrentLockedPart.Parent and CurrentLockedModel and CurrentLockedModel.Parent then
        local hum = CurrentLockedModel:FindFirstChildOfClass("Humanoid")
        local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentLockedPart.Position)
        local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude

        if not hum or hum.Health <= 0 or not onScreen or dist2D > (Config.FOVRadius * 1.15) or not IsTargetVisible(CurrentLockedPart, CurrentLockedModel) then
            CurrentLockedPart = nil
            CurrentLockedModel = nil
            CurrentPredictedPos = nil
        end
    else
        CurrentLockedPart = nil
        CurrentLockedModel = nil
        CurrentPredictedPos = nil
    end

    -- ค้นหาเป้าหมายใหม่ในวง FOV
    if not CurrentLockedPart then
        CurrentLockedPart, CurrentLockedModel = FindBestTargetInFOV()
    end

    if CurrentLockedPart and CurrentLockedModel then
        FOVStroke.Color = Color3.fromRGB(255, 75, 75) -- เปลี่ยนสีวง FOV เป็นสีแดงเมื่อจับเป้าหมายได้
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

        if IsAimKeyActive() then
            local mouseDelta = UserInputService:GetMouseDelta()
            local deltaMag = mouseDelta.Magnitude
            local effectiveSmooth = Config.AimSmoothness

            -- เร่งความไวในการเกาะเป้าอัตโนมัติเมื่อเป้าหมายกำลังวิ่งเร็ว
            local targetVel = GetTargetVelocity(CurrentLockedModel, CurrentLockedModel:FindFirstChild("HumanoidRootPart") or CurrentLockedPart)
            if targetVel.Magnitude > 8 then
                effectiveSmooth = math.clamp(effectiveSmooth * 1.35, 0.1, 0.95)
            end

            -- ระบบ Breakaway: หากผู้เล่นสะบัดเมาส์สวนทางออกจากเป้าหมายแรงๆ ให้คลายล็อคทันที
            local isBreakingAway = false
            if deltaMag >= Config.BreakawayThreshold and predOnScreen then
                local toTarget = Vector2.new(predScreen.X, predScreen.Y) - screenCenter
                if toTarget.Magnitude > 2 and mouseDelta.Unit:Dot(toTarget.Unit) < -0.1 then
                    isBreakingAway = true
                end
            end

            if not isBreakingAway then
                -- หมุนกล้องไปยังจุดเล็งดักหน้าโดยตรง (ทำงานหลังสคริปต์กล้องของเกม)
                local goalCFrame = CFrame.lookAt(Camera.CFrame.Position, CurrentPredictedPos)
                Camera.CFrame = Camera.CFrame:Lerp(goalCFrame, effectiveSmooth)

                -- หากใช้บน PC และมีฟังก์ชัน mousemoverel จะช่วยอัปเดตแกนเมาส์ภายในของเกมด้วยเพื่อให้มุมกล้องไม่ดีดกลับ
                if mousemoverel and predOnScreen and (Config.AimMode == "MouseMove + Raycast" or Config.AimMode == "Camera + Raycast") then
                    local offsetX = (predScreen.X - screenCenter.X) * (effectiveSmooth * 0.45)
                    local offsetY = (predScreen.Y - screenCenter.Y) * (effectiveSmooth * 0.45)
                    if math.abs(offsetX) >= 1 or math.abs(offsetY) >= 1 then
                        pcall(mousemoverel, offsetX, offsetY)
                    end
                end
            end
        end
    else
        FOVStroke.Color = Color3.fromRGB(255, 255, 255)
        PredictionDot.Visible = false
        TargetLine.Visible = false
    end
end)

-- ==============================================================================
-- [7] HELPER FUNCTIONS FOR ESP & BACKGROUND SCANNER
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

    UserIdNameCache[numId] = "ID:" .. tostring(numId)
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
        if p.Character == model then return true end
    end
    return false
end

local function GetSleeperInfo(obj)
    if typeof(obj) ~= "Instance" or not obj:IsA("Model") then return false, nil end
    if obj == LocalPlayer.Character or obj.Name == "Viewmodel" then return false, nil end

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
    if obj == LocalPlayer.Character or obj.Name == "Viewmodel" or obj.Name == "StarterCharacter" then return false, nil end
    if IsActiveOnlineCharacter(obj) then return false, nil end

    local hum = obj:FindFirstChildOfClass("Humanoid")
    local root = obj:FindFirstChild("HumanoidRootPart")
    local head = obj:FindFirstChild("Head")

    if hum and hum.Health > 0 and root and head then
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
    while true do
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
                if obj:IsA("Model") and obj ~= LocalPlayer.Character and obj.Name ~= "Viewmodel" then
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
                                local hum = obj:FindFirstChildOfClass("Humanoid")
                                if part and hum then
                                    table.insert(newTracked, {
                                        Key = obj, Part = part, Category = "Scientist",
                                        Title = string.format("[BOT: %s] [%d HP]", tostring(sciName), math.floor(hum.Health)),
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
                                    local hum = desc:FindFirstChildOfClass("Humanoid")
                                    if part and hum then
                                        table.insert(newTracked, {
                                            Key = desc, Part = part, Category = "Scientist",
                                            Title = string.format("[BOT: %s] [%d HP]", tostring(sciName), math.floor(hum.Health)),
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
-- [8] ESP RENDERER
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

RunService.RenderStepped:Connect(function()
    local activeKeys = {}
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local refPos = (myRoot and myRoot.Position) or Camera.CFrame.Position

    -- อัปเดตความเร็วของผู้เล่นทุกคนในเซิร์ฟเวอร์ทุกเฟรมเพื่อให้ Prediction แม่นยำสูงสุด
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local char = player.Character
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                GetTargetVelocity(char, root)
            end
        end
    end

    if Config.ESP_Players then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local char = player.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                local hum = char:FindFirstChildOfClass("Humanoid")

                if root and head and hum and hum.Health > 0 then
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
                                math.floor(hum.Health),
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
end)

-- ==============================================================================
-- [9] FLUENT UI SETUP + MOBILE FLOATING BUTTON
-- ==============================================================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Rust Survival Hub V6",
    SubTitle = "True Ballistics Aimbot + No Recoil + Auto Spark + Full ESP",
    TabWidth = 155,
    Size = UDim2.fromOffset(600, 470),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Aimbot & ลดแรงดีด", Icon = "crosshair" }),
    PlayerBaseESP = Window:AddTab({ Title = "ESP คน / บอท / บ้าน", Icon = "users" }),
    ResourceESP = Window:AddTab({ Title = "ESP แร่ & ตี Spark", Icon = "pickaxe" }),
    LootESP = Window:AddTab({ Title = "ESP ของตก & กล่อง", Icon = "box" }),
}

-- ------------------------------------------------------------------------------
-- TAB 1: AIMBOT & NO RECOIL
-- ------------------------------------------------------------------------------
local AimToggle = Tabs.Combat:AddToggle("AimToggle", {
    Title = "เปิดใช้งาน Aimbot ล็อคหัวแม่นยำสูง (Master Switch)",
    Description = "ล็อคหัวอัตโนมัติพร้อมคำนวณความเร็ววิ่งและวิถีกระสุนจริง",
    Default = false
})
AimToggle:OnChanged(function() Config.AimlockEnabled = AimToggle.Value end)

local AimActDropdown = Tabs.Combat:AddDropdown("AimActDropdown", {
    Title = "เงื่อนไขการทำงานของ Aimbot",
    Values = { "Always", "HoldClick" },
    Default = "Always",
})
AimActDropdown:OnChanged(function(val) Config.AimActivationMode = val end)

local PredictToggle = Tabs.Combat:AddToggle("PredictToggle", {
    Title = "คำนวณดักหน้าคนวิ่งตามความเร็วกระสุนจริง (True Ballistics Lead)",
    Default = true
})
PredictToggle:OnChanged(function() Config.UsePrediction = PredictToggle.Value end)

local DropCompToggle = Tabs.Combat:AddToggle("DropCompToggle", {
    Title = "ชดเชยวิถีกระสุนตกตามแรงโน้มถ่วง (Bullet Drop Compensation)",
    Default = true
})
DropCompToggle:OnChanged(function() Config.BulletDropCompensation = DropCompToggle.Value end)

local LockBotToggle = Tabs.Combat:AddToggle("LockBotToggle", {
    Title = "ล็อคหัวบอทนักวิทยาศาสตร์ด้วย (Lock Scientists)",
    Default = true
})
LockBotToggle:OnChanged(function() Config.LockScientists = LockBotToggle.Value end)

local NoRecoilToggle = Tabs.Combat:AddToggle("NoRecoilToggle", {
    Title = "เปิดใช้งานลดแรงดีดปืน (No Recoil)",
    Default = false
})
NoRecoilToggle:OnChanged(function() Config.NoRecoilEnabled = NoRecoilToggle.Value end)

Tabs.Combat:AddSlider("RecoilScaleSlider", {
    Title = "เปอร์เซ็นต์แรงดีดปืน (Recoil Percentage %)",
    Default = 0,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Callback = function(val) Config.RecoilScale = val end
})

local FOVToggle = Tabs.Combat:AddToggle("FOVToggle", {
    Title = "แสดงวงกลมระยะล็อค (FOV Circle)",
    Default = true
})
FOVToggle:OnChanged(function() Config.ShowFOV = FOVToggle.Value end)

local LineToggle = Tabs.Combat:AddToggle("LineToggle", {
    Title = "แสดงเส้นชี้เป้าและจุดเขียวดักหน้า (Target Line & Prediction Dot)",
    Default = true
})
LineToggle:OnChanged(function() Config.ShowTargetLine = LineToggle.Value end)

Tabs.Combat:AddSlider("FOVRadiusSlider", {
    Title = "ขนาดวงกลม FOV (px)",
    Default = 150,
    Min = 50,
    Max = 400,
    Rounding = 0,
    Callback = function(val) Config.FOVRadius = val end
})

Tabs.Combat:AddSlider("SmoothnessSlider", {
    Title = "ความไวในการดูดเป้า (Aim Speed / Lock Strength)",
    Description = "0.45 = เกาะติดคนวิ่งไวมาก | 0.85 = ล็อคติดหัวทันที",
    Default = 0.45,
    Min = 0.10,
    Max = 0.95,
    Rounding = 2,
    Callback = function(val) Config.AimSmoothness = val end
})

Tabs.Combat:AddSlider("PredictionMultSlider", {
    Title = "ตัวคูณระยะดักหน้าคนวิ่ง (Prediction Multiplier)",
    Description = "1.05 = ดักหน้าตามความเร็วกระสุนจริง (เพิ่มได้หากปิงสูง)",
    Default = 1.05,
    Min = 0.50,
    Max = 2.00,
    Rounding = 2,
    Callback = function(val) Config.PredictionMultiplier = val end
})

local WallCheckToggle = Tabs.Combat:AddToggle("WallCheckToggle", {
    Title = "เช็กกำแพงกั้น (SolidHit WallCheck)",
    Default = false
})
WallCheckToggle:OnChanged(function() Config.WallCheck = WallCheckToggle.Value end)

local TeamCheckToggle = Tabs.Combat:AddToggle("TeamCheckToggle", {
    Title = "ข้ามเพื่อนในปาร์ตี้ (TeamUI Check)",
    Default = false
})
TeamCheckToggle:OnChanged(function() Config.TeamCheck = TeamCheckToggle.Value end)

-- ------------------------------------------------------------------------------
-- TAB 2: ESP ผู้เล่น, บอทนักวิทยาศาสตร์ & เจ้าของบ้าน
-- ------------------------------------------------------------------------------
local T_Players = Tabs.PlayerBaseESP:AddToggle("T_Players", {
    Title = "ESP ผู้เล่นออนไลน์ (ชื่อ + เลือด + ปืนที่ถือ)",
    Default = false
})
T_Players:OnChanged(function() Config.ESP_Players = T_Players.Value end)

local T_Scientists = Tabs.PlayerBaseESP:AddToggle("T_Scientists", {
    Title = "ESP บอทนักวิทยาศาสตร์ (Road / Monument Scientist)",
    Default = false
})
T_Scientists:OnChanged(function() Config.ESP_Scientists = T_Scientists.Value end)

local T_Sleepers = Tabs.PlayerBaseESP:AddToggle("T_Sleepers", {
    Title = "ESP คนนอนออฟไลน์ (Sleeper)",
    Default = false
})
T_Sleepers:OnChanged(function() Config.ESP_Sleepers = T_Sleepers.Value end)

local T_BodyBags = Tabs.PlayerBaseESP:AddToggle("T_BodyBags", {
    Title = "ESP ถุงศพคนตาย (BodyBag)",
    Default = false
})
T_BodyBags:OnChanged(function() Config.ESP_BodyBags = T_BodyBags.Value end)

local T_BaseOwner = Tabs.PlayerBaseESP:AddToggle("T_BaseOwner", {
    Title = "ESP ดูชื่อเจ้าของบ้าน (สแกนตู้ TC & เตียงนอน)",
    Default = false
})
T_BaseOwner:OnChanged(function() Config.ESP_BaseOwner = T_BaseOwner.Value end)

local T_Traps = Tabs.PlayerBaseESP:AddToggle("T_Traps", {
    Title = "ESP กับดักในบ้าน (Shotgun Trap / Flame Turret)",
    Default = false
})
T_Traps:OnChanged(function() Config.ESP_Traps = T_Traps.Value end)

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
local AutoSparkToggle = Tabs.ResourceESP:AddToggle("AutoSparkToggle", {
    Title = "ตีแร่โดนจุด Spark อัตโนมัติ (Auto-Hit Ore Spark)",
    Default = false
})
AutoSparkToggle:OnChanged(function() Config.AutoSparkEnabled = AutoSparkToggle.Value end)

local SparkCamToggle = Tabs.ResourceESP:AddToggle("SparkCamToggle", {
    Title = "ช่วยหันกล้องเข้าจุด Spark ตอนกดขุด (Camera Assist)",
    Default = true
})
SparkCamToggle:OnChanged(function() Config.AutoSparkCameraAssist = SparkCamToggle.Value end)

local T_Stone = Tabs.ResourceESP:AddToggle("T_Stone", {
    Title = "ESP แร่หิน (Stone Ore)",
    Default = false
})
T_Stone:OnChanged(function() Config.ESP_StoneOre = T_Stone.Value end)

local T_Metal = Tabs.ResourceESP:AddToggle("T_Metal", {
    Title = "ESP แร่เหล็ก (Metal Ore)",
    Default = false
})
T_Metal:OnChanged(function() Config.ESP_MetalOre = T_Metal.Value end)

local T_Sulfur = Tabs.ResourceESP:AddToggle("T_Sulfur", {
    Title = "ESP แร่กำมะถัน (Sulfur Ore)",
    Default = false
})
T_Sulfur:OnChanged(function() Config.ESP_SulfurOre = T_Sulfur.Value end)

local T_Cloth = Tabs.ResourceESP:AddToggle("T_Cloth", {
    Title = "ESP ผ้า & ของป่า (Cloth / Hemp / Mushrooms)",
    Default = false
})
T_Cloth:OnChanged(function() Config.ESP_ClothAndFood = T_Cloth.Value end)

-- ------------------------------------------------------------------------------
-- TAB 4: ESP กล่องเก็บของ & ของตกพื้น
-- ------------------------------------------------------------------------------
local T_Storage = Tabs.LootESP:AddToggle("T_Storage", {
    Title = "ESP กล่องเก็บของ & เตาเผา (Crate / Furnace / Stash)",
    Default = false
})
T_Storage:OnChanged(function() Config.ESP_Storage = T_Storage.Value end)

local T_UnlockedOnly = Tabs.LootESP:AddToggle("T_UnlockedOnly", {
    Title = "กรองเฉพาะกล่องที่ไม่ได้ล็อก (Unlocked Only)",
    Default = false
})
T_UnlockedOnly:OnChanged(function() Config.ESP_OnlyUnlockedStorage = T_UnlockedOnly.Value end)

local T_Dropped = Tabs.LootESP:AddToggle("T_Dropped", {
    Title = "ESP ของและอาวุธที่ดรอปบนพื้น (Dropped Items)",
    Default = false
})
T_Dropped:OnChanged(function() Config.ESP_DroppedItems = T_Dropped.Value end)

local T_WorldCrates = Tabs.LootESP:AddToggle("T_WorldCrates", {
    Title = "ESP กล่องฟาร์มตามแมพ & แอร์ดรอป (Military / Locked Crate / Barrel)",
    Default = false
})
T_WorldCrates:OnChanged(function() Config.ESP_WorldCrates = T_WorldCrates.Value end)

Tabs.LootESP:AddSlider("WorldDistSlider", {
    Title = "ระยะมองเห็นแร่และสิ่งของสูงสุด (Studs)",
    Default = 600,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(val) Config.WorldRenderDistance = val end
})

-- ปุ่มลอยสำหรับเปิด/ปิด UI บนมือถือ
local MobileToggleBtn = Instance.new("TextButton")
MobileToggleBtn.Name = "MobileToggleUI"
MobileToggleBtn.Size = UDim2.fromOffset(52, 52)
MobileToggleBtn.Position = UDim2.new(0, 16, 0.5, -26)
MobileToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
MobileToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MobileToggleBtn.Font = Enum.Font.GothamBold
MobileToggleBtn.TextSize = 12
MobileToggleBtn.Text = "HUB"
MobileToggleBtn.Draggable = true
MobileToggleBtn.Active = true
MobileToggleBtn.Parent = OverlayGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 12)
BtnCorner.Parent = MobileToggleBtn

MobileToggleBtn.MouseButton1Click:Connect(function()
    Window:Minimize()
end)

Window:SelectTab(1)
