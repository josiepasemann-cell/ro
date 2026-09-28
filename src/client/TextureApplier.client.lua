--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: TextureApplier (LocalScript)
	Responsibility:
		Fills in the image of every keyed Texture/Decal built by the model
		buildscripts (assets/models/**). Buildscripts leave Texture = "" and
		mark each instance with the attribute TextureKey = "<Key>" and the
		CollectionService tag "KeyedTexture" (convention: see
		assets/textures/README.md). This script looks the key up in
		ReplicatedStorage.TextureConfig and:
			- Id ~= ""  -> .Texture = "rbxassetid://" .. Id
			- Id == ""  -> .Transparency = 1 (not uploaded yet: show nothing
			               instead of a broken/blank image)
			- unknown key -> hidden too, plus one warning per key.

	Why client-side:
		Texture instances replicate to every client already; only the image
		property needs to be set, and that is purely cosmetic. Doing it on the
		client also covers parts that stream in later (StreamingEnabled) and
		templates that the server clones out of ReplicatedStorage, with zero
		server work and no remotes.

	Cost:
		Fully event-driven, no per-frame work. One pass over Workspace and
		ReplicatedStorage at start, then:
			- CollectionService:GetInstanceAddedSignal("KeyedTexture")
			- DescendantAdded on Workspace and ReplicatedStorage (for
			  instances that only carry the attribute); the handler is an
			  IsA check plus one attribute read.
		Applying is idempotent, so an instance seen by both paths is fine.

	Rojo mount point:
		src/client/TextureApplier.client.lua -> StarterPlayerScripts.TextureApplier
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TextureConfig = require(ReplicatedStorage:WaitForChild("TextureConfig")) :: any

local TAG = "KeyedTexture"
local ATTRIBUTE = "TextureKey"
local LOG_PREFIX = "[TextureApplier]"

local warnedUnknown: { [string]: boolean } = {}
local pendingKeys: { [string]: boolean } = {}
local appliedCount = 0

local function toAssetUri(id: string): string
	if string.sub(id, 1, 13) == "rbxassetid://" or string.sub(id, 1, 11) == "rbxasset://" then
		return id
	end
	return "rbxassetid://" .. id
end

local function apply(instance: Instance)
	if not instance:IsA("Decal") then -- Texture inherits from Decal
		return
	end
	local key = instance:GetAttribute(ATTRIBUTE)
	if type(key) ~= "string" or key == "" then
		return
	end
	local decal = instance :: Decal

	local entry = TextureConfig[key]
	if type(entry) ~= "table" then
		if not warnedUnknown[key] then
			warnedUnknown[key] = true
			warn(string.format("%s Unknown TextureKey \"%s\" on %s - hidden. Add it to TextureConfig.lua.", LOG_PREFIX, key, decal:GetFullName()))
		end
		decal.Transparency = 1
		return
	end

	local id = entry.Id
	if type(id) == "string" and id ~= "" then
		local uri = toAssetUri(id)
		if decal.Texture ~= uri then
			decal.Texture = uri
		end
		appliedCount += 1
	else
		-- Not uploaded yet: hide instead of showing an empty/broken image.
		decal.Transparency = 1
		pendingKeys[key] = true
	end
end

local function onDescendantAdded(instance: Instance)
	-- Cheap filter: only Decals/Textures that carry the key attribute.
	if instance:IsA("Decal") and instance:GetAttribute(ATTRIBUTE) ~= nil then
		apply(instance)
	end
end

-- Event hookups first, so nothing added during the initial scan is missed.
CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
Workspace.DescendantAdded:Connect(onDescendantAdded)
ReplicatedStorage.DescendantAdded:Connect(onDescendantAdded)

-- Initial pass.
for _, instance in CollectionService:GetTagged(TAG) do
	apply(instance)
end
for _, root in { Workspace, ReplicatedStorage } :: { Instance } do
	for _, instance in root:GetDescendants() do
		onDescendantAdded(instance)
	end
end

local pendingList = {}
for key in pendingKeys do
	table.insert(pendingList, key)
end
table.sort(pendingList)
if #pendingList > 0 then
	print(string.format(
		"%s %d texture key(s) have no asset ID yet and are hidden: %s. Upload assets/textures/*.png and fill in src/shared/TextureConfig.lua.",
		LOG_PREFIX,
		#pendingList,
		table.concat(pendingList, ", ")
	))
else
	print(string.format("%s Applied %d keyed texture(s) at startup.", LOG_PREFIX, appliedCount))
end
