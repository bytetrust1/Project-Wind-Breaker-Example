local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Geting the services

-- Requiring all the packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)

local Darwin = require(ReplicatedStorage.StoragePackage.Modules.Utility.DarwinModules.DarwinUtilities) -- Module set from a friend of mine
local VLD = require(ReplicatedStorage.StoragePackage.Modules.Utility.VLDModules) -- Custom module set made by me

local Classes = ReplicatedStorage.StoragePackage.Classes -- Place where all the classes in the game is stored

local SkillService = Knit.CreateService({
    Name = "SkillService", -- Creating the Service using Knit
	Client = {
		Replicate = Knit.CreateSignal(), -- Signal to replicate VFX and other stuff for near by clients
		ReplicateEnd = Knit.CreateSignal(), -- Signal to destroy VFX or other stuff
		Event = Knit.CreateSignal(), -- Signal for custom events fired by the Skill Classes
	},
})
SkillService.__index = SkillService -- Leting skill objects access methods from SkillService
SkillService.Skills = {} -- Making a Dictionary to store Skill objects to access later

local Moves = Classes.Skills.Moves -- Place where i store all the Skill Class modules

function GetAllFolders(MoveName : string, Character : Model)
  -- Getting all the Asset folders to use in Skills makes it easier and shorter scripts in the actual skill classes
	local AnimationFolder = ReplicatedStorage.StoragePackage.Assets.Animations:FindFirstChild(MoveName, true) or ReplicatedStorage.StoragePackage.Assets.Animations.Base
	local VFXFolder = ReplicatedStorage.StoragePackage.Assets.VFX:FindFirstChild(MoveName, true) or ReplicatedStorage.StoragePackage.Assets.VFX.Base
	local SFXFolder = ReplicatedStorage.StoragePackage.Assets.SFX:FindFirstChild(MoveName, true) or ReplicatedStorage.StoragePackage.Assets.SFX.Base

	return AnimationFolder, VFXFolder, SFXFolder -- Returning all the Folders
end

function Makelibs(Character : Model, MoveName : string, ...)
	local AnimationFolder, VFXFolder, SFXFolder = GetAllFolders(MoveName, Character) -- Getting all the asset folders
	
	local Wraper, Skill = unpack(...) -- unpacking the last parameter to return

	return {
		AnimationFolder = AnimationFolder,
		VFXFolder = VFXFolder,
		SFXFolder = SFXFolder,
		Darwin = Darwin,
		VLD = VLD,
		Character = Character,
		Skill = Skill,
		Wraper = Wraper,
	} -- Returning all the useful Modules and Asset folders
end

function SkillService.new(Params : {Character : Model, SkillName : string})
	if not Params then return end -- Check if the params are empty
	
	--print("Creating skill: ", Params.SkillName)
	
	if not Classes.Skills:FindFirstChild(Params.SkillName, true) then -- Check if the SkillName has a Skill Class module
		warn("Skill not found: "..Params.SkillName)
		return
	end
	
	local self = setmetatable({}, SkillService) -- Making a new Skill class and letting it access the SkillService methods
	
	self.Services = Knit.GetServices() -- Gets all the Services using Knit
	
	self.Character = Params.Character -- Setting Character to the Params Character
	self.Name = Params.SkillName -- Setting SkillName to the Params SkillName
	self.Wraper = self.Services.CharacterService:GetCharacter(self.Character) -- Gets the Character Wraper using CharacterService I created
	self.ActualSkill = require(Classes.Skills:FindFirstChild(self.Name, true)) -- Requiring the Skill class module
	
	self.State = "Idle" -- Setting the state to "Idle" so it's free to start
	
	self.libs = Makelibs(self.Character, self.Name, {self.Wraper, self}) -- Getting all the Useful modules using the Makelibs function
	
	if SkillService.Skills[self.Character] then -- Check if the Character already in the Skills Dictionary
		SkillService.Skills[self.Character][self.Name] = self -- if so add the Skill Class under SkillName under Character
	else
		--print(SkillService.Skills, self.Character, self.Name, self)
		SkillService.Skills[self.Character] = {[self.Name] = self} -- If Character not in the Skills then I add the character and the skill class to Skills
	end
	
	self._trove = Trove.new() -- Creating a Trove for clean up later
	
	self.Wraper:AddSkill(self.Name, self) -- Adds the skill to the Character Wraper
	
	return self -- Returning the skill class to run any methods
