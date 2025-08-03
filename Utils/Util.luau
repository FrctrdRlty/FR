if not LoadCustomAsset then
    loadstring(game:HttpGet("https://raw.githubusercontent.com/RegularVynixu/Utilities/main/Functions.lua"))()
end

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer
local localCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()
local localRoot = localCharacter:WaitForChild("HumanoidRootPart")
local localPlayerGui = localPlayer:WaitForChild("PlayerGui")
local mainUI = localPlayerGui:WaitForChild("MainUI")

local Modules = {
    Main_Game = require(mainUI.Initiator.Main_Game)
}

local CurrentRoomIndex = 1
local CameraLocked = false
local CamLockTarget: BasePart | CFrame?

local fadeFrame = Instance.new("Frame")
fadeFrame.Name = "FadeFrame"
fadeFrame.Size = UDim2.new(1, 0, 1, 0)
fadeFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.ZIndex = 99998
fadeFrame.Parent = mainUI

return function(FR: any): any
    local Signal = Require(FR.Utils.."/Signal.luau")

    local Util = {
        Connections = {},
        Signals = {
            Trigger = Signal.new()
        }
    }

    Util.Connections.CharacterAdded = localPlayer.CharacterAdded:Connect(function(character: Model)
        localCharacter = character
        localRoot = character:WaitForChild("HumanoidRootPart")
    end)

    Util.LoadAsset = function(self, sAsset: string): any?
        return LoadCustomAsset(`{FR.Assets}/{sAsset}`)
    end

    Util.LoadInstance = function(self, sAsset: string): any?
        return LoadCustomInstance(`{FR.Assets}/{sAsset}`)
    end

    Util.Caption = function(self, sText: string, iDuration: number?, textColor: Color3?): TextLabel
        for _, v in next, mainUI.MainFrame:GetChildren() do
            if v.Name == "LiveCaption" then
                v:Destroy()
            end
        end

        local c = mainUI.MainFrame.Caption:Clone()
        c.Name = "LiveCaption"
        c.Visible = true
        c.Text = sText
        if textColor then
            c.TextColor3 = textColor
        end
        c.Parent = mainUI.MainFrame

        local info = TweenInfo.new(iDuration or 7, Enum.EasingStyle.Exponential, Enum.EasingDirection.In)
        TweenService:Create(c, info, {
            TextTransparency = 1,
            TextStrokeTransparency = 2
        }):Play()
        task.delay(info.Time, c.Destroy, c)

        return c
    end

    Util.Fade = function(self, tweenInfo: TweenInfo, transparency: number)
        local tween = TweenService:Create(fadeFrame, tweenInfo, { BackgroundTransparency = transparency })
        tween:Play()
        tween.Completed:Wait()
    end

    Util.Teleport = function(self, target: BasePart | CFrame)
        localCharacter:PivotTo( typeof(target) == "Instance" and target.CFrame or target )
        if typeof(target) == "Instance" then
            Modules.Main_Game.ax_t = target.Orientation.Y
            Modules.Main_Game.ay_t = target.Orientation.X
        end
    end

    Util.OnTrigger = function(self, sTrigger: string, callback: () -> (), ...: any)
        assert(typeof(callback) == "function", "Callback must be a function")
        local args = {...}
        local con; con = self.Signals.Trigger:Connect(function(trigger: string)
            if trigger == sTrigger then
                con:Disconnect()
                callback(unpack(args))
            end
        end)
        self.Connections["Trigger_"..sTrigger] = con
    end

    Util.SetupRoom = function(self, pRoom: string | Model, pivot: CFrame): Model
        local room: Model?;
        if typeof(pRoom) == "Instance" and pRoom:IsA("Model") then
            room = pRoom
        else
            if pRoom:sub(-5) ~= ".rbxm" then
                pRoom ..= ".rbxm"
            end
            room = self:LoadInstance("/Rooms/"..pRoom)
        end
        if not room then
            error("Failed to load room: "..tostring(pRoom))
        end

        local roomsFolder = self.MainFolder:FindFirstChild("Rooms")
        local assets = room:FindFirstChild("Assets")
        local door = room:FindFirstChild("Door")

        room:PivotTo(pivot or CFrame.new())
        room.Name = CurrentRoomIndex

        if assets then
            -- TerrainWater
            for _, bp in next, assets:GetChildren() do
                if bp:IsA("BasePart") and bp.Name == "TerrainWater" then
                    workspace.Terrain:FillBlock(bp.CFrame, bp.Size, Enum.Material.Water)
                end
            end
        end

        if door and door:FindFirstChild("Sign") then
            -- Duped door signs
            local sign = door.Sign
            sign.Duped.Visible = true
            sign.Duped.ImageTransparency = 0

            for _, v in next, sign:GetDescendants() do
                if v:IsA("TextLabel") then
                    v.Visible = false
                end
            end
        end

        room.Parent = roomsFolder
        CurrentRoomIndex += 1

        -- Triggers
        local triggers = room:FindFirstChild("Triggers")
        if triggers then
            for _, trigger in next, triggers:GetChildren() do
                if trigger:IsA("BasePart") then
                    local con; con = trigger.Touched:Connect(function(hit: BasePart)
                        if hit:IsDescendantOf(localCharacter) then
                            con:Disconnect()
                            self.Signals.Trigger:Fire(trigger.Name)
                        end
                    end)
                end
            end
        end

        -- Unload rooms
        for _, v in next, roomsFolder:GetChildren() do
            if v:GetAttribute("Unloaded") then
                v:Destroy()
            end
        end

        if #roomsFolder:GetChildren() > 2 then
            self:UnloadRoom(roomsFolder:GetChildren()[1])
        end

        return room
    end

    Util.UnloadRoom = function(self, room: Model)
        room:SetAttribute("Unloaded", true)

        local door: Model;
        local parts = {}
        for _, v in next, room:GetChildren() do
            if not door and v:IsA("Model") and v.Name:find("Door") then
                door = v
            else
                parts[#parts + 1] = v
            end
        end
        if door then
            self:CloseDoor(door)
        end

        task.delay(3, function()
            local assets = room:FindFirstChild("Assets")
            if assets then
                -- Remove TerrainWater
                for _, bp in next, assets:GetChildren() do
                    if bp:IsA("BasePart") and bp.Name == "TerrainWater" then
                        workspace.Terrain:FillBlock(bp.CFrame, bp.Size, Enum.Material.Air)
                    end
                end
            end
            
            for _, v in next, parts do
                v:Destroy()
            end
        end)
    end

    Util.OpenDoor = function(self, doorModel: Model)
        local collision = doorModel:FindFirstChild("Collision")
        local hingeConstraint = doorModel:FindFirstChild("HingeConstraint")
        local door = doorModel:FindFirstChild("Door")

        if doorModel:FindFirstChild("Hidden") then
            doorModel.Hidden.Transparency = 1
        end
        if collision then
            collision.CanCollide = false
        end
        if hingeConstraint then
            hingeConstraint.TargetAngle = hingeConstraint.LowerAngle
            hingeConstraint.ServoMaxTorque = 9999
        end
        if door then
            door.CanCollide = false
            door.Anchored = false
            door.Open:Play()
        end
    end

    Util.CloseDoor = function(self, doorModel: Model)
        local collision = doorModel:FindFirstChild("Collision")
        local hingeConstraint = doorModel:FindFirstChild("HingeConstraint")

        if collision then
            collision.CanCollide = true
        end
        if hingeConstraint then
            hingeConstraint.TargetAngle = 0
            hingeConstraint.ServoMaxTorque = 9999
        end
    end

    Util.WaitOnDoor = function(self, doorModel: Model, iDistance: number?)
        assert(doorModel.PrimaryPart, "Door model must have a PrimaryPart set.")
        local distance = iDistance or 12
        repeat task.wait() until (doorModel.PrimaryPart.Position - localRoot.Position).Magnitude <= distance
    end

    Util.SetLighting = function(self, sLighting: string, properties: any)
        Lighting:ClearAllChildren()

        local iLighting = self:LoadInstance(sLighting)
        if iLighting then
            for _, v in next, iLighting:GetChildren() do
                v.Parent = Lighting
            end
            iLighting:Destroy()
        else
            warn("Failed to load lighting: "..tostring(sLighting))
        end

        for i, v in next, properties do
            Lighting[i] = v
        end
    end

    Util.CreateFakeCharacter = function(self, character: Model): Model
        character.Archivable = true

        local fakeCharacter = character:Clone()
        fakeCharacter.Name = "FakeCharacter"

        for _, v in next, fakeCharacter:GetDescendants() do
            if v:IsA("Accessory") then
                local at = v.AccessoryType
                if at == Enum.AccessoryType.Hat
                or at == Enum.AccessoryType.Hair
                or at == Enum.AccessoryType.Face
                or at == Enum.AccessoryType.Neck then
                    v:Destroy()
                end
            elseif v:IsA("Tool") then
                v:Destroy()
            end
        end

        return fakeCharacter
    end

    Util.LockCamera = function(self, target: BasePart | CFrame)
        CameraLocked = true
        CamLockTarget = target
        Modules.Main_Game.disableMovement = true
        Modules.Main_Game.ax_t = 0
        Modules.Main_Game.ay_t = 0
    end

    Util.UnlockCamera = function(self)
        CameraLocked = false
        CamLockTarget = nil
        Modules.Main_Game.disableMovement = false
    end

    Util.AnimatePlayer = function(self, character: Model, animResolvable: KeyframeSequence | Animation | number | string): (any?, Model?)
        localRoot.Anchored = true

        local oldCFrame = localRoot.CFrame
        local oldX = Modules.Main_Game.ax_t
        local oldY = Modules.Main_Game.ay_t

        local fakeCharacter = self:CreateFakeCharacter(character)
        local fakeHead = fakeCharacter:WaitForChild("Head")
        fakeCharacter:PivotTo(oldCFrame)
        fakeCharacter.Parent = self.MainFolder

        Modules.Main_Game.ax_t = 0
        Modules.Main_Game.ay_t = 0
        self:LockCamera(fakeHead)

        localCharacter:PivotTo(CFrame.new(0, -1000, 0))

        local baseMotors = HttpService:JSONDecode(readfile(FR.Root.."/BaseMotors.json"))
        for i, v in next, fakeCharacter:GetDescendants() do
            if v:IsA("Motor6D") then
                local data = baseMotors[v.Name]
                if data then
                    v.C0 = CFrame.new(unpack(data.C0))
                    v.C1 = CFrame.new(unpack(data.C1))
                end
            end
        end

        local anim = Animator.new(fakeCharacter, animResolvable)
        if anim then
            anim.Completed = Signal.new()
            anim:Play()

            task.spawn(function()
                anim.Stopped:Wait()
                fakeCharacter:Destroy()
                localCharacter:PivotTo(oldCFrame)
                localRoot.Anchored = false
                Modules.Main_Game.ax_t = oldX
                Modules.Main_Game.ay_t = oldY
                self:UnlockCamera()
                anim.Completed:Fire()
            end)
        else
            warn("Failed to load animation: "..tostring(animResolvable))
            return
        end

        return anim, fakeCharacter
    end

    Util.Unload = function(self)
        for i, v in next, self.Connections do
            v:Disconnect()
            self.Connections[i] = nil
        end
        for i, v in next, self do
            self[i] = nil
        end
    end

    -- Main folder setup
    local mainFolder = Util:LoadInstance("MainFolder.rbxm")
    mainFolder.Parent = workspace
    Util.MainFolder = mainFolder

    if not Animator then
        loadstring(game:HttpGet("https://raw.githubusercontent.com/RegularVynixu/Animator/main/Source/Main.lua"))()
    end

    -- Base camera lock
    setmetatable(Modules.Main_Game, {
        __index = function(t, k)
            if CameraLocked and CamLockTarget and k == "transitionCam" then
                local to = typeof(CamLockTarget)
                local cf =
                    (to == "Instance" and CamLockTarget.CFrame)
                    or (to == "CFrame" and CamLockTarget)
                    or CFrame.new()
                    
                t.basecamcf = cf
            end
            return rawget(t, k)
        end
    })

    return Util, mainFolder

end
