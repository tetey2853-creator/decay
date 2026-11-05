-- ==============================================================================
-- TeteKubb Hub (V14.1 - Fixed GeneratedMonuments Error + Hyper-Smooth + Vacuum)
-- Features: 0-Lag Cached ESP, Auto-Loot Crates/Bags/Ground, Target Loadout HUD,
--           Smooth Predictive Aimbot, No Recoil, Fullbright (B), Auto Ore Spark
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
-- [0] CLEANUP OLD INSTANCE & LIFECYCLE FLAG
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

if hookmetamethod and not GlobalEnv._RustACBypassedV11 then
    GlobalEnv._RustACBypassedV11 = true
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
-- [2] GLOBAL CONFIG
-- ==============================================================================
local Config = {
    -- ระบบ Aimbot
    AimlockEnabled = false,
    AimActivationMode = "Always",
    TargetPartMode = "Head",
    AirborneBodyAim = true,
    StickyAim = true,
    AimSmoothness = 0.50,
    UsePrediction = true,
    PredictionMultiplier = 1.05,
    BulletDropCompensation = true,
    BreakawayThreshold = 12.0,
    MaxAimDistance = 900,
    FOVRadius = 150,
    ShowFOV = false,
    ShowTargetLine = false,
    ShowStatusHUD = false,
    LockScientists = true,
    WallCheck = false,
    TeamCheck = false,

    -- ระบบเช็คของผู้เล่นที่ล็อคเป้า (Target Inspector)
    ShowTargetInventory = true,

    -- ปุ่มลัดคีย์บอร์ด
    Key_ToggleAimbot = Enum.KeyCode.X,
    Key_SwitchPart = Enum.KeyCode.V,
    Key_ToggleFullbright = Enum.KeyCode.B,

    -- ระบบลดแรงดีดปืน
    NoRecoilEnabled = false,
    RecoilScale = 0,

    -- ระบบความสว่าง & หญ้า
    FullbrightEnabled = false,
    FullbrightLevel = 2.5,
    RemoveFogAndShadows = true,
    HideTerrainGrass = false,

    -- ระบบตีแร่โดนจุด Spark
    AutoSparkEnabled = false,
    ShowSparkESP = true,
    SparkRange = 10,

    -- ระบบดูดของอัตโนมัติ (Auto-Loot & Vacuum)
    AutoPickupEnabled = false,
    AutoPickupRange = 14,
    AutoLootOpenContainer = false,
    AutoLootNearbyContainers = false,
    LootFilterMode = "All",

    -- ระบบเช็คของในกล่อง
    ShowCrateContents = true,
    AutoFetchStorage = false,

    -- ระบบ ESP
    ESP_Players = false,
    ESP_Scientists = false,
    ESP_Sleepers = false,
    ESP_BodyBags = false,
    ESP_TC = false,
    ESP_BaseOwner = false,
    ESP_Traps = false,

    ESP_StoneOre = false,
    ESP_MetalOre = false,
    ESP_SulfurOre = false,
    ESP_GrassCloth = false,

    ESP_Storage = false,
    ESP_OnlyUnlockedStorage = false,
    ESP_LootCrates = false,
    ESP_MilitaryCrates = false,
    ESP_Barrels = false,
    ESP_FuelBarrels = false,
    ESP_DroppedItems = false,

    PlayerRenderDistance = 1200,
    WorldRenderDistance = 650,
    MaxWorldESPCount = 45,
}

local CurrentLockedModel = nil
local CurrentLockedPart = nil
local CurrentPredictedPos = nil
local CurrentTargetName = "None"
local CachedScientists = {}
local CachedNearestSpark = nil

-- ==============================================================================
-- [3] FULLBRIGHT, TERRAIN GRASS & SETAMBIENT BLOCKER
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

local function ApplyTerrainGrassState(hideGrass)
    if sethiddenproperty and workspace.Terrain then
        pcall(function()
            sethiddenproperty(workspace.Terrain, "Decoration", not hideGrass)
        end)
    end
end

if SetAmbientRemote then
    AddConnection(SetAmbientRemote.OnClientEvent:Connect(function()
        if Config.FullbrightEnabled then
            task.defer(function() ApplyFullbrightState(true) end)
        end
    end))
end

AddConnection(Lighting.Changed:Connect(function()
    if Config.FullbrightEnabled then
        Lighting.Ambient = Color3.fromRGB(210, 210, 210)
        Lighting.OutdoorAmbient = Color3.fromRGB(210, 210, 210)
        Lighting.Brightness = Config.FullbrightLevel
        Lighting.ClockTime = 14
        if Config.RemoveFogAndShadows then
            Lighting.FogEnd = 100000
            Lighting.FogStart = 100000
            Lighting.GlobalShadows = false
        end
    end
end))

-- ==============================================================================
-- [4] LOAD GAME MODULES, REMOTES & NO RECOIL HOOK
-- ==============================================================================
local GameItemData = nil
local GameAmmoTypes = nil
local GameStorageView = nil
local PickUpRequestRemote = nil
local AddPlayerToStorageRemote = nil
local QuickMoveFromStorageRemote = nil

