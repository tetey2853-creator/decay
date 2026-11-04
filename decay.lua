-- ==============================================================================
-- Rust Roblox Script V3 (Smooth Physics Flight, Anti-Rubberband & No Walk Bug)
-- Supports: PC & Mobile | Anti-Cheat Bypass Included
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
-- [GLOBAL CONFIG & STATE]
-- ==============================================================================
local Config = {
    -- ระบบที่ 1: Smooth Travel
    TravelSpeed = 28, -- ความเร็วเสถียรที่ไม่โดนเซิร์ฟเวอร์ดึงกลับ (แนะนำ 22 - 35)
    StopDistance = 2.5, -- ระยะหยุดหน้าเป้าหมาย
    HoldPositionOnArrive = false, -- ปิดการล็อกตัวค้างหลังถึงที่หมายเพื่อให้เดินต่อได้ทันที
    ManualNoclip = false, -- เปิดทะลุกำแพงเองเมื่อต้องการเดินเข้าบ้าน
    IsTravelling = false,
    IsHovering = false,
    SavedPosition = nil,
    SelectedTargetName = nil,
    ScannedTargets = {},

    -- ระบบที่ 2: Soft Aimlock
    AimlockEnabled = false,
    ShowFOV = false,
    FOVRadius = 120,
    AimSmoothness = 0.14,
    BreakawayThreshold = 4.5,
    WallCheck = true,
    TeamCheck = true,

    -- ระบบที่ 3: ESP
    PlayerESPEnabled = false,
    SleeperESPEnabled = false,
    CrateESPEnabled = false,
    MaxRenderDistance = 1000,
}

-- เก็บค่า CanCollide เดิมของตัวละครเพื่อคืนค่าไม่ให้เดินติดบั๊ก
local OriginalCharCollision = {}
local ActiveBV = nil
local ActiveBG = nil

local function RecordCharacterCollision(char)
    OriginalCharCollision = {}
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            OriginalCharCollision[part] = part.CanCollide
        end
    end
end

local function RestoreCharacterPhysics()
    if ActiveBV then ActiveBV:Destroy() ActiveBV = nil end
    if ActiveBG then ActiveBG:Destroy() ActiveBG = nil end

    local char = LocalPlayer.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    if hum then
        hum.PlatformStand = false
    end

    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- คืนค่าการชนเดิมของชิ้นส่วนในตัวละครทั้งหมด
    for part, canCollide in pairs(OriginalCharCollision) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    RecordCharacterCollision(char)
end)
if LocalPlayer.Character then
    RecordCharacterCollision(LocalPlayer.Character)
end

-- ==============================================================================
-- [HELPER FUNCTIONS & SMART SLEEPER DETECTOR]
-- ==============================================================================

-- 1. เช็กสถานะล็อกตามลอจิก ReplicatedStorage.LockAccess
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

