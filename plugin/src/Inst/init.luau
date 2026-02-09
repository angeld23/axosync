--!strict
--?angeld23

local InstanceFileSyncService = game:GetService("InstanceFileSyncService")
local RunService = game:GetService("RunService")

local Types = require(script.Types)
local Comm = require(script.Parent.Comm)
local Retry = require(script.Parent.Retry)
local Janitor = require(script.Parent.Janitor)
local Log = require(script.Parent.Log)
local Settings = require(script.Parent.Settings)
local TableUtil = require(script.Parent.TableUtil)

local Inst = {}

Inst.TRACKED_PARENTS = {} :: { [Instance]: true? }

Inst.filePathCache = {} :: { [Instance]: string } do
	setmetatable(Inst.filePathCache, { __mode = "k" })
end
Inst.nextFilePathUpdateTime = nil :: number?

export type TrackedInstanceMetadata = {
	path: {string},
	janitor: Janitor.Janitor,
}
Inst.trackedInstances = {} :: { [Instance]: TrackedInstanceMetadata } do
	setmetatable(Inst.trackedInstances, { __mode = "k" })
end
Inst.nameChangeConnections = {} :: { [Instance]: RBXScriptConnection } do
	setmetatable(Inst.nameChangeConnections, { __mode = "k" })
end