pcall(function()
    local itemMod = ReplicatedStorage:WaitForChild("ItemData", 5)
    if itemMod then GameItemData = require(itemMod).Items end
    local ammoMod = ReplicatedStorage:WaitForChild("AmmoTypes", 5)
    if ammoMod then GameAmmoTypes = require(ammoMod) end
    local svMod = ReplicatedStorage:WaitForChild("StorageView", 5)
    if svMod then GameStorageView = require(svMod) end

    local lootSys = ReplicatedStorage:WaitForChild("LootSystem", 5)
    local lootRemotes = lootSys and lootSys:WaitForChild("RemoteEvents", 5)
    if lootRemotes then
        PickUpRequestRemote = lootRemotes:FindFirstChild("PickUpRequest")
        AddPlayerToStorageRemote = lootRemotes:FindFirstChild("AddPlayerToStorage")
    end

    local invFolder = ReplicatedStorage:WaitForChild("Inventory", 5)
    local storageRemotes = invFolder and invFolder:WaitForChild("StorageRemoteEvents", 5)
    if storageRemotes then
        QuickMoveFromStorageRemote = storageRemotes:FindFirstChild("QuickMoveFromStorage")
    end
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

local ValuableItemsMap = {
    ["Scrap"] = true, ["Cloth"] = true, ["Metal Ore"] = true, ["Metal Bar"] = true,
    ["High Quality Metal Ore"] = true, ["High Quality Metal Bar"] = true,
    ["Sulfur Ore"] = true, ["Sulfur"] = true, ["Gunpowder"] = true, ["Fuel"] = true,
    ["Diesel Fuel"] = true, ["C4"] = true, ["Dynamite"] = true, ["Supply Signal"] = true,
    ["Medical Syringe"] = true, ["Bandage"] = true, ["Jackhammer"] = true,
    ["Red Keycard"] = true, ["Blue Keycard"] = true, ["Green Keycard"] = true,
}

local function ShouldLootItem(itemName)
    if not itemName or itemName == "" then return false end
    if Config.LootFilterMode == "All" then return true end
    if ValuableItemsMap[itemName] then return true end
    if GameItemData and GameItemData[itemName] then
        local t = GameItemData[itemName].Type
        if t == "Gun" or t == "Ammo" or t == "Component" or t == "Attachment" or t == "Clothes" then
            return true
        end
    end
    return false
end

local ClothingAssetMap = {
    ["13319023083"] = { Name = "Burlap Shirt", Protection = 10 },
    ["13315993089"] = { Name = "Burlap Trousers", Protection = 10 },
    ["16001675719"] = { Name = "Hoodie", Protection = 20 },
    ["112146303712876"] = { Name = "Pants", Protection = 15 },
    ["117675966308035"] = { Name = "Hide Vest", Protection = 12 },
    ["140352819642633"] = { Name = "Hide Pants", Protection = 12 },
}

local ArmorKeywords = {
    ["Military Helmet"] = 50,
    ["Military Vest"] = 25,
    ["Coffee Can Helmet"] = 35,
    ["Hazmat Suit"] = 30,
    ["Hazmat"] = 30,
    ["Road Sign Jacket"] = 20,
    ["Road Sign Kilt"] = 20,
    ["Wood Armor Helmet"] = 15,
    ["Wood Chestplate"] = 10,
    ["Wood Armor Pants"] = 10,
}

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
-- [5] CHARACTER RESOLVER, TEAM CHECK & TARGET/CRATE INSPECTOR LOGIC
-- ==============================================================================
local PlayerWeaponHistory = {}
local CachedPlayerWeapon = {}
local StorageFetchCooldown = {}

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

local function InspectCharacterLoadout(char)
    if not char or not char.Parent then return nil end

    local heldWeapon = "Unarmed"
    local attachmentsList = {}
    local armorSet = {}
    local totalProtection = 0

    local history = PlayerWeaponHistory[char.Name]
    if not history then
        history = {}
        PlayerWeaponHistory[char.Name] = history
    end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") or (child:IsA("Model") and (child:FindFirstChild("GunComponents") or child:FindFirstChild("ToolComponents") or child:FindFirstChild("Handle"))) then
            heldWeapon = child.Name
            history[child.Name] = true

            local eqAtt = child:FindFirstChild("EquippedAttachments")
            if eqAtt then
                for _, att in ipairs(eqAtt:GetChildren()) do
                    table.insert(attachmentsList, att.Name)
                end
            else
                if child:GetAttribute("HasScope") then table.insert(attachmentsList, "8x Scope") end
                if child:GetAttribute("HasLaser") then table.insert(attachmentsList, "Weapon Laser") end
                if child:GetAttribute("HasFlashlight") and not child:GetAttribute("HasLaser") then
                    table.insert(attachmentsList, "Flashlight")
                end
            end
        end

        if child:IsA("Shirt") or child:IsA("Pants") then
            local template = tostring(child:IsA("Shirt") and child.ShirtTemplate or child.PantsTemplate)
            for assetId, info in pairs(ClothingAssetMap) do
                if string.find(template, assetId, 1, true) and not armorSet[info.Name] then
                    armorSet[info.Name] = true
                    totalProtection = totalProtection + info.Protection
                end
            end
        end

        for armorName, prot in pairs(ArmorKeywords) do
            if string.find(child.Name, armorName, 1, true) and not armorSet[armorName] then
                armorSet[armorName] = true
                totalProtection = totalProtection + prot
            end
        end
    end

    CachedPlayerWeapon[char] = heldWeapon

    local extraItems = {}
    local storageFolder = char:FindFirstChild("Storage") or (GameStorageView and GameStorageView.IsLoaded(char) and GameStorageView.Get(char))
    if storageFolder then
        local counts = {}
        for _, slot in ipairs(storageFolder:GetChildren()) do
            local iName = slot:FindFirstChild("ItemName")
            local iAmt = slot:FindFirstChild("Amount")
            if iName and iName.Value ~= "" then
                local amt = (iAmt and tonumber(iAmt.Value)) or 1
                counts[iName.Value] = (counts[iName.Value] or 0) + amt
            end
        end
        for name, amt in pairs(counts) do
            table.insert(extraItems, string.format("%s x%d", name, amt))
        end
    end

    local knownWeapons = {}
    for wName, _ in pairs(history) do
        if wName ~= heldWeapon then
            table.insert(knownWeapons, wName)
        end
    end

    local armorList = {}
    for aName, _ in pairs(armorSet) do
        table.insert(armorList, aName)
    end

    return {
        HeldWeapon = heldWeapon,
        Attachments = attachmentsList,
        KnownWeapons = knownWeapons,
        ArmorList = armorList,
        Protection = math.min(totalProtection, 90),
        StorageItems = extraItems
    }
end

local function BuildContainerItemsSummary(containerObj, distToPlayer)
    if not Config.ShowCrateContents or not containerObj then return "" end

    local storageFolder = containerObj:FindFirstChild("Storage")
    if not storageFolder and GameStorageView then
        if GameStorageView.IsLoaded(containerObj) then
            storageFolder = GameStorageView.Get(containerObj)
        elseif (Config.AutoFetchStorage or Config.AutoLootNearbyContainers) and AddPlayerToStorageRemote and distToPlayer <= 16 then
            local now = os.clock()
            if not StorageFetchCooldown[containerObj] or (now - StorageFetchCooldown[containerObj]) > 4.5 then
                StorageFetchCooldown[containerObj] = now
                pcall(function()
                    AddPlayerToStorageRemote:FireServer(containerObj)
                end)
            end
        end
    end

    if not storageFolder then return "" end

    local itemCounts = {}
    local itemOrder = {}
    for _, slot in ipairs(storageFolder:GetChildren()) do
        local itemNameVal = slot:FindFirstChild("ItemName")
        local amountVal = slot:FindFirstChild("Amount")
        if itemNameVal and itemNameVal.Value ~= "" then
            local name = itemNameVal.Value
            local amt = (amountVal and tonumber(amountVal.Value)) or 1
            if not itemCounts[name] then
                itemCounts[name] = 0
                table.insert(itemOrder, name)
            end
            itemCounts[name] = itemCounts[name] + amt
        end
    end

    if #itemOrder == 0 then
        return "\n[ว่างเปล่า]"
    end

    local displayList = {}
    local maxShow = math.min(#itemOrder, 4)
    for i = 1, maxShow do
        local name = itemOrder[i]
        table.insert(displayList, string.format("%s x%d", name, itemCounts[name]))
    end
    if #itemOrder > 4 then
        table.insert(displayList, string.format("+%d", #itemOrder - 4))
    end

    return "\nของ: " .. table.concat(displayList, ", ")
end

-- ==============================================================================
-- [6] STABLE VELOCITY TRACKER & BALLISTICS PREDICTION
-- ==============================================================================
local VelocityTracker = {}

local function GetTargetVelocity(model, rootPart)
    if not model or not rootPart or not rootPart:IsA("BasePart") then return Vector3.zero end
    local now = os.clock()
    local currentPos = rootPart.Position
    local record = VelocityTracker[model]

    if not record then
        VelocityTracker[model] = {
            LastPos = currentPos,
            SmoothedVel = Vector3.zero,
            LastTime = now
        }
        return Vector3.zero
    end

    local dt = now - record.LastTime
    if dt >= 0.04 then
        local deltaVel = (currentPos - record.LastPos) / dt
        local engineVel = rootPart.AssemblyLinearVelocity or Vector3.zero

        local rawVel = engineVel
        if engineVel.Magnitude > 0.5 then
            rawVel = (engineVel * 0.70) + (deltaVel * 0.30)
        elseif deltaVel.Magnitude > 2.5 and deltaVel.Magnitude < 120 then
            rawVel = deltaVel
        else
            rawVel = Vector3.zero
        end

        if rawVel.Magnitude > 140 then
            rawVel = Vector3.zero
        end

        record.SmoothedVel = record.SmoothedVel:Lerp(rawVel, 0.35)
        if record.SmoothedVel.Magnitude < 1.8 then
            record.SmoothedVel = Vector3.zero
        end

        record.LastPos = currentPos
        record.LastTime = now
    end

    return record.SmoothedVel
end

local function CalculatePredictedAimPosition(targetPart, targetModel)
    if not targetPart or not targetPart:IsA("BasePart") then return nil end
    local basePos = targetPart.Position
    if not Config.UsePrediction or not targetModel then
        return basePos
    end

    local rootPart = targetModel:FindFirstChild("HumanoidRootPart")
    if not (rootPart and rootPart:IsA("BasePart")) then
        rootPart = targetPart
    end
    local velocity = GetTargetVelocity(targetModel, rootPart)

    local camPos = Camera.CFrame.Position
    local distance = (basePos - camPos).Magnitude
    local bulletSpeed, bulletGravity = GetCurrentWeaponBallistics()
    bulletSpeed = math.max(bulletSpeed, 80)

    local timeToHit = distance / bulletSpeed
    local futurePos1 = basePos + Vector3.new(velocity.X, velocity.Y * 0.25, velocity.Z) * timeToHit
    timeToHit = (futurePos1 - camPos).Magnitude / bulletSpeed

    local horizontalLead = Vector3.new(velocity.X, 0, velocity.Z) * (timeToHit * Config.PredictionMultiplier)
    local verticalLead = Vector3.new(0, velocity.Y * 0.25 * timeToHit * Config.PredictionMultiplier, 0)

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
    if not targetPart or not targetPart:IsA("BasePart") then return false end

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

local function FindBasePartChild(parent, name)
    if not parent then return nil end
    local c = parent:FindFirstChild(name)
    if c and c:IsA("BasePart") then return c end
    return nil
end

local function GetSmartAimPart(character)
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = FindBasePartChild(character, "HumanoidRootPart")
    local head = FindBasePartChild(character, "Head")
    local torso = FindBasePartChild(character, "Torso") or FindBasePartChild(character, "UpperTorso") or root

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
            local p = FindBasePartChild(character, partName)
            if p then
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
    if oreModel.PrimaryPart and oreModel.PrimaryPart:IsA("BasePart") then
        return oreModel.PrimaryPart
    end
    return oreModel:FindFirstChildWhichIsA("BasePart")
end

task.spawn(function()
    while ScriptRunning do
        pcall(function()
            if Config.AutoSparkEnabled then
                local char = GetLocalCharacter()
                local root = FindBasePartChild(char, "HumanoidRootPart")
                local oreSpawns = workspace:FindFirstChild("OreSpawns")
                local bestSparkPart = nil
                local shortestDist = Config.SparkRange

                if root and oreSpawns then
                    for _, zone in ipairs(oreSpawns:GetChildren()) do
                        for _, ore in ipairs(zone:GetChildren()) do
                            local primary = (ore.PrimaryPart and ore.PrimaryPart:IsA("BasePart") and ore.PrimaryPart)
                                or FindBasePartChild(ore, "Top")
                            if primary then
                                local dist = (primary.Position - root.Position).Magnitude
                                if dist <= shortestDist then
                                    local sparkPart = GetActiveSparkPart(ore)
                                    if sparkPart then
                                        shortestDist = dist
                                        bestSparkPart = sparkPart
                                    end
                                end
                            end
                        end
                    end
                end
                CachedNearestSpark = bestSparkPart
            else
                CachedNearestSpark = nil
            end
        end)
        task.wait(0.14)
    end
end)

-- ==============================================================================
-- [8] UI OVERLAY (FOV, TARGET LINE, STATUS HUD & TARGET INSPECTOR PANEL)
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

local TargetInspectorFrame = Instance.new("Frame")
TargetInspectorFrame.Name = "TargetInspectorFrame"
TargetInspectorFrame.Size = UDim2.fromOffset(310, 128)
TargetInspectorFrame.Position = UDim2.new(0.5, 175, 0.5, -64)
TargetInspectorFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
TargetInspectorFrame.BackgroundTransparency = 0.18
TargetInspectorFrame.Visible = false
TargetInspectorFrame.Parent = OverlayGui

local InspCorner = Instance.new("UICorner")
InspCorner.CornerRadius = UDim.new(0, 10)
InspCorner.Parent = TargetInspectorFrame

local InspStroke = Instance.new("UIStroke")
InspStroke.Color = Color3.fromRGB(255, 75, 75)
InspStroke.Thickness = 1.5
InspStroke.Parent = TargetInspectorFrame

local InspTitle = Instance.new("TextLabel")
InspTitle.Size = UDim2.new(1, -16, 0, 24)
InspTitle.Position = UDim2.fromOffset(8, 6)
InspTitle.BackgroundTransparency = 1
InspTitle.Font = Enum.Font.GothamBold
InspTitle.TextSize = 14
InspTitle.TextXAlignment = Enum.TextXAlignment.Left
InspTitle.TextColor3 = Color3.fromRGB(255, 95, 95)
InspTitle.TextStrokeTransparency = 0.2
InspTitle.Text = "เป้าหมาย: None"
InspTitle.Parent = TargetInspectorFrame

local InspBody = Instance.new("TextLabel")
InspBody.Size = UDim2.new(1, -16, 1, -34)
InspBody.Position = UDim2.fromOffset(8, 30)
InspBody.BackgroundTransparency = 1
InspBody.Font = Enum.Font.RobotoMono
InspBody.TextSize = 12
InspBody.TextXAlignment = Enum.TextXAlignment.Left
InspBody.TextYAlignment = Enum.TextYAlignment.Top
InspBody.TextWrapped = true
InspBody.TextColor3 = Color3.fromRGB(235, 235, 245)
InspBody.TextStrokeTransparency = 0.25
InspBody.Text = ""
InspBody.Parent = TargetInspectorFrame

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
-- [9] SMOOTH CAMERA AIMBOT ENGINE & TARGET INSPECTOR UPDATER
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

local LastInspectorUpdate = 0

local function UpdateAimbotStep(dt)
    if not ScriptRunning then return end
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local frameDt = math.clamp(dt or (1 / 60), 0.001, 0.1)
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
        local newHudText = string.format(
            "TeteKubb V14.1 | [%s] Aimbot: %s | [%s] เล็ง: %s | [%s] แสง: %s | เป้า: %s",
            GetKeyNameSafe(Config.Key_ToggleAimbot), aimTxt,
            GetKeyNameSafe(Config.Key_SwitchPart), tostring(Config.TargetPartMode),
            GetKeyNameSafe(Config.Key_ToggleFullbright), fbTxt,
            tostring(CurrentTargetName)
        )
        if StatusHUD.Text ~= newHudText then
            StatusHUD.Text = newHudText
        end
    end

    if Config.AutoSparkEnabled and CachedNearestSpark and CachedNearestSpark.Parent then
        local spScreen, onScreen = Camera:WorldToViewportPoint(CachedNearestSpark.Position)
        if onScreen and Config.ShowSparkESP then
            SparkMarker.Position = UDim2.fromOffset(spScreen.X, spScreen.Y)
            SparkMarker.Visible = true
        else
            SparkMarker.Visible = false
        end

        local isAttacking = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or IsMobileAttacking
        if isAttacking and IsHoldingMiningTool() and not IsGameMenuOpen() then
            local alpha = 1 - ((1 - 0.55) ^ (frameDt * 60))
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, CachedNearestSpark.Position), math.clamp(alpha, 0.05, 0.95))
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
        TargetInspectorFrame.Visible = false
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

        if Config.ShowTargetInventory then
            TargetInspectorFrame.Visible = true
            local now = os.clock()
            if (now - LastInspectorUpdate) >= 0.20 then
                LastInspectorUpdate = now
                local hp = math.floor(GetCharacterHealth(CurrentLockedModel))
                local dist = math.floor((CurrentLockedPart.Position - Camera.CFrame.Position).Magnitude)
                local info = InspectCharacterLoadout(CurrentLockedModel)

                InspTitle.Text = string.format("🎯 ล็อคเป้า: %s [%d HP] (%dm)", tostring(CurrentTargetName), hp, dist)
                if info then
                    local attStr = (#info.Attachments > 0) and (" (" .. table.concat(info.Attachments, ", ") .. ")") or ""
                    local knownStr = (#info.KnownWeapons > 0) and table.concat(info.KnownWeapons, ", ") or "ยังไม่พบของสลับถือ"
                    local armorStr = (#info.ArmorList > 0) and table.concat(info.ArmorList, ", ") or "ไม่มีเกราะ"
                    local storageStr = (#info.StorageItems > 0) and ("\nช่องของ: " .. table.concat(info.StorageItems, ", ")) or ""

                    InspBody.Text = string.format(
                        "ถืออยู่: %s%s\nของในตัวที่พบ: %s\nเกราะ (%d%%): %s%s",
                        info.HeldWeapon, attStr,
                        knownStr,
                        info.Protection, armorStr,
                        storageStr
                    )
                end
            end
        else
            TargetInspectorFrame.Visible = false
        end

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
            local baseSmooth = Config.AimSmoothness

            local rootOrPart = FindBasePartChild(CurrentLockedModel, "HumanoidRootPart") or CurrentLockedPart
            local targetVel = GetTargetVelocity(CurrentLockedModel, rootOrPart)
            if targetVel.Magnitude > 8 then
                baseSmooth = math.clamp(baseSmooth * 1.30, 0.15, 0.92)
            end

            local isBreakingAway = false
            if deltaMag >= Config.BreakawayThreshold and predOnScreen then
                local toTarget = Vector2.new(predScreen.X, predScreen.Y) - screenCenter
                if toTarget.Magnitude > 4 and mouseDelta.Unit:Dot(toTarget.Unit) < -0.20 then
                    isBreakingAway = true
                end
            end

            if not isBreakingAway and CurrentPredictedPos then
                local frameAlpha = 1 - ((1 - baseSmooth) ^ (frameDt * 60))
                frameAlpha = math.clamp(frameAlpha, 0.05, 0.96)

                local goalCFrame = CFrame.lookAt(Camera.CFrame.Position, CurrentPredictedPos)
                Camera.CFrame = Camera.CFrame:Lerp(goalCFrame, frameAlpha)
            end
        end
    else
        CurrentTargetName = "None"
        FOVStroke.Color = Color3.fromRGB(255, 255, 255)
        PredictionDot.Visible = false
        TargetLine.Visible = false
        TargetInspectorFrame.Visible = false
    end
end

RunService:BindToRenderStep("TeteKubbAimbotEngine", Enum.RenderPriority.Last.Value + 10, UpdateAimbotStep)

-- ==============================================================================
-- [10] SHALLOW NON-BLOCKING WORLD INDEXER & AUTO-LOOT VACUUM (FIXED BASEPART CHECK)
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

    local head = FindBasePartChild(obj, "Head")
    local nameUI = head and head:FindFirstChild("NameUI")
    local nameLabel = nameUI and nameUI:FindFirstChild("NameLabel")
    local sleeperName = (nameLabel and nameLabel.Text ~= "" and nameLabel.Text) or obj.Name

    if obj.Name == "Sleeper" or obj:FindFirstChild("Sleeper") then
        return true, sleeperName
    end

    local hasTorso = FindBasePartChild(obj, "Torso") or FindBasePartChild(obj, "UpperTorso") or FindBasePartChild(obj, "HumanoidRootPart")
    if head and hasTorso and not IsActiveOnlineCharacter(obj) then
        local hum = obj:FindFirstChildOfClass("Humanoid")
        local root = FindBasePartChild(obj, "HumanoidRootPart") or head
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
    local root = FindBasePartChild(obj, "HumanoidRootPart")
    local head = FindBasePartChild(obj, "Head")

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

-- แก้ไขบั๊ก: บังคับตรวจสอบ :IsA("BasePart") ทุกตัว เพื่อไม่ให้คืนค่า Model ที่ชื่อ "Top"
local function GetTargetPart(model)
    if not model then return nil end
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
            return model.PrimaryPart
        end
        for _, partName in ipairs({ "HumanoidRootPart", "Head", "Hitbox", "Core", "Top" }) do
            local candidate = model:FindFirstChild(partName)
            if candidate and candidate:IsA("BasePart") then
                return candidate
            end
        end
        return model:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function IsObjectAlive(obj)
    local hpVal = obj:FindFirstChild("Health") or (obj:FindFirstChild("System") and obj.System:FindFirstChild("Health"))
    if hpVal and hpVal:IsA("ValueBase") and tonumber(hpVal.Value) and tonumber(hpVal.Value) <= 0 then
        return false
    end
    return true
end

local StorageTypes = {
    ["Wooden Crate"] = "กล่องไม้",
    ["Drop Stash"] = "กระเป๋าซ่อนของ",
    ["Furnace"] = "เตาเผาเล็ก",
    ["Large Furnace"] = "เตาเผาใหญ่",
    ["Workbench"] = "โต๊ะคราฟต์ Lv.1",
    ["Workbench Level 2"] = "โต๊ะคราฟต์ Lv.2",
    ["Research Table"] = "โต๊ะวิจัย",
    ["Repair Bench"] = "โต๊ะซ่อมของ",
}

local TrapTypes = {
    ["Shotgun Trap"] = true,
    ["Flame Turret"] = true,
}

local LootCrateNames = {
    ["Crate"] = "กล่องดรอป (Crate)",
    ["FoodCrate"] = "กล่องอาหาร (Food Crate)",
    ["Food Crate"] = "กล่องอาหาร (Food Crate)",
    ["HelicopterCrate"] = "กล่องฮอตก (Heli Crate)",
    ["Helicopter Crate"] = "กล่องฮอตก (Heli Crate)",
    ["Locked Crate"] = "กล่องล็อกเวลา (Locked Crate)",
    ["LockedCrate"] = "กล่องล็อกเวลา (Locked Crate)",
    ["SupplyDrop"] = "แอร์ดรอป (Supply Drop)",
    ["Supply Drop"] = "แอร์ดรอป (Supply Drop)",
    ["Airdrop"] = "แอร์ดรอป (Airdrop)",
}

local MilitaryCrateNames = {
    ["MilitaryCrate"] = "กล่องทหาร (Military Crate)",
    ["Military Crate"] = "กล่องทหาร (Military Crate)",
}

local BarrelNames = {
    ["Barrel"] = "ถังเหล็ก (Barrel)",
    ["LootBarrel"] = "ถังเหล็ก (Barrel)",
}

local FuelBarrelNames = {
    ["FuelBarrel"] = "ถังแก๊ส (Fuel Barrel)",
    ["Fuel Barrel"] = "ถังแก๊ส (Fuel Barrel)",
    ["OilBarrel"] = "ถังแก๊ส (Oil Barrel)",
    ["GasBarrel"] = "ถังแก๊ส (Gas Barrel)",
}

local GrassAndClothKeywords = {
    ["Cloth"] = "ผืนหญ้า/ต้นผ้า (Cloth)",
    ["Hemp"] = "ต้นผ้า (Hemp)",
    ["Grass"] = "ผืนหญ้า (Grass)",
    ["GrassPatch"] = "ผืนหญ้า (Grass)",
    ["ClothPlant"] = "ต้นผ้า (Cloth)",
    ["Mushrooms"] = "เห็ด (Mushroom)",
    ["Mushroom"] = "เห็ด (Mushroom)",
    ["Apple"] = "แอปเปิ้ล (Apple)",
    ["Corn"] = "ข้าวโพด (Corn)",
    ["Pumpkin"] = "ฟักทอง (Pumpkin)",
}

local IgnoredMonumentBuildingNames = {
    ["Lighthouse"] = true,
    ["Gas Station"] = true,
    ["Factory"] = true,
    ["North Bunker"] = true,
    ["Bunker Alpha"] = true,
    ["Arctic Base"] = true,
    ["Oilrig"] = true,
}

local function CleanObjectName(rawName)
    if type(rawName) ~= "string" then return "" end
    return (string.gsub(rawName, "%s*%d+$", ""))
end

local IndexedMonumentModels = {}

local function IsInterestingModel(obj)
    if not obj or not obj:IsA("Model") then return false end
    if IgnoredMonumentBuildingNames[obj.Name] then return false end
    if obj:FindFirstChild("GunComponents") or obj:FindFirstChild("ToolComponents") then return false end
    local raw = obj.Name
    local clean = CleanObjectName(raw)
    if MilitaryCrateNames[raw] or MilitaryCrateNames[clean]
        or LootCrateNames[raw] or LootCrateNames[clean]
        or FuelBarrelNames[raw] or FuelBarrelNames[clean]
        or BarrelNames[raw] or BarrelNames[clean]
        or GrassAndClothKeywords[raw] or GrassAndClothKeywords[clean]
        or obj:FindFirstChild("ItemName")
        or obj:FindFirstChild("HumanoidRootPart")
        or string.find(string.lower(raw), "scientist")
    then
        return true
    end
    return false
end

local function ShallowScanContainer(container, depth)
    if not container or depth > 5 then return end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") then
            if IsInterestingModel(child) then
                IndexedMonumentModels[child] = true
            elseif IgnoredMonumentBuildingNames[child.Name] or depth <= 2 then
                ShallowScanContainer(child, depth + 1)
            end
        elseif child:IsA("Folder") then
            ShallowScanContainer(child, depth + 1)
        end
    end
end

local function WatchMonumentFolder(folder)
    if not folder then return end
    ShallowScanContainer(folder, 1)
    AddConnection(folder.DescendantAdded:Connect(function(desc)
        if desc:IsA("Model") and IsInterestingModel(desc) then
            IndexedMonumentModels[desc] = true
        end
    end))
    AddConnection(folder.DescendantRemoving:Connect(function(desc)
        IndexedMonumentModels[desc] = nil
    end))
end

task.spawn(function()
    WatchMonumentFolder(workspace:FindFirstChild("Monuments"))
    WatchMonumentFolder(workspace:FindFirstChild("GeneratedMonuments"))
end)

local VisibleTrackedObjects = {}
local PickupCandidates = {}
local NearbyContainerCandidates = {}

local function ProcessWorldModel(obj, refPos, rawList, newScientists, newPickups, newContainers, seenSet)
    if not obj or seenSet[obj] or not obj.Parent or not obj:IsA("Model") then return end
    if IgnoredMonumentBuildingNames[obj.Name] then return end
    if obj == GetLocalCharacter() or obj.Name == "Viewmodel" or obj.Name == "StarterCharacter" then return end
    if obj:FindFirstChild("GunComponents") or obj:FindFirstChild("ToolComponents") then return end
    if not IsObjectAlive(obj) then return end

    local part = GetTargetPart(obj)
    if not part or not part:IsA("BasePart") then return end
    local dist = (part.Position - refPos).Magnitude

    local itemNameVal = obj:FindFirstChild("ItemName")
    local amountVal = obj:FindFirstChild("Amount")

    if itemNameVal and itemNameVal:IsA("StringValue") then
        local itemName = itemNameVal.Value ~= "" and itemNameVal.Value or obj.Name
        local cleanItem = CleanObjectName(itemName)
        local amt = (amountVal and amountVal.Value) or 1

        seenSet[obj] = true
        if dist <= 25 and ShouldLootItem(itemName) then
            table.insert(newPickups, { Model = obj, Part = part, Dist = dist })
        end

        if dist <= Config.WorldRenderDistance then
            local grassLabel = GrassAndClothKeywords[itemName] or GrassAndClothKeywords[cleanItem]
            if grassLabel and Config.ESP_GrassCloth then
                table.insert(rawList, {
                    Key = obj, Part = part, Category = "GrassCloth", Dist = dist,
                    Title = string.format("[%s] x%d", grassLabel, amt),
                    CachedSub = "",
                    Color = Color3.fromRGB(80, 255, 120)
                })
            elseif Config.ESP_DroppedItems then
                table.insert(rawList, {
                    Key = obj, Part = part, Category = "DroppedItem", Dist = dist,
                    Title = string.format("[ของตก: %s] x%d", itemName, amt),
                    CachedSub = "",
                    Color = Color3.fromRGB(120, 255, 220)
                })
            end
        end
        return
    end

    local rawName = obj.Name
    local cleanName = CleanObjectName(rawName)

    local milLabel = MilitaryCrateNames[rawName] or MilitaryCrateNames[cleanName]
    if milLabel then
        seenSet[obj] = true
        if dist <= 18 then table.insert(newContainers, { Model = obj, Dist = dist }) end
        if Config.ESP_MilitaryCrates and dist <= Config.WorldRenderDistance then
            table.insert(rawList, {
                Key = obj, Part = part, Category = "MilitaryCrate", Dist = dist,
                Title = "[" .. milLabel .. "]",
                CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                Color = Color3.fromRGB(50, 255, 110)
            })
        end
        return
    end

    local lootLabel = LootCrateNames[rawName] or LootCrateNames[cleanName]
    if lootLabel then
        seenSet[obj] = true
        if dist <= 18 then table.insert(newContainers, { Model = obj, Dist = dist }) end
        if Config.ESP_LootCrates and dist <= Config.WorldRenderDistance then
            table.insert(rawList, {
                Key = obj, Part = part, Category = "LootCrate", Dist = dist,
                Title = "[" .. lootLabel .. "]",
                CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                Color = Color3.fromRGB(255, 215, 0)
            })
        end
        return
    end

    local fuelLabel = FuelBarrelNames[rawName] or FuelBarrelNames[cleanName]
    if fuelLabel then
        if Config.ESP_FuelBarrels and dist <= Config.WorldRenderDistance then
            seenSet[obj] = true
            table.insert(rawList, {
                Key = obj, Part = part, Category = "FuelBarrel", Dist = dist,
                Title = "[" .. fuelLabel .. "]", CachedSub = "",
                Color = Color3.fromRGB(255, 115, 40)
            })
        end
        return
    end

    local barrelLabel = BarrelNames[rawName] or BarrelNames[cleanName]
    if barrelLabel then
        if Config.ESP_Barrels and dist <= Config.WorldRenderDistance then
            seenSet[obj] = true
            table.insert(rawList, {
                Key = obj, Part = part, Category = "Barrel", Dist = dist,
                Title = "[" .. barrelLabel .. "]", CachedSub = "",
                Color = Color3.fromRGB(135, 205, 255)
            })
        end
        return
    end

    local grassLabel = GrassAndClothKeywords[rawName] or GrassAndClothKeywords[cleanName]
    if grassLabel then
        if part.Size.Magnitude < 35 then
            seenSet[obj] = true
            if dist <= 25 then
                table.insert(newPickups, { Model = obj, Part = part, Dist = dist })
            end
            if Config.ESP_GrassCloth and dist <= Config.WorldRenderDistance then
                table.insert(rawList, {
                    Key = obj, Part = part, Category = "GrassCloth", Dist = dist,
                    Title = "[" .. grassLabel .. "]", CachedSub = "",
                    Color = Color3.fromRGB(80, 255, 120)
                })
            end
        end
        return
    end

    if Config.ESP_Scientists or Config.LockScientists then
        local isSci, sciName = IsScientistBot(obj)
        if isSci then
            seenSet[obj] = true
            table.insert(newScientists, obj)
            if Config.ESP_Scientists and dist <= Config.PlayerRenderDistance then
                local hp = GetCharacterHealth(obj)
                table.insert(rawList, {
                    Key = obj, Part = part, Category = "Scientist", Dist = dist,
                    Title = string.format("[BOT: %s] [%d HP]", tostring(sciName), math.floor(hp)),
                    CachedSub = "",
                    Color = Color3.fromRGB(255, 120, 40)
                })
            end
            return
        end
    end

    if Config.ESP_Sleepers then
        local isSlp, slpName = GetSleeperInfo(obj)
        if isSlp then
            seenSet[obj] = true
            if dist <= 18 then table.insert(newContainers, { Model = obj, Dist = dist }) end
            if dist <= Config.WorldRenderDistance then
                table.insert(rawList, {
                    Key = obj, Part = part, Category = "Sleeper", Dist = dist,
                    Title = "[SLEEPER] " .. tostring(slpName),
                    CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                    Color = Color3.fromRGB(185, 115, 255)
                })
            end
        end
    end
end

task.spawn(function()
    while ScriptRunning do
        pcall(function()
            local rawList = {}
            local newScientists = {}
            local newPickups = {}
            local newContainers = {}
            local seenSet = {}

            local myChar = GetLocalCharacter()
            local myRoot = FindBasePartChild(myChar, "HumanoidRootPart")
            local refPos = (myRoot and myRoot.Position) or (Camera and Camera.CFrame.Position) or Vector3.zero

            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local c = GetPlayerCharacter(p)
                    if c then InspectCharacterLoadout(c) end
                end
            end

            local AnyDeployableESP = Config.ESP_TC or Config.ESP_BaseOwner or Config.ESP_Storage
                or Config.ESP_Traps or Config.ESP_Sleepers or Config.ESP_BodyBags or Config.ESP_LootCrates
                or Config.AutoLootNearbyContainers

            local AnyWorldScanESP = Config.ESP_Scientists or Config.LockScientists or Config.ESP_Sleepers
                or Config.ESP_GrassCloth or Config.ESP_DroppedItems or Config.ESP_LootCrates
                or Config.ESP_MilitaryCrates or Config.ESP_Barrels or Config.ESP_FuelBarrels
                or Config.AutoPickupEnabled or Config.AutoLootNearbyContainers

            if AnyDeployableESP then
                local pbs = workspace:FindFirstChild("PlayerBuiltStructures")
                local deployables = pbs and pbs:FindFirstChild("Deployables")
                if deployables then
                    for _, obj in ipairs(deployables:GetChildren()) do
                        local part = GetTargetPart(obj)
                        if part and part:IsA("BasePart") and IsObjectAlive(obj) then
                            seenSet[obj] = true
                            local dist = (part.Position - refPos).Magnitude
                            local isSleeper, sleeperName = GetSleeperInfo(obj)
                            local locked = IsDeployableLocked(obj)

                            if dist <= 18 and not locked and (StorageTypes[obj.Name] or obj.Name == "BodyBag" or isSleeper or obj.Name == "Locked Crate") then
                                table.insert(newContainers, { Model = obj, Dist = dist })
                            end

                            if dist <= Config.WorldRenderDistance then
                                if obj.Name == "Base Claim" and Config.ESP_TC then
                                    local ownerStr = GetBaseOwnerNames(obj)
                                    local lockStatus = locked and "[ล็อก]" or "[ไม่ล็อก]"
                                    local hpVal = obj:FindFirstChild("Health")
                                    local hpTxt = (hpVal and tonumber(hpVal.Value)) and string.format(" (%d HP)", math.floor(hpVal.Value)) or ""
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "TC", Dist = dist,
                                        Title = string.format("[ตู้ TC ฐานบ้าน] %s%s\nเจ้าของ: %s", lockStatus, hpTxt, ownerStr),
                                        CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                                        Color = Color3.fromRGB(255, 85, 255)
                                    })
                                elseif obj.Name == "Sleeping Bag" and Config.ESP_BaseOwner then
                                    local ownerStr = GetBaseOwnerNames(obj)
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "BaseOwner", Dist = dist,
                                        Title = string.format("[เตียงนอน] เจ้าของ: %s", ownerStr),
                                        CachedSub = "",
                                        Color = Color3.fromRGB(255, 155, 60)
                                    })
                                elseif StorageTypes[obj.Name] and Config.ESP_Storage then
                                    if not (Config.ESP_OnlyUnlockedStorage and locked) then
                                        local lockTag = locked and "[ล็อก]" or "[ไม่ล็อก]"
                                        local col = locked and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(65, 235, 255)
                                        table.insert(rawList, {
                                            Key = obj, Part = part, Category = "Storage", Dist = dist,
                                            Title = string.format("[%s] %s", StorageTypes[obj.Name], lockTag),
                                            CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                                            Color = col
                                        })
                                    end
                                elseif isSleeper and Config.ESP_Sleepers then
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "Sleeper", Dist = dist,
                                        Title = "[SLEEPER] " .. tostring(sleeperName),
                                        CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                                        Color = Color3.fromRGB(185, 115, 255)
                                    })
                                elseif obj.Name == "BodyBag" and Config.ESP_BodyBags then
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "BodyBag", Dist = dist,
                                        Title = "[ถุงศพ BodyBag]",
                                        CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                                        Color = Color3.fromRGB(255, 230, 60)
                                    })
                                elseif TrapTypes[obj.Name] and Config.ESP_Traps then
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "Trap", Dist = dist,
                                        Title = "[กับดัก! " .. obj.Name .. "]", CachedSub = "",
                                        Color = Color3.fromRGB(255, 50, 120)
                                    })
                                elseif (obj.Name == "Locked Crate" or obj.Name == "LockedCrate") and Config.ESP_LootCrates then
                                    table.insert(rawList, {
                                        Key = obj, Part = part, Category = "LootCrate", Dist = dist,
                                        Title = "[กล่องล็อกเวลา (Locked Crate)]",
                                        CachedSub = (dist <= 220) and BuildContainerItemsSummary(obj, dist) or "",
                                        Color = Color3.fromRGB(255, 215, 0)
                                    })
                                end
                            end
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
                                    local part = (ore.PrimaryPart and ore.PrimaryPart:IsA("BasePart") and ore.PrimaryPart)
                                        or FindBasePartChild(ore, "Top")
                                    if part then
                                        local dist = (part.Position - refPos).Magnitude
                                        if dist <= Config.WorldRenderDistance then
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
                                            table.insert(rawList, {
                                                Key = ore, Part = part, Category = "Ore", Dist = dist,
                                                Title = string.format("%s (%d HP)", label, math.floor(hp)),
                                                CachedSub = "",
                                                Color = col
                                            })
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if AnyWorldScanESP then
                for _, topChild in ipairs(workspace:GetChildren()) do
                    if topChild:IsA("Model") then
                        ProcessWorldModel(topChild, refPos, rawList, newScientists, newPickups, newContainers, seenSet)
                    elseif topChild:IsA("Folder")
                        and topChild.Name ~= "Monuments"
                        and topChild.Name ~= "GeneratedMonuments"
                        and topChild.Name ~= "OreSpawns"
                        and topChild.Name ~= "PlayerBuiltStructures"
                        and topChild.Name ~= "Decorations"
                        and topChild.Name ~= "Add-ons"
                    then
                        for _, sub in ipairs(topChild:GetChildren()) do
                            if sub:IsA("Model") then
                                ProcessWorldModel(sub, refPos, rawList, newScientists, newPickups, newContainers, seenSet)
                            end
                        end
                    end
                end

                for monModel, _ in pairs(IndexedMonumentModels) do
                    if monModel and monModel.Parent then
                        ProcessWorldModel(monModel, refPos, rawList, newScientists, newPickups, newContainers, seenSet)
                    else
                        IndexedMonumentModels[monModel] = nil
                    end
                end
            end

            if #rawList > Config.MaxWorldESPCount then
                table.sort(rawList, function(a, b)
                    return a.Dist < b.Dist
                end)
                local capped = {}
                for i = 1, Config.MaxWorldESPCount do
                    capped[i] = rawList[i]
                end
                VisibleTrackedObjects = capped
            else
                VisibleTrackedObjects = rawList
            end

            CachedScientists = newScientists
            PickupCandidates = newPickups
            NearbyContainerCandidates = newContainers
        end)
        task.wait(0.65)
    end