end

function SkillService:Start(Players : {Player})
	if not Players then return end -- Check if Players Exist
	if self.State ~= "Idle" then return end -- Check if the State is Idle
	if self.Wraper.ActiveSkill then return end -- Check the Character Wraper to see if the Skill is the ActiveSkill in it if so return end
	
	self.State = "Active" -- Change the State to Active
	
	self.FramesObject = self.ActualSkill.StartServer(self.libs) -- 
	self.Wraper:SetActiveSkill(self.Name, true)
	
	self:_ArmRelease()
	
	for _,v in Players do
		self.Client.Replicate:Fire(v, self.Character, self.Name)
	end
end

--// A move hands itself back by calling Stop at the end of its frame chain. Those frames run
--// as promises, so anything that throws on the way there -- an Animation with no asset id, a
--// hitbox that errors, the character being replaced mid-move -- rejects quietly and Stop is
--// never reached. Without this the skill sits Active for the rest of the round, and because
--// it still holds ActiveSkill it takes every other skill on the character down with it: one
--// use and nothing works again, cooldown or no cooldown.
function SkillService:_ArmRelease()
	--// only the moves. Block and the other held skills stay Active by design.
	if Classes.Skills:FindFirstChild(self.Name, true).Parent ~= Moves then return end
	
	self._trove:AddPromise(Promise.delay(10):andThen(function()
		if self.Wraper.ActiveSkill ~= self.Name then return end
		
		warn("[SkillService] "..self.Name.." skill never stoped on it's own... Promise error above.")
		self:Stop()
	end))
end

function SkillService:Stop()
	if not (self.State == "Cooldown") then
		self.State = "Idle"
	end
	
	if self.FramesObject then
		self.FramesObject:Destroy()
		self.FramesObject = nil
	end
	
	--// Handing the character back comes first and unconditionally. This used to sit at the
	--// bottom, below a loop that indexes HumanoidRootPart -- so a character that died or
	--// respawned mid-move threw on the way past and never got released, and ActiveSkill
	--// stayed set for good.
	self.Wraper:SetActiveSkill(self.Name, false)
	
	local Root = self.Character and self.Character:FindFirstChild("HumanoidRootPart")
	if not Root then return end
	
	for _,v in VLD.Players:GetPlayersInRange(Root, 1000) do
		self.Client.ReplicateEnd:Fire(v, self.Character, self.Name)
	end
end

function SkillService:ApplyCooldown(Duration : number)
	if not Duration then return end
	
	self.State = "Cooldown"
	self._trove:AddPromise(Promise.delay(Duration):andThen(function()
		self.State = "Idle"
	end))
end

function SkillService:FireClient(Params : {any}?)
	local Players = VLD.Players:GetPlayersInRange(self.Character.HumanoidRootPart, 1000)
	for _,v in Players do
		self.Client.Event:Fire(v, self.Character, self.Name, Params)
	end
end

function SkillService:UpdateCharacter(Character : Model)
	if not Character then return end
	
	self.Character = Character
	self.Wraper = self.Services.CharacterService:GetCharacter(self.Character)
	
	self.libs.Character = self.Character
	self.libs.Wraper = self.Wraper
	
	self.Wraper:AddSkill(self.Name, self)
end

function SkillService:Destroy()
	self.Wraper:RemoveSkill(self.Name)

	self.State = "Idle"

	if self.FramesObject then
		self.FramesObject:Destroy()
	end

	self._trove:Clean()

	if SkillService.Skills[self.Character] then
		SkillService.Skills[self.Character][self.Name] = nil
		if not next(SkillService.Skills[self.Character]) then
			SkillService.Skills[self.Character] = nil
		end
	end
end

function SkillService:AddMoveset(Moveset : {}, Character : Model)
	for _,v in Moveset do
		SkillService.new({Character = Character, SkillName = v})
	end
end

function SkillService:OnCharacterInit(Character : Model)
	if SkillService.Skills[Character] then
		for _,v in SkillService.Skills[Character] do
			v:UpdateCharacter(Character)
		end
	end
end

function SkillService:KnitStart()
	self.Services = Knit.GetServices()
end

return SkillService
