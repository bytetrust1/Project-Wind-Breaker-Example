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
		Replicate = Knit.CreateSignal(), -- Signal to replicate VFX and other stuff
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
	
	self.FramesObject = self.ActualSkill.StartServer(self.libs) -- Starting the ServerStart method in the Skill Class Module
	self.Wraper:SetActiveSkill(self.Name, true) -- Setting the Active skill in the wraper
	
	self:_ArmRelease() -- Release all other skills attached to the character
	
	local Root = self.Character and self.Character:FindFirstChild("HumanoidRootPart") -- Gets the HumanoidRootPart of the character
	if not Root then return end -- Check if it exist
	
	for _,v in VLD.Players:GetPlayersInRange(Root, 1000) do -- Used a function in my Module set to get all the players near by
		self.Client.Replicate:Fire(v, self.Character, self.Name) -- Fire the Replicate function on each player
	end
end

function SkillService:_ArmRelease()
	if Classes.Skills:FindFirstChild(self.Name, true).Parent ~= Moves then return end -- Check if the Skill is a move type, Skills like Block and other held skills are not effected by this
	
	self._trove:AddPromise(Promise.delay(10):andThen(function() -- Making a promise to delay 10 seconds
		if self.Wraper.ActiveSkill ~= self.Name then return end -- Check if the skill is still active
		
		warn("[SkillService] "..self.Name.." skill never stoped on it's own... Promise error above.") -- Warn that the skill never stoped
		self:Stop() -- Stops the skill
	end))
end

function SkillService:Stop()
	if not (self.State == "Cooldown") then -- Checking if the Skill is not on cooldown
		self.State = "Idle" -- if so I set the State to Idle
	end
	
	if self.FramesObject then -- Check if the skill still exist
		self.FramesObject:Destroy() -- Destroy it
		self.FramesObject = nil -- Setting it to nil
	end
	
	self.Wraper:SetActiveSkill(self.Name, false) -- Setting the active skill of the Character Wraper to nil
	
	local Root = self.Character and self.Character:FindFirstChild("HumanoidRootPart") -- Gets the HumanoidRootPart of the character
	if not Root then return end -- Check if it exist
	
	for _,v in VLD.Players:GetPlayersInRange(Root, 1000) do -- Used a function in my Module set to get all the players near by
		self.Client.ReplicateEnd:Fire(v, self.Character, self.Name) -- Fire the ReplicateEnd Signal on each player
	end
end

function SkillService:ApplyCooldown(Duration : number)
	if not Duration then return end -- Checking if Duration exist
	
	self.State = "Cooldown" -- Setting the state
	self._trove:AddPromise(Promise.delay(Duration):andThen(function() -- Creating a Promise to wait the duration
		self.State = "Idle" -- Setting the state back to idle
	end))
end

function SkillService:FireClient(Params : {any}?)
	local Players = VLD.Players:GetPlayersInRange(self.Character.HumanoidRootPart, 1000) -- Getting all the player near by
	for _,v in Players do
		self.Client.Event:Fire(v, self.Character, self.Name, Params) -- Firing Event signal on each of them
	end
end

function SkillService:UpdateCharacter(Character : Model)
	if not Character then return end -- Checking if the character is provided
	
	self.Character = Character -- Setting the Character variable
	self.Wraper = self.Services.CharacterService:GetCharacter(self.Character) -- Getting the Character Wraper and setting it as the wraper
	
	self.libs.Character = self.Character -- Changing the libs Dictionary to match the updated character
	self.libs.Wraper = self.Wraper -- Same as above but with the wraper
	
	self.Wraper:AddSkill(self.Name, self) -- Adding the skill to the new character Wraper
end

function SkillService:Destroy()
	self.Wraper:RemoveSkill(self.Name) -- Remove the skill from the character wraper

	self.State = "Idle" -- Setting the state to Idle

	if self.FramesObject then -- Check if the skill class exist
		self.FramesObject:Destroy() -- If so destroy it
	end

	self._trove:Clean() -- Cleans the trove to disconnect all the connections

	if SkillService.Skills[self.Character] then -- Checks if the Character is in the Skills dictionary
		SkillService.Skills[self.Character][self.Name] = nil -- if so set the Skill to nil inside the character
		if not next(SkillService.Skills[self.Character]) then -- check if the Character dictionary is empty
			SkillService.Skills[self.Character] = nil -- if so set the whole thing to nil
		end
	end
end

function SkillService:AddMoveset(Moveset : {}, Character : Model)
	for _,v in Moveset do -- loop though all the moves in the moveset
		SkillService.new({Character = Character, SkillName = v}) -- Adding all the Skills in the moveset to the character
	end
end

function SkillService:OnCharacterInit(Character : Model)
	if SkillService.Skills[Character] then -- Check for the character model in the Skills dictionary
		for _,v in SkillService.Skills[Character] do -- Looping though all the Skills under the character
			v:UpdateCharacter(Character) -- Updating the character with the new character
		end
	end
end

function SkillService:KnitStart()
	self.Services = Knit.GetServices() -- Getting all the Services using Knit
end

return SkillService -- Returning the module