end)

-- ลูปดูดของอัตโนมัติ (ดูดของตกพื้น + ดูดของในกล่องที่เปิดอยู่ + ดูดของในกล่องรอบตัว)
local PickupCooldowns = {}
local SlotLootCooldowns = {}

local function TryQuickLootContainerSlots(slotsFolder)
    if not slotsFolder or not QuickMoveFromStorageRemote then return 0 end
    local now = os.clock()
    local moved = 0

    for _, slot in ipairs(slotsFolder:GetChildren()) do
        local itemNameVal = slot:FindFirstChild("ItemName")
        local amountVal = slot:FindFirstChild("Amount")
        if itemNameVal and itemNameVal.Value ~= "" and (not amountVal or amountVal.Value > 0) then
            if ShouldLootItem(itemNameVal.Value) then
                local slotKey = tostring(slot:GetFullName())
                if not SlotLootCooldowns[slotKey] or (now - SlotLootCooldowns[slotKey]) > 0.35 then
                    SlotLootCooldowns[slotKey] = now
                    moved = moved + 1
                    pcall(function()
                        QuickMoveFromStorageRemote:FireServer(slot)
                    end)
                    if moved >= 6 then break end
                end
            end
        end
    end
    return moved
end

task.spawn(function()
    while ScriptRunning do
        pcall(function()
            local now = os.clock()

            if Config.AutoPickupEnabled and PickUpRequestRemote then
                local char = GetLocalCharacter()
                local root = FindBasePartChild(char, "HumanoidRootPart")
                if root then
                    local myPos = root.Position
                    local firedCount = 0
                    for _, entry in ipairs(PickupCandidates) do
                        local model = entry.Model
                        local part = entry.Part
                        if model and model.Parent and part and part.Parent and part:IsA("BasePart") then
                            if (part.Position - myPos).Magnitude <= Config.AutoPickupRange then
                                if not PickupCooldowns[model] or (now - PickupCooldowns[model]) > 0.40 then
                                    PickupCooldowns[model] = now
                                    firedCount = firedCount + 1
                                    pcall(function()
                                        PickUpRequestRemote:FireServer(model)
                                    end)
                                    if firedCount >= 5 then break end
                                end
                            end
                        end
                    end
                end
            end

            if Config.AutoLootOpenContainer and QuickMoveFromStorageRemote then
                local pGui = LocalPlayer:FindFirstChild("PlayerGui")
                local invGui = pGui and pGui:FindFirstChild("Inventory")
                if invGui then
                    for _, panelName in ipairs({ "Storage", "Furnace", "LargeFurnace", "Campfire", "Recycler" }) do
                        local panel = invGui:FindFirstChild(panelName)
                        if panel and panel.Visible then
                            TryQuickLootContainerSlots(panel)
                        end
                    end
                end
            end

            if Config.AutoLootNearbyContainers and QuickMoveFromStorageRemote then
                for _, entry in ipairs(NearbyContainerCandidates) do
                    local container = entry.Model
                    if container and container.Parent and entry.Dist <= Config.AutoPickupRange then
                        local storageFolder = container:FindFirstChild("Storage")
                        if not storageFolder and GameStorageView then
                            if GameStorageView.IsLoaded(container) then
                                storageFolder = GameStorageView.Get(container)
                            elseif AddPlayerToStorageRemote then
                                if not StorageFetchCooldown[container] or (now - StorageFetchCooldown[container]) > 2.5 then
                                    StorageFetchCooldown[container] = now
                                    pcall(function()
                                        AddPlayerToStorageRemote:FireServer(container)
                                    end)
                                end
                            end
                        end
                        if storageFolder then
                            TryQuickLootContainerSlots(storageFolder)
                        end
                    end
                end
            end
        end)
        task.wait(0.16)
    end
end)