-- Returns a list of instances that had their paths added or changed
function Inst.UpdateCachedFilePathsAsync(): {Instance}
	local success, paths = Comm.GetFilePathsAsync():unpack()
	if not success then
		Log.warn(`Failed to get file paths: {paths}`)
		return {}
	end
	local paths = paths :: {string}

	local changedInstances = table.create(#paths) :: {Instance}
	local longestPaths = {} :: { [Instance]: string }
	for _, path in paths do
		local inst = InstanceFileSyncService:GetSyncedInstance(path)
		if inst then
			local oldPath = longestPaths[inst]
			if not oldPath or #oldPath < #path then
				longestPaths[inst] = path
			end
		end
	end
	
	for inst, path in longestPaths do
		if inst then
			local oldPath = Inst.filePathCache[inst]
			Inst.filePathCache[inst] = path
			if oldPath ~= path then
				table.insert(changedInstances, inst)
			end
		end
	end
	
	if #changedInstances > 0 then
		Log.debug(`File path(s) set:{table.concat(TableUtil.Map(changedInstances, function(inst: Instance)
			return `\n\t\t\t\t\t{inst:GetFullName()} -> {Inst.filePathCache[inst]}`
		end))}`)
	end

	return changedInstances
end

function Inst.UpdateAndSendFilePathsAsync(): {Instance}
	local updatedInstances = Inst.UpdateCachedFilePathsAsync()
	for _, updatedInst in Inst.HighestAncestors(updatedInstances) do
		local updatedInstMetadata = Inst.trackedInstances[updatedInst]
		if not updatedInstMetadata then
			continue
		end
		task.spawn(function()
			Comm.SourcemapSetAsync(updatedInstMetadata.path, Inst.ToSourcemapInstance(updatedInst))
		end)
	end
	return updatedInstances
end

function Inst.HighestAncestors(instances: {Instance}): {Instance}
	local highest = table.create(#instances) :: {Instance}
	for _, inst in instances do
		local found = false
		for i, highestInst in highest do
			if highestInst:IsDescendantOf(inst) then
				highest[i] = inst
				found = true
				break
			elseif inst:IsDescendantOf(highestInst) then
				continue -- skip, we already have a higher ancestor
			end
		end
		if not found then
			table.insert(highest, inst)
		end
	end
	return highest
end

function Inst.GetInstancePath(inst: Instance): {string}
	local currentInst: Instance? = inst

	local revPath: {string} = {}
	while currentInst and currentInst ~= game do
		table.insert(revPath, currentInst.Name)
		currentInst = currentInst.Parent
	end

	local path = table.create(#revPath) :: {string}
	for i = #revPath, 1, -1 do
		table.insert(path, revPath[i])
	end
	return path
end

-- Includes self
function Inst.GetSiblingsWithSameName(inst: Instance): {Instance}
	return if not inst.Parent then {inst} else inst.Parent:QueryDescendants(`>[Name="{inst.Name}"]`)
end

function Inst.NameIsUniqueAmongSiblings(inst: Instance): boolean
	return #Inst.GetSiblingsWithSameName(inst) == 1
end

function Inst.IsFileSynced(inst: Instance): boolean
	return not not table.find(InstanceFileSyncService:GetAllInstances(), inst)
end

function Inst.ToSourcemapInstance(inst: Instance, ignoreChildren: boolean?): Types.SourcemapInstance
	local children = inst:GetChildren()
	local sourcemapChildren = table.create(#children) :: {Types.SourcemapInstance}
	if not ignoreChildren then
		local uniqueNames: { [string]: Instance | false } = {}
		for _, child in children do
			if uniqueNames[child.Name] == nil then
				uniqueNames[child.Name] = child
			else
				uniqueNames[child.Name] = false
			end
		end

		for _, child in uniqueNames do
			if child then
				table.insert(sourcemapChildren, Inst.ToSourcemapInstance(child))
			end
		end
	end

	local filePath = Inst.filePathCache[inst]
	return {
		name = if inst == game then "game" else inst.Name,
		className = inst.ClassName,
		pluginManaged = if inst ~= game then true else nil,
		filePaths = filePath and { filePath },
		children = sourcemapChildren,
	}
end

function Inst.ShouldTrack(inst: Instance): boolean
	if Inst.TRACKED_PARENTS[inst] then
		return true
	end
	
	if inst:HasTag("AxoSyncIgnore") then
		return false
	end
	if inst.Name == "AngryJonathans" and inst.Parent == workspace.Terrain then
		return false
	end
	if inst.Name:sub(-7) == "'s hats" and inst.Parent == workspace.Terrain then
		return false
	end
	
	return not not (inst.Parent and Inst.trackedInstances[inst.Parent] and Inst.NameIsUniqueAmongSiblings(inst))
end

function Inst._onNameUpdateAsync(inst: Instance, prevName: string)
	if not inst.Parent then
		return
	end
	
	if prevName == inst.Name then
		return
	end
	
	-- check if we've ruined anyone else's uniqueness with this name change
	for _, sibling in Inst.GetSiblingsWithSameName(inst) do
		if sibling ~= inst then
			Inst._updateAsync(sibling)
		end
	end
	
	-- check if we've freed anyone from non-uniqueness with this name change
	for _, sibling in inst.Parent:QueryDescendants(`>[Name="{prevName}"]`) do
		if sibling ~= inst then
			Inst._updateAsync(sibling)
		end
	end

	Inst._updateAsync(inst)
	
	-- change paths to match this name change
	local metadata = Inst.trackedInstances[inst]
	if metadata and Inst.ShouldTrack(inst) then
		local oldPath = table.clone(metadata.path)

		local ourPathIndex = #metadata.path
		for otherInst, otherMetadata in Inst.trackedInstances do
			if otherInst == inst or otherMetadata.path[ourPathIndex] == prevName and otherInst:IsDescendantOf(inst) then
				otherMetadata.path[ourPathIndex] = inst.Name
			end
		end

		Comm.SourcemapSetAsync(oldPath, nil)
		Comm.SourcemapSetAsync(metadata.path, Inst.ToSourcemapInstance(inst))
	end
end

function Inst._updateAsync(inst: Instance, dontSendSourcemapSet: boolean?, dontCheckSiblings: boolean?)
	if utf8.len(inst.Name) ~= #inst.Name then
		return
	end
	
	Inst.nextFilePathUpdateTime = Inst.nextFilePathUpdateTime or os.clock() + 1
	
	if not Inst.nameChangeConnections[inst] then
		local prevName = inst.Name
		Inst.nameChangeConnections[inst] = inst:GetPropertyChangedSignal("Name"):Connect(function()
			local _prevName = prevName
			prevName = inst.Name
			Inst._onNameUpdateAsync(inst, _prevName)
		end)
		
		if not dontCheckSiblings then
			task.spawn(function()
				-- check if we've ruined anyone else's uniqueness
				for _, sibling in Inst.GetSiblingsWithSameName(inst) do
					if sibling ~= inst and Inst.trackedInstances[sibling] then
						Inst._updateAsync(sibling, nil, true)
					end
				end
			end)
		end
	end

	local shouldTrack = Inst.ShouldTrack(inst)
	local metadata: TrackedInstanceMetadata? = Inst.trackedInstances[inst]

	if shouldTrack ~= not not metadata then
		if metadata then -- is being tracked, must be untracked
			metadata.janitor:Cleanup()
		else -- isn't being tracked, must be tracked
			local janitor = Janitor.new()
			metadata = {
				path = Inst.GetInstancePath(inst),
				janitor = janitor,
			}
			Inst.trackedInstances[inst] = metadata

			assert(metadata)

			janitor:Add(function()
				local trackedMetadata = Inst.trackedInstances[inst]
				if trackedMetadata and trackedMetadata.janitor == janitor then
					Inst.trackedInstances[inst] = nil

					Comm.SourcemapSetAsync(trackedMetadata.path, nil)
				end
			end, nil, "RemoveFromTrackerDictAndSendDeletion")

			janitor:Add(inst.ChildRemoved:Connect(function(child)
				local childMetadata = Inst.trackedInstances[child]
				if childMetadata then
					childMetadata.janitor:Cleanup()
				end
				
				for _, sibling in inst:QueryDescendants(`>[Name="{child.Name}"]`) do
					Inst._updateAsync(sibling)
				end
			end))

			janitor:Add(inst.ChildAdded:Connect(function(child)
				Inst._updateAsync(child)
			end))

			for _, child in inst:GetChildren() do
				Inst._updateAsync(child, true)
			end

			if not dontSendSourcemapSet then
				Comm.SourcemapSetAsync(metadata.path, Inst.ToSourcemapInstance(inst))
			end
		end
	end
end

Inst.heartbeat = nil :: RBXScriptConnection?
function Inst.StartTrackingAsync(): string?
	Inst.StopTracking()
	
	Log.debug("Starting")
	
	Inst.TRACKED_PARENTS = Settings.GetInclude()
	
	local success, projectName = Comm.GetProjectFolderNameAsync():unpack()
	if not success then
		return nil
	end
	local projectName = projectName :: string
	
	Inst.UpdateCachedFilePathsAsync()
	
	Comm.SourcemapSetAsync({}, {
		name = "game",
		className = game.ClassName,
	})
	for parent in Inst.TRACKED_PARENTS do
		Inst._updateAsync(parent, true)
		Comm.SourcemapSetAsync({parent.Name}, Inst.ToSourcemapInstance(parent))
	end
	
	Inst.heartbeat = RunService.Heartbeat:Connect(function()
		if Inst.nextFilePathUpdateTime and os.clock() > Inst.nextFilePathUpdateTime then
			Inst.nextFilePathUpdateTime = nil
			Inst.UpdateAndSendFilePathsAsync()
		end
	end)
	
	return projectName
end

function Inst.StopTracking()
	if Inst.heartbeat then
		Log.debug("Stopping")
		Inst.heartbeat:Disconnect()
		Inst.heartbeat = nil
	end
	
	for inst, metadata in Inst.trackedInstances do
		metadata.janitor:RemoveNoClean("RemoveFromTrackerDictAndSendDeletion")
		metadata.janitor:Cleanup()
		Inst.trackedInstances[inst] = nil
	end
	
	for inst, conn in Inst.nameChangeConnections do
		conn:Disconnect()
	end
	
	table.clear(Inst.trackedInstances)
	table.clear(Inst.nameChangeConnections)
end

return Inst