-- 2. เช็กว่าโมเดลนั้นเป็นตัวละครของผู้เล่นที่กำลังออนไลน์อยู่หรือไม่
local function IsActiveOnlineCharacter(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then
            return true
        end
    end
    return false
end

-- 3. ตรวจจับ Sleeper พร้อมดึงชื่อจาก Head.NameUI.NameLabel
local function GetSleeperInfo(obj)
    if typeof(obj) ~= "Instance" or not obj:IsA("Model") then return false, nil end
    if obj == LocalPlayer.Character or obj.Name == "Viewmodel" then return false, nil end

    local head = obj:FindFirstChild("Head")
    local nameUI = head and head:FindFirstChild("NameUI")
    local nameLabel = nameUI and nameUI:FindFirstChild("NameLabel")
    local sleeperPlayerName = (nameLabel and nameLabel.Text ~= "" and nameLabel.Text) or obj.Name

    if obj.Name == "Sleeper" or obj:FindFirstChild("Sleeper") then
        return true, sleeperPlayerName
    end

    local hasTorso = obj:FindFirstChild("Torso") or obj:FindFirstChild("UpperTorso") or obj:FindFirstChild("HumanoidRootPart")
    if head and hasTorso and not IsActiveOnlineCharacter(obj) then
        local hum = obj:FindFirstChildOfClass("Humanoid")
        local root = obj:FindFirstChild("HumanoidRootPart") or head
        local isLyingDown = math.abs(root.CFrame.UpVector.Y) < 0.55

        if nameUI or isLyingDown or (obj.Parent and obj.Parent.Name == "Deployables") or not hum then
            return true, sleeperPlayerName
        end
    end

    return false, nil
end

-- 4. แคชรายการ Object ในแมพทุกๆ 1 วินาที เพื่อไม่ให้กระตุกเวลาเปิด ESP หรือบิน
local CachedCandidates = {}
task.spawn(function()
    while true do
        local results = {}
        local seen = {}

        local pbs = workspace:FindFirstChild("PlayerBuiltStructures")
        local deployables = pbs and pbs:FindFirstChild("Deployables")

        if deployables then
            for _, obj in ipairs(deployables:GetChildren()) do
                seen[obj] = true
                table.insert(results, obj)
            end
        end

        for _, obj in ipairs(workspace:GetChildren()) do
            if not seen[obj] and obj:IsA("Model") then
                local isSlp = GetSleeperInfo(obj)
                if isSlp or obj.Name == "BodyBag" or obj.Name == "Drop Stash" then
                    seen[obj] = true
                    table.insert(results, obj)
                end
            end
        end

        CachedCandidates = results
        task.wait(1)
    end
end)

-- 5. หา Part หลักของโมเดล
local function GetTargetPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Head")
            or model.PrimaryPart
            or model:FindFirstChild("Hitbox")
            or model:FindFirstChild("Core")
            or model:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

-- ==============================================================================
-- [SYSTEM 1: SMOOTH PHYSICS FLIGHT (แก้ปัญหาดึงกลับและแก้เดินติดบั๊ก)]
-- ==============================================================================
local ValidContainers = {
    ["Wooden Crate"] = true,
    ["Furnace"] = true,
    ["Large Furnace"] = true,
    ["Drop Stash"] = true,
}

local function StopSafeTravel()
    Config.IsTravelling = false
    Config.IsHovering = false
    if not Config.ManualNoclip then
        RestoreCharacterPhysics()
    else
        if ActiveBV then ActiveBV:Destroy() ActiveBV = nil end
        if ActiveBG then ActiveBG:Destroy() ActiveBG = nil end
    end
end

local function StartSafeTravel(targetPartOrPos, isReturning)
    local char = LocalPlayer.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not rootPart or not hum then return end

    if next(OriginalCharCollision) == nil then
        RecordCharacterCollision(char)
    end

    if not isReturning and not Config.SavedPosition then
        Config.SavedPosition = rootPart.CFrame
    end

    -- ลบตัวเก่าก่อนสร้างใหม่
    if ActiveBV then ActiveBV:Destroy() end
    if ActiveBG then ActiveBG:Destroy() end

    -- ใช้ BodyVelocity และ BodyGyro เพื่อเคลื่อนที่ด้วยฟิสิกส์จริง (เซิร์ฟเวอร์ไม่ดีดกลับ)
    ActiveBV = Instance.new("BodyVelocity")
    ActiveBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    ActiveBV.Velocity = Vector3.zero
    ActiveBV.Parent = rootPart

    ActiveBG = Instance.new("BodyGyro")
    ActiveBG.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    ActiveBG.P = 1e4
    ActiveBG.D = 500
    ActiveBG.CFrame = rootPart.CFrame
    ActiveBG.Parent = rootPart

    Config.IsTravelling = true
    Config.IsHovering = false

    task.spawn(function()
        while Config.IsTravelling and rootPart and rootPart.Parent and hum and hum.Health > 0 do
            RunService.Heartbeat:Wait()

            local rawTargetPos = typeof(targetPartOrPos) == "Instance" and targetPartOrPos.Position or targetPartOrPos
            -- ยกระดับเป้าหมายขึ้นเล็กน้อย (1.5 Studs) เพื่อไม่ให้ตัวละครมุดดินตอนบินไปถึง
            local destPos = isReturning and rawTargetPos or (rawTargetPos + Vector3.new(0, 1.5, 0))
            local diff = destPos - rootPart.Position
            local distance = diff.Magnitude

            local stopThreshold = isReturning and 1.5 or Config.StopDistance

            if distance <= stopThreshold then
                Config.IsTravelling = false

                if isReturning then
                    Config.SavedPosition = nil
                    StopSafeTravel()
                elseif Config.HoldPositionOnArrive then
                    -- ลอยตัวนิ่งๆ ด้วย BodyVelocity = 0 จนกว่าผู้เล่นจะกดเดินเอง
                    Config.IsHovering = true
                    if ActiveBV then ActiveBV.Velocity = Vector3.zero end
                else
                    -- ปลดล็อกฟิสิกส์ทันทีเมื่อถึงที่หมาย เพื่อให้เดินได้ปกติไม่ติดบั๊ก
                    StopSafeTravel()
                end
                break
            else
                -- ชะลอความเร็วลงอย่างนุ่มนวลเมื่อเข้าใกล้เป้าหมายในระยะ 6 Studs สุดท้าย
                local currentSpeed = Config.TravelSpeed
                if distance < 6 then
                    currentSpeed = math.max(8, Config.TravelSpeed * (distance / 6))
                end

                if ActiveBV then
                    ActiveBV.Velocity = diff.Unit * currentSpeed
                end
                if ActiveBG then
                    ActiveBG.CFrame = CFrame.lookAt(rootPart.Position, Vector3.new(destPos.X, rootPart.Position.Y, destPos.Z))
                end
            end
        end
    end)
end

-- จัดการ Noclip เฉพาะตัวละคร และปลดล็อกอัตโนมัติเมื่อผู้เล่นกดเดิน
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end

    local hum = char:FindFirstChildOfClass("Humanoid")

    -- ถ้าอยู่ในโหมดลอยตัวค้าง (Hover) แล้วผู้เล่นขยับปุ่มเดิน ให้ปลดล็อกทันทีเพื่อเดินต่อได้เลย
    if Config.IsHovering and hum and hum.MoveDirection.Magnitude > 0.05 then
        StopSafeTravel()
        return
    end

    if Config.IsTravelling or Config.ManualNoclip then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

local function ScanAllTargets()
    Config.ScannedTargets = {}
    local dropdownList = {}
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return dropdownList end

    for _, obj in ipairs(CachedCandidates) do
        local isSleeper, sleeperName = GetSleeperInfo(obj)
        local isBag = (obj.Name == "BodyBag")
        local isContainer = ValidContainers[obj.Name]

        if isSleeper or isBag or isContainer then
            local part = GetTargetPart(obj)
            if part and not IsDeployableLocked(obj) then
                local dist = math.floor((part.Position - myRoot.Position).Magnitude)
                local displayName = isSleeper and ("Sleeper: " .. tostring(sleeperName)) or obj.Name
                local label = string.format("[%s] %d m (%d, %d, %d)", displayName, dist, math.floor(part.Position.X), math.floor(part.Position.Y), math.floor(part.Position.Z))

                Config.ScannedTargets[label] = {
                    Instance = obj,
                    Part = part,
                    Distance = dist,
                    Type = isSleeper and "Sleeper" or obj.Name
                }
                table.insert(dropdownList, label)
            end
        end
    end

    table.sort(dropdownList, function(a, b)
        return Config.ScannedTargets[a].Distance < Config.ScannedTargets[b].Distance
    end)

    return dropdownList
end

local function FindNearestTarget(filterFunc)
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, "ไม่พบตัวละครของคุณ" end

    local nearestPart = nil
    local minDist = math.huge
    local foundLocked = false

    for _, obj in ipairs(CachedCandidates) do
        if filterFunc(obj) then
            local part = GetTargetPart(obj)
            if part then
                if IsDeployableLocked(obj) then
                    foundLocked = true
                else
                    local dist = (part.Position - myRoot.Position).Magnitude
                    if dist < minDist then
                        minDist = dist
                        nearestPart = part
                    end
                end
            end
        end
    end

    if not nearestPart and foundLocked then
        return nil, "พบเป้าหมายแต่ติดล็อกทั้งหมด"
    end
    return nearestPart, nil
end

local function QuickOpenNearestContainer()
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local remFolder = ReplicatedStorage:FindFirstChild("Deployables") and ReplicatedStorage.Deployables:FindFirstChild("RemoteEvents")
    if not myRoot or not remFolder then return false end

    local bestObj = nil
    local bestDist = 14

    for _, obj in ipairs(CachedCandidates) do
        local isSleeper = GetSleeperInfo(obj)
        if isSleeper or obj.Name == "BodyBag" or ValidContainers[obj.Name] then
            local part = GetTargetPart(obj)
            if part and not IsDeployableLocked(obj) then
                local dist = (part.Position - myRoot.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestObj = obj
                end
            end
        end
    end

    if not bestObj then return false end

    local isSlp = GetSleeperInfo(bestObj)
    if isSlp and remFolder:FindFirstChild("OpenSleeper") then
        remFolder.OpenSleeper:Fire(bestObj)
        return true, "Sleeper"
    elseif bestObj.Name == "BodyBag" and remFolder:FindFirstChild("OpenBodyBag") then
        remFolder.OpenBodyBag:Fire(bestObj)
        return true, "BodyBag"
    elseif bestObj.Name == "Wooden Crate" and remFolder:FindFirstChild("OpenCrate") then
        remFolder.OpenCrate:Fire(bestObj)
        return true, "Wooden Crate"
    elseif bestObj.Name == "Furnace" and remFolder:FindFirstChild("OpenFurnace") then
        remFolder.OpenFurnace:Fire(bestObj)
        return true, "Furnace"
    elseif bestObj.Name == "Large Furnace" and remFolder:FindFirstChild("OpenLargeFurnace") then
        remFolder.OpenLargeFurnace:Fire(bestObj)
        return true, "Large Furnace"
    end
    return false
end

-- ==============================================================================
-- [TEAM CHECK & WALL CHECK FOR AIMLOCK]
-- ==============================================================================
local function IsTeammate(player)
    if not Config.TeamCheck then return false end
    if player == LocalPlayer then return true end
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then return true end

    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local teamUI = playerGui and playerGui:FindFirstChild("TeamUI")
    local teamFrame = teamUI and teamUI:FindFirstChild("Team")

    if teamFrame then
        for _, child in ipairs(teamFrame:GetChildren()) do
            if child.Name == player.Name or child.Name == player.DisplayName or child.Name == tostring(player.UserId) then
                return true
            end
            for _, desc in ipairs(child:GetDescendants()) do
                if desc:IsA("TextLabel") and (string.find(desc.Text, player.Name, 1, true) or string.find(desc.Text, player.DisplayName, 1, true)) then
                    return true
                end
            end
        end
    end
    return false
end

local function IsVisible(targetPart, targetModel)
    if not Config.WallCheck then return true end
    if not targetPart then return false end

    local origin = Camera.CFrame.Position
    local direction = targetPart.Position - origin
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.IgnoreWater = true
    raycastParams.FilterDescendantsInstances = { LocalPlayer.Character, Camera }

    local result = workspace:Raycast(origin, direction, raycastParams)
    if not result then return true end
    if targetModel and result.Instance:IsDescendantOf(targetModel) then return true end
    return false
end

local function GetHeldWeapon(character)
    if not character then return "None" end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            return child.Name
        elseif child:IsA("Model") and (child:FindFirstChild("GunComponents") or child:FindFirstChild("ToolComponents") or child:FindFirstChild("Handle")) then
            return child.Name
        end
    end
    return "Unarmed"
end

-- ==============================================================================
-- [UI OVERLAY FOR FOV CIRCLE & SAFE ESP]
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
FOVStroke.Transparency = 0.25
FOVStroke.Parent = FOVCircleFrame

-- ==============================================================================
-- [SYSTEM 2: SOFT FOV AIMLOCK WITH BREAKAWAY]
-- ==============================================================================
local CurrentAimTarget = nil

local function GetClosestTargetInFOV()
    local screenCenter = Camera.ViewportSize / 2
    local bestHead = nil
    local shortestDist = Config.FOVRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not IsTeammate(player) then
            local char = player.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local head = char and char:FindFirstChild("Head")

            if humanoid and humanoid.Health > 0 and head then
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local distFromCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                    if distFromCenter <= shortestDist and IsVisible(head, char) then
                        shortestDist = distFromCenter
                        bestHead = head
                    end
                end
            end
        end
    end
    return bestHead
end

RunService.RenderStepped:Connect(function()
    local screenCenter = Camera.ViewportSize / 2
    FOVCircleFrame.Position = UDim2.fromOffset(screenCenter.X, screenCenter.Y)
    FOVCircleFrame.Size = UDim2.fromOffset(Config.FOVRadius * 2, Config.FOVRadius * 2)
    FOVCircleFrame.Visible = Config.ShowFOV

    if not Config.AimlockEnabled then
        CurrentAimTarget = nil
        return
    end

    if CurrentAimTarget and CurrentAimTarget.Parent then
        local char = CurrentAimTarget.Parent
        local hum = char:FindFirstChildOfClass("Humanoid")
        local screenPos, onScreen = Camera:WorldToViewportPoint(CurrentAimTarget.Position)
        local distFromCenter = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude

        if not hum or hum.Health <= 0 or not onScreen or distFromCenter > Config.FOVRadius or not IsVisible(CurrentAimTarget, char) then
            CurrentAimTarget = nil
        end
    else
        CurrentAimTarget = nil
    end

    if not CurrentAimTarget then
        CurrentAimTarget = GetClosestTargetInFOV()
    end

    if CurrentAimTarget then
        local mouseDelta = UserInputService:GetMouseDelta()
        local deltaMag = mouseDelta.Magnitude
        local effectiveSmoothness = Config.AimSmoothness

        if deltaMag >= Config.BreakawayThreshold then
            local screenPos = Camera:WorldToViewportPoint(CurrentAimTarget.Position)
            local toTargetDir = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter)
            if toTargetDir.Magnitude > 1 then
                local dot = mouseDelta.Unit:Dot(toTargetDir.Unit)
                if dot < 0.2 then
                    effectiveSmoothness = math.max(0.005, Config.AimSmoothness * (1 - math.clamp(deltaMag / (Config.BreakawayThreshold * 2.5), 0, 0.95)))
                end
            end
        end

        local targetCFrame = CFrame.lookAt(Camera.CFrame.Position, CurrentAimTarget.Position)
        Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, effectiveSmoothness)
    end
end)