-- ==============================================================================
-- [11] ULTRA-LIGHTWEIGHT ESP RENDERER
-- ==============================================================================
local ESPPool = {}

local function CreateESPItem(key, isPlayerOrBot)
    local container = Instance.new("Frame")
    container.Name = "ESP_Item"
    container.BackgroundTransparency = isPlayerOrBot and 1 or 0.15
    container.BorderSizePixel = 0
    container.Visible = false
    container.Parent = OverlayGui

    local boxStroke = nil
    if isPlayerOrBot then
        boxStroke = Instance.new("UIStroke")
        boxStroke.Thickness = 1.3
        boxStroke.Parent = container
    else
        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = container
    end

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(0, 260, 0, 56)
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 0, -3)
    label.Font = Enum.Font.RobotoMono
    label.TextSize = 13
    label.TextStrokeTransparency = 0.20
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Parent = container

    ESPPool[key] = {
        Frame = container,
        Stroke = boxStroke,
        Label = label,
        LastText = "",
        LastColor = nil
    }
    return ESPPool[key]
end

local function CleanupESP(activeKeys)
    for key, item in pairs(ESPPool) do
        if not activeKeys[key] then
            if item.Frame.Visible then
                item.Frame.Visible = false
            end
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
    local myRoot = FindBasePartChild(myChar, "HumanoidRootPart")
    local refPos = (myRoot and myRoot.Position) or Camera.CFrame.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = GetPlayerCharacter(player)
            local root = FindBasePartChild(char, "HumanoidRootPart")
            if root then GetTargetVelocity(char, root) end
        end
    end

    if Config.ESP_Players then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = GetPlayerCharacter(player)
                local root = FindBasePartChild(char, "HumanoidRootPart")
                local head = FindBasePartChild(char, "Head")
                local hp = GetCharacterHealth(char)

                if root and head and hp > 0 then
                    local dist = (root.Position - refPos).Magnitude
                    if dist <= Config.PlayerRenderDistance then
                        local topPos, onScreenTop = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, 1.2, 0))
                        local botPos, onScreenBot = Camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

                        if onScreenTop or onScreenBot then
                            activeKeys[player] = true
                            local esp = ESPPool[player] or CreateESPItem(player, true)
                            local isTeam = IsTeammate(player)
                            local color = isTeam and Color3.fromRGB(60, 255, 100) or Color3.fromRGB(255, 65, 65)

                            local height = math.abs(botPos.Y - topPos.Y)
                            local width = height * 0.6
                            local weapon = CachedPlayerWeapon[char] or "Unarmed"

                            esp.Frame.Size = UDim2.fromOffset(width, height)
                            esp.Frame.Position = UDim2.fromOffset(topPos.X - width / 2, topPos.Y)

                            if esp.LastColor ~= color then
                                esp.LastColor = color
                                if esp.Stroke then esp.Stroke.Color = color end
                                esp.Label.TextColor3 = color
                            end

                            local distInt = math.floor(dist / 2) * 2
                            local newText = string.format(
                                "%s [%d HP]\nถือ: %s (%d m)",
                                player.Name,
                                math.floor(hp),
                                weapon,
                                distInt
                            )
                            if esp.LastText ~= newText then
                                esp.LastText = newText
                                esp.Label.Text = newText
                            end
                            esp.Frame.Visible = true
                        end
                    end
                end
            end
        end
    end

    for _, data in ipairs(VisibleTrackedObjects) do
        local obj = data.Key
        local part = data.Part
        if obj and obj.Parent and part and part.Parent and part:IsA("BasePart") then
            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen and screenPos.Z > 0 then
                activeKeys[obj] = true
                local isBot = (data.Category == "Scientist")
                local esp = ESPPool[obj] or CreateESPItem(obj, isBot)

                local dotSize = isBot and 24 or 7
                esp.Frame.Size = UDim2.fromOffset(dotSize, dotSize)
                esp.Frame.Position = UDim2.fromOffset(screenPos.X - dotSize / 2, screenPos.Y - dotSize / 2)

                if esp.LastColor ~= data.Color then
                    esp.LastColor = data.Color
                    if esp.Stroke then
                        esp.Stroke.Color = data.Color
                    else
                        esp.Frame.BackgroundColor3 = data.Color
                    end
                    esp.Label.TextColor3 = data.Color
                end

                local distInt = math.floor((part.Position - refPos).Magnitude / 2) * 2
                local newText = string.format("%s (%d m)%s", data.Title, distInt, data.CachedSub or "")
                if esp.LastText ~= newText then
                    esp.LastText = newText
                    esp.Label.Text = newText
                end
                esp.Frame.Visible = true
            end
        end
    end

    CleanupESP(activeKeys)