-- ==============================================================================
-- [SYSTEM 3: SAFE ESP (PLAYER / SMART SLEEPER / BODYBAG / CRATE)]
-- ==============================================================================
local ESPPool = {}

local function CreateESPItem(key)
    local container = Instance.new("Frame")
    container.Name = "ESP_" .. tostring(key)
    container.BackgroundTransparency = 1
    container.Visible = false
    container.Parent = OverlayGui

    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 1.5
    boxStroke.Parent = container

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0, 220, 0, 45)
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 0, -4)
    label.Font = Enum.Font.RobotoMono
    label.TextSize = 13
    label.TextStrokeTransparency = 0.2
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

    if Config.PlayerESPEnabled then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local char = player.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local head = char:FindFirstChild("Head")
                local hum = char:FindFirstChildOfClass("Humanoid")

                if root and head and hum and hum.Health > 0 then
                    local dist = (root.Position - refPos).Magnitude
                    if dist <= Config.MaxRenderDistance then
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
                                "%s [%d HP]\n[%s] (%d m)",
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

    if Config.SleeperESPEnabled or Config.CrateESPEnabled then
        for _, obj in ipairs(CachedCandidates) do
            local isSleeper, sleeperName = false, nil
            if Config.SleeperESPEnabled then
                isSleeper, sleeperName = GetSleeperInfo(obj)
            end
            local isBag = Config.SleeperESPEnabled and (obj.Name == "BodyBag")
            local isUnlockedCrate = Config.CrateESPEnabled and (obj.Name == "Wooden Crate") and not IsDeployableLocked(obj)

            if isSleeper or isBag or isUnlockedCrate then
                local part = GetTargetPart(obj)
                if part then
                    local dist = (part.Position - refPos).Magnitude
                    if dist <= Config.MaxRenderDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            activeKeys[obj] = true
                            local esp = ESPPool[obj] or CreateESPItem(obj)
                            local color, tagText

                            if isSleeper then
                                color = Color3.fromRGB(180, 110, 255)
                                tagText = string.format("[SLEEPER: %s]", tostring(sleeperName))
                            elseif isBag then
                                color = Color3.fromRGB(255, 225, 60)
                                tagText = "[BODYBAG]"
                            else
                                color = Color3.fromRGB(80, 220, 255)
                                tagText = "[UNLOCKED CRATE]"
                            end

                            esp.Frame.Size = UDim2.fromOffset(28, 28)
                            esp.Frame.Position = UDim2.fromOffset(screenPos.X - 14, screenPos.Y - 14)
                            esp.Stroke.Color = color
                            esp.Label.TextColor3 = color
                            esp.Label.Text = string.format("%s\n(%d m)", tagText, math.floor(dist))
                            esp.Frame.Visible = true
                        end
                    end
                end
            end
        end
    end

    CleanupESP(activeKeys)