end))

-- ==============================================================================
-- [12] FLUENT UI SETUP (TeteKubb Hub V14.1) & KEYBIND HANDLER
-- ==============================================================================
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()

local Window = Fluent:CreateWindow({
    Title = "TeteKubb Hub V14.1",
    SubTitle = "Fixed Lighthouse Bug + Auto-Loot Vacuum + Inspector",
    TabWidth = 155,
    Size = UDim2.fromOffset(640, 520),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Combat = Window:AddTab({ Title = "Aimbot & เช็คของคน", Icon = "crosshair" }),
    PlayerBaseESP = Window:AddTab({ Title = "ESP คน & ตู้ TC", Icon = "users" }),
    ResourceESP = Window:AddTab({ Title = "ดูดของ & แร่/หญ้า", Icon = "pickaxe" }),
    LootESP = Window:AddTab({ Title = "ESP กล่อง & ตั้งค่าลื่น", Icon = "box" }),
}

local function ReadToggleVal(val, toggleObj)
    if type(val) == "boolean" then return val end
    if toggleObj and type(toggleObj.Value) == "boolean" then return toggleObj.Value end
    return false
end

-- ------------------------------------------------------------------------------
-- TAB 1: PRO AIMBOT & TARGET INSPECTOR
-- ------------------------------------------------------------------------------
local AimToggle = Tabs.Combat:AddToggle("AimToggle", {
    Title = "เปิดใช้งาน Aimbot ล็อคเป้า (ปุ่มลัด: X)",
    Description = "ล็อคหัว/ตัวนิ่งสนิททั้งในคอมและมือถือ พร้อมคำนวณดักทางคนวิ่ง",
    Default = false
})
AimToggle:OnChanged(function(val)
    Config.AimlockEnabled = ReadToggleVal(val, AimToggle)
end)

local TargetInvToggle = Tabs.Combat:AddToggle("TargetInvToggle", {
    Title = "โชว์ของในตัวผู้เล่นที่ล็อคเป้า (Target Loadout & Armor HUD)",
    Description = "ล็อคใครโชว์ปืนที่ถือ ของแต่งปืน อาวุธในตัวที่ตรวจพบ และชุดเกราะของคนนั้นทันที",
    Default = true
})
TargetInvToggle:OnChanged(function(val)
    Config.ShowTargetInventory = ReadToggleVal(val, TargetInvToggle)
    if not Config.ShowTargetInventory then
        TargetInspectorFrame.Visible = false
    end
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
    Description = "0.50 = นิ่งสมูทเหมือนมือถือ | 0.85 = เกาะติดหัวไวมาก",
    Default = 0.50,
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
    Default = 1.05,
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
    Title = "ล็อคบอทนักวิทยาศาสตร์ด้วย (Lock Scientists)",
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
-- TAB 2: FULLBRIGHT & ESP ผู้เล่น / ตู้ TC / เตียง / กับดัก
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

local T_Players = Tabs.PlayerBaseESP:AddToggle("T_Players", {
    Title = "ESP ผู้เล่นออนไลน์ (ชื่อ + เลือด + ปืนที่ถือ)",
    Default = false
})
T_Players:OnChanged(function(val) Config.ESP_Players = ReadToggleVal(val, T_Players) end)

local T_TC = Tabs.PlayerBaseESP:AddToggle("T_TC", {
    Title = "ESP ตู้ TC / ตู้ฐานบ้าน (Base Claim + ชื่อเจ้าของ + ของข้างใน)",
    Default = false
})
T_TC:OnChanged(function(val) Config.ESP_TC = ReadToggleVal(val, T_TC) end)

local T_BaseOwner = Tabs.PlayerBaseESP:AddToggle("T_BaseOwner", {
    Title = "ESP เตียงนอนผู้เล่น (Sleeping Bag + ชื่อเจ้าของ)",
    Default = false
})
T_BaseOwner:OnChanged(function(val) Config.ESP_BaseOwner = ReadToggleVal(val, T_BaseOwner) end)

local T_Scientists = Tabs.PlayerBaseESP:AddToggle("T_Scientists", {
    Title = "ESP บอทนักวิทยาศาสตร์ (Road / Monument Scientist)",
    Default = false
})
T_Scientists:OnChanged(function(val) Config.ESP_Scientists = ReadToggleVal(val, T_Scientists) end)

local T_Sleepers = Tabs.PlayerBaseESP:AddToggle("T_Sleepers", {
    Title = "ESP คนนอนออฟไลน์ (Sleeper + เช็คของในตัว)",
    Default = false
})
T_Sleepers:OnChanged(function(val) Config.ESP_Sleepers = ReadToggleVal(val, T_Sleepers) end)

local T_BodyBags = Tabs.PlayerBaseESP:AddToggle("T_BodyBags", {
    Title = "ESP ถุงศพคนตาย (BodyBag + เช็คของในถุง)",
    Default = false
})
T_BodyBags:OnChanged(function(val) Config.ESP_BodyBags = ReadToggleVal(val, T_BodyBags) end)

local T_Traps = Tabs.PlayerBaseESP:AddToggle("T_Traps", {
    Title = "ESP กับดักในบ้าน (Shotgun Trap / Flame Turret)",
    Default = false
})
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
-- TAB 3: AUTO-LOOT VACUUM (ดูดของ), AUTO SPARK & ESP แร่ + ผืนหญ้า
-- ------------------------------------------------------------------------------
local AutoPickupToggle = Tabs.ResourceESP:AddToggle("AutoPickupToggle", {
    Title = "ดูดของตกพื้น & ผืนหญ้ารอบตัวอัตโนมัติ (Ground Item Vacuum)",
    Description = "ดูดไอเทมที่ดรอปบนพื้น ผืนหญ้า/ต้นผ้า เห็ด และแอปเปิ้ลรอบตัวเข้ากระเป๋าทันที",
    Default = false
})
AutoPickupToggle:OnChanged(function(val) Config.AutoPickupEnabled = ReadToggleVal(val, AutoPickupToggle) end)

local AutoLootOpenToggle = Tabs.ResourceESP:AddToggle("AutoLootOpenToggle", {
    Title = "ดูดของในกล่อง/ถุงศพทันทีที่กดเปิด (Instant Open-Crate Vacuum)",
    Description = "พอกดเปิดกล่อง ถุงศพ หรือเตาเผาปุ๊บ จะกวาดของเข้าตัวอัตโนมัติในพริบตา",
    Default = false
})
AutoLootOpenToggle:OnChanged(function(val) Config.AutoLootOpenContainer = ReadToggleVal(val, AutoLootOpenToggle) end)

local AutoLootNearbyToggle = Tabs.ResourceESP:AddToggle("AutoLootNearbyToggle", {
    Title = "ดูดของจากกล่อง & ถุงศพรอบตัวโดยไม่ต้องกดเปิดเอง (Remote Crate Vacuum)",
    Description = "แค่เดินผ่านกล่องดรอป กล่องไม้ไม่ล็อก หรือถุงศพ จะดึงของข้างในเข้าตัวอัตโนมัติ",
    Default = false
})
AutoLootNearbyToggle:OnChanged(function(val) Config.AutoLootNearbyContainers = ReadToggleVal(val, AutoLootNearbyToggle) end)

local LootFilterDropdown = Tabs.ResourceESP:AddDropdown("LootFilterDropdown", {
    Title = "โหมดคัดกรองของที่จะดูด (Loot Filter)",
    Values = { "All", "Valuables" },
    Default = "All",
})
LootFilterDropdown:OnChanged(function(val) Config.LootFilterMode = val end)

Tabs.ResourceESP:AddSlider("PickupRangeSlider", {
    Title = "ระยะดูดของรอบตัวอัตโนมัติ (Studs)",
    Default = 14,
    Min = 5,
    Max = 22,
    Rounding = 0,
    Callback = function(val) Config.AutoPickupRange = val end
})

local AutoSparkToggle = Tabs.ResourceESP:AddToggle("AutoSparkToggle", {
    Title = "หันกล้องตีจุด Spark ของแร่อัตโนมัติ (Auto-Hit Ore Spark)",
    Default = false
})
AutoSparkToggle:OnChanged(function(val) Config.AutoSparkEnabled = ReadToggleVal(val, AutoSparkToggle) end)

local T_GrassCloth = Tabs.ResourceESP:AddToggle("T_GrassCloth", {
    Title = "ESP ผืนหญ้า / ต้นผ้า & ของป่า (Grass / Cloth / Hemp)",
    Default = false
})
T_GrassCloth:OnChanged(function(val) Config.ESP_GrassCloth = ReadToggleVal(val, T_GrassCloth) end)

local T_HideGrass = Tabs.ResourceESP:AddToggle("T_HideGrass", {
    Title = "ซ่อนหญ้า 3D บนพื้นแมพ (Remove Terrain Grass)",
    Default = false
})
T_HideGrass:OnChanged(function(val)
    Config.HideTerrainGrass = ReadToggleVal(val, T_HideGrass)
    ApplyTerrainGrassState(Config.HideTerrainGrass)
end)

local T_Stone = Tabs.ResourceESP:AddToggle("T_Stone", {
    Title = "ESP แร่หิน (Stone Ore)",
    Default = false
})
T_Stone:OnChanged(function(val) Config.ESP_StoneOre = ReadToggleVal(val, T_Stone) end)

local T_Metal = Tabs.ResourceESP:AddToggle("T_Metal", {
    Title = "ESP แร่เหล็ก (Metal Ore)",
    Default = false
})
T_Metal:OnChanged(function(val) Config.ESP_MetalOre = ReadToggleVal(val, T_Metal) end)

local T_Sulfur = Tabs.ResourceESP:AddToggle("T_Sulfur", {
    Title = "ESP แร่กำมะถัน (Sulfur Ore)",
    Default = false
})
T_Sulfur:OnChanged(function(val) Config.ESP_SulfurOre = ReadToggleVal(val, T_Sulfur) end)

-- ------------------------------------------------------------------------------
-- TAB 4: CRATE INSPECTOR, ESP กล่อง & ตั้งค่าความลื่น (ANTI-LAG)
-- ------------------------------------------------------------------------------
local T_ShowContents = Tabs.LootESP:AddToggle("T_ShowContents", {
    Title = "แสดงรายชื่อไอเทมข้างในกล่อง & ตู้ TC บน ESP (Crate Item Checker)",
    Default = true
})
T_ShowContents:OnChanged(function(val) Config.ShowCrateContents = ReadToggleVal(val, T_ShowContents) end)

local T_AutoFetchStorage = Tabs.LootESP:AddToggle("T_AutoFetchStorage", {
    Title = "ซิงค์ดูของในกล่องระยะใกล้โดยไม่ต้องกดเปิดเอง (Auto-Fetch Storage)",
    Default = false
})
T_AutoFetchStorage:OnChanged(function(val) Config.AutoFetchStorage = ReadToggleVal(val, T_AutoFetchStorage) end)

local T_Storage = Tabs.LootESP:AddToggle("T_Storage", {
    Title = "ESP กล่องเก็บของในบ้าน & เตาเผา (Wooden Crate / Stash / Furnace)",
    Default = false
})
T_Storage:OnChanged(function(val) Config.ESP_Storage = ReadToggleVal(val, T_Storage) end)

local T_UnlockedOnly = Tabs.LootESP:AddToggle("T_UnlockedOnly", {
    Title = "กรองเฉพาะกล่องบ้านที่ไม่ได้ล็อก (Unlocked Only)",
    Default = false
})
T_UnlockedOnly:OnChanged(function(val) Config.ESP_OnlyUnlockedStorage = ReadToggleVal(val, T_UnlockedOnly) end)

local T_MilitaryCrates = Tabs.LootESP:AddToggle("T_MilitaryCrates", {
    Title = "ESP กล่องทหาร (Military Crate)",
    Default = false
})
T_MilitaryCrates:OnChanged(function(val) Config.ESP_MilitaryCrates = ReadToggleVal(val, T_MilitaryCrates) end)

local T_LootCrates = Tabs.LootESP:AddToggle("T_LootCrates", {
    Title = "ESP กล่องดรอปที่เก็บของได้ & แอร์ดรอป (Crate / Supply Drop / Locked Crate)",
    Default = false
})
T_LootCrates:OnChanged(function(val) Config.ESP_LootCrates = ReadToggleVal(val, T_LootCrates) end)

local T_Barrels = Tabs.LootESP:AddToggle("T_Barrels", {
    Title = "ESP ถังเหล็ก (Barrel)",
    Default = false
})
T_Barrels:OnChanged(function(val) Config.ESP_Barrels = ReadToggleVal(val, T_Barrels) end)

local T_FuelBarrels = Tabs.LootESP:AddToggle("T_FuelBarrels", {
    Title = "ESP ถังแก๊ส / ถังน้ำมัน (Fuel Barrel)",
    Default = false
})
T_FuelBarrels:OnChanged(function(val) Config.ESP_FuelBarrels = ReadToggleVal(val, T_FuelBarrels) end)

local T_Dropped = Tabs.LootESP:AddToggle("T_Dropped", {
    Title = "ESP ของและอาวุธที่ดรอปบนพื้น (Dropped Items)",
    Default = false
})
T_Dropped:OnChanged(function(val) Config.ESP_DroppedItems = ReadToggleVal(val, T_Dropped) end)

Tabs.LootESP:AddSlider("MaxESPCountSlider", {
    Title = "จำกัดจำนวนป้าย ESP สูงสุดบนจอ (แก้แล็ค 100%)",
    Description = "แสดงเฉพาะของที่อยู่ใกล้ตัวที่สุดตามจำนวนนี้ ยิ่งน้อยยิ่งลื่น",
    Default = 45,
    Min = 15,
    Max = 120,
    Rounding = 0,
    Callback = function(val) Config.MaxWorldESPCount = val end
})

Tabs.LootESP:AddSlider("WorldDistSlider", {
    Title = "ระยะมองเห็นกล่อง ถัง และสิ่งของสูงสุด (Studs)",
    Default = 650,
    Min = 100,
    Max = 2000,
    Rounding = 0,
    Callback = function(val) Config.WorldRenderDistance = val end
})

-- ==============================================================================
-- [ระบบปุ่มลัดคีย์บอร์ด X / V / B]
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
            Title = "สลับจุดล็อค (ปุ่ม V)",
            Content = "เปลี่ยนจุดล็อคเป็น: " .. nextMode,
            Duration = 1.5
        })
    elseif input.KeyCode == Config.Key_ToggleFullbright then
        FullbrightToggle:SetValue(not Config.FullbrightEnabled)
        Fluent:Notify({
            Title = "Fullbright (ปุ่ม B)",
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
QuickLockBtn.Text = "LOCK"
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
    pcall(function() ApplyTerrainGrassState(false) end)
    if OverlayGui and OverlayGui.Parent then
        pcall(function() OverlayGui:Destroy() end)
    end
end

Window:SelectTab(1)