end)

-- ==============================================================================
-- [FLUENT UI SETUP + MOBILE FLOATING BUTTON]
-- ==============================================================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Rust Survival Hub V3",
    SubTitle = "Smooth Flight (Anti-Rubberband) & No Walk Bug",
    TabWidth = 150,
    Size = UDim2.fromOffset(560, 440),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Travel = Window:AddTab({ Title = "Safe Travel", Icon = "navigation" }),
    Combat = Window:AddTab({ Title = "Soft Aimlock", Icon = "crosshair" }),
    Visuals = Window:AddTab({ Title = "ESP Visuals", Icon = "eye" }),
}

-- ------------------------------------------------------------------------------
-- TAB 1: SMOOTH SAFE TRAVEL
-- ------------------------------------------------------------------------------
local ManualNoclipToggle = Tabs.Travel:AddToggle("ManualNoclipToggle", {
    Title = "เดินทะลุกำแพง (Character Noclip)",
    Description = "เปิดเฉพาะตอนต้องการเดินทะลุกำแพงบ้านด้วยตัวเอง (ปิดแล้วเดินปกติ 100%)",
    Default = false
})
ManualNoclipToggle:OnChanged(function()
    Config.ManualNoclip = ManualNoclipToggle.Value
    if not Config.ManualNoclip and not Config.IsTravelling then
        RestoreCharacterPhysics()
    end
end)

local HoldArriveToggle = Tabs.Travel:AddToggle("HoldArriveToggle", {
    Title = "ลอยตัวค้างเมื่อถึงที่หมาย (Hover on Arrive)",
    Description = "ถ้าเปิดจะลอยค้างกลางอากาศ และปลดล็อกอัตโนมัติทันทีที่คุณกดเดิน",
    Default = false
})
HoldArriveToggle:OnChanged(function()
    Config.HoldPositionOnArrive = HoldArriveToggle.Value
end)

local TargetDropdown = Tabs.Travel:AddDropdown("TargetDropdown", {
    Title = "รายชื่อเป้าหมายที่สแกนเจอ (Sleeper / กล่องไม่ล็อก)",
    Values = {},
    Multi = false,
    Default = nil,
})
TargetDropdown:OnChanged(function(val)
    Config.SelectedTargetName = val
end)

Tabs.Travel:AddButton({
    Title = "สแกนเป้าหมายใหม่ (Refresh Targets)",
    Callback = function()
        local list = ScanAllTargets()
        TargetDropdown:SetValues(list)
        Fluent:Notify({
            Title = "Scan Complete",
            Content = "พบเป้าหมายทั้งหมด " .. tostring(#list) .. " จุด",
            Duration = 3
        })
    end
})

Tabs.Travel:AddButton({
    Title = "บินไปหา Sleeper (คนนอน) ที่ใกล้ที่สุด",
    Callback = function()
        local part, err = FindNearestTarget(function(obj)
            local isSlp = GetSleeperInfo(obj)
            return isSlp
        end)
        if part then
            StartSafeTravel(part, false)
            Fluent:Notify({ Title = "Smooth Flight", Content = "กำลังบินไปหา Sleeper...", Duration = 3 })
        else
            Fluent:Notify({ Title = "ไม่พบ Sleeper", Content = err or "ไม่มีคนนอนในบริเวณนี้", Duration = 3 })
        end
    end
})

Tabs.Travel:AddButton({
    Title = "บินไปหากล่องที่ไม่ล็อกที่ใกล้ที่สุด",
    Callback = function()
        local part, err = FindNearestTarget(function(obj) return ValidContainers[obj.Name] == true end)
        if part then
            StartSafeTravel(part, false)
            Fluent:Notify({ Title = "Smooth Flight", Content = "กำลังบินไปหากล่องที่ไม่ล็อก...", Duration = 3 })
        else
            Fluent:Notify({ Title = "ไม่พบกล่อง", Content = err or "ไม่มีกล่องที่เปิดได้ในขณะนี้", Duration = 3 })
        end
    end
})

Tabs.Travel:AddButton({
    Title = "บินไปยังเป้าหมายที่เลือกใน Dropdown",
    Callback = function()
        local data = Config.SelectedTargetName and Config.ScannedTargets[Config.SelectedTargetName]
        if data and data.Part and data.Part.Parent then
            if IsDeployableLocked(data.Instance) then
                Fluent:Notify({ Title = "ติดล็อก!", Content = "เป้าหมายนี้ถูกล็อกแล้ว", Duration = 3 })
                return
            end
            StartSafeTravel(data.Part, false)
        else
            Fluent:Notify({ Title = "แจ้งเตือน", Content = "กรุณากดสแกนและเลือกเป้าหมายใน Dropdown ก่อน", Duration = 3 })
        end
    end
})

Tabs.Travel:AddButton({
    Title = "สั่งเปิดกล่อง/ศพที่อยู่ใกล้ตัวทันที (Force Open UI)",
    Description = "เรียกหน้าต่างเก็บของของกล่องหรือคนนอนในระยะประชิดทันที",
    Callback = function()
        local ok, name = QuickOpenNearestContainer()
        if ok then
            Fluent:Notify({ Title = "Opened", Content = "เปิดช่องเก็บของ: " .. tostring(name), Duration = 2 })
        else
            Fluent:Notify({ Title = "แจ้งเตือน", Content = "ต้องอยู่ใกล้เป้าหมายในระยะไม่เกิน 12m", Duration = 3 })
        end
    end
})

Tabs.Travel:AddSlider("TravelSpeedSlider", {
    Title = "ความเร็วในการบิน (Anti-Rubberband Speed)",
    Description = "แนะนำ 24 - 35 Studs/s หากตั้งสูงกว่านี้เซิร์ฟเวอร์อาจดึงกลับที่เดิม",
    Default = 28,
    Min = 18,
    Max = 50,
    Rounding = 0,
    Callback = function(val) Config.TravelSpeed = val end
})

Tabs.Travel:AddButton({
    Title = "Return to Saved Pos (บินกลับจุดเดิม)",
    Callback = function()
        if Config.SavedPosition then
            StartSafeTravel(Config.SavedPosition.Position, true)
            Fluent:Notify({ Title = "Returning", Content = "กำลังบินกลับจุดปลอดภัย...", Duration = 3 })
        else
            Fluent:Notify({ Title = "แจ้งเตือน", Content = "ยังไม่มีพิกัดเดิมที่บันทึกไว้", Duration = 3 })
        end
    end
})

Tabs.Travel:AddButton({
    Title = "Stop Travel / Fix Walk (หยุดบินและรีเซ็ตการเดิน)",
    Description = "กดปุ่มนี้หากต้องการหยุดบินกลางคัน หรือปลดล็อกฟิสิกส์ตัวละครทันที",
    Callback = function()
        Config.ManualNoclip = false
        ManualNoclipToggle:SetValue(false)
        StopSafeTravel()
        Fluent:Notify({ Title = "Physics Reset", Content = "คืนค่าการเดินปกติเรียบร้อยแล้ว", Duration = 2 })
    end
})

-- ------------------------------------------------------------------------------
-- TAB 2: SOFT FOV AIMLOCK
-- ------------------------------------------------------------------------------
local AimToggle = Tabs.Combat:AddToggle("AimToggle", { Title = "เปิดใช้งาน Soft FOV Aimlock", Default = false })
AimToggle:OnChanged(function() Config.AimlockEnabled = AimToggle.Value end)

local FOVToggle = Tabs.Combat:AddToggle("FOVToggle", { Title = "แสดงวงกลมระยะล็อค (FOV Circle)", Default = false })
FOVToggle:OnChanged(function() Config.ShowFOV = FOVToggle.Value end)

Tabs.Combat:AddSlider("FOVRadiusSlider", {
    Title = "ขนาดรัศมีวง FOV (px)",
    Default = 120,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(val) Config.FOVRadius = val end
})

Tabs.Combat:AddSlider("SmoothnessSlider", {
    Title = "ความนุ่มนวลในการล็อค (Smoothness)",
    Default = 0.14,
    Min = 0.05,
    Max = 0.40,
    Rounding = 2,
    Callback = function(val) Config.AimSmoothness = val end
})

Tabs.Combat:AddSlider("BreakawaySlider", {
    Title = "แรงดึงเมาส์/นิ้วเพื่อหลุดล็อค (Breakaway)",
    Default = 4.5,
    Min = 2.0,
    Max = 15.0,
    Rounding = 1,
    Callback = function(val) Config.BreakawayThreshold = val end
})

local WallCheckToggle = Tabs.Combat:AddToggle("WallCheckToggle", { Title = "เช็กสิ่งกีดขวาง (WallCheck)", Default = true })
WallCheckToggle:OnChanged(function() Config.WallCheck = WallCheckToggle.Value end)

local TeamCheckToggle = Tabs.Combat:AddToggle("TeamCheckToggle", { Title = "ข้ามเพื่อนร่วมทีม (TeamCheck)", Default = true })
TeamCheckToggle:OnChanged(function() Config.TeamCheck = TeamCheckToggle.Value end)

-- ------------------------------------------------------------------------------
-- TAB 3: ESP VISUALS
-- ------------------------------------------------------------------------------
local PlayerESPToggle = Tabs.Visuals:AddToggle("PlayerESPToggle", { Title = "ESP ผู้เล่นออนไลน์ (Active Players)", Default = false })
PlayerESPToggle:OnChanged(function() Config.PlayerESPEnabled = PlayerESPToggle.Value end)

local SleeperESPToggle = Tabs.Visuals:AddToggle("SleeperESPToggle", { Title = "ESP คนนอนออฟไลน์และถุงศพ (Sleeper & BodyBag)", Default = false })
SleeperESPToggle:OnChanged(function() Config.SleeperESPEnabled = SleeperESPToggle.Value end)

local CrateESPToggle = Tabs.Visuals:AddToggle("CrateESPToggle", { Title = "ESP กล่องไม้ที่ไม่ได้ล็อก (Unlocked Wooden Crate)", Default = false })
CrateESPToggle:OnChanged(function() Config.CrateESPEnabled = CrateESPToggle.Value end)

Tabs.Visuals:AddSlider("RenderDistSlider", {
    Title = "ระยะการมองเห็นสูงสุด (Max Render Distance)",
    Default = 1000,
    Min = 100,
    Max = 2500,
    Rounding = 0,
    Callback = function(val) Config.MaxRenderDistance = val end
})

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
