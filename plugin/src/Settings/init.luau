--!strict
--?angeld23

local ScriptEditorService = game:GetService("ScriptEditorService")
local TestService = game:GetService("TestService")
local RunService = game:GetService("RunService")

local T = require(script.Parent.T)
local Log = require(script.Parent.Log)
local TableUtil = require(script.Parent.TableUtil)
local Cleanup = require(script.Parent.Cleanup)

local Settings = {}
Settings.TYPECHECKS = {}

export type Settings = {
	host: string,
	port: number,
	logLevel: "ERROR" | "WARN" | "INFO" | "DEBUG",
	include: {Instance},
}
Settings.TYPECHECKS.Settings = T.interface {
	host = T.string,
	port = T.number,
	logLevel = Log.TYPECHECKS.LogLevel,
	include = T.array(T.Instance),
}

Settings.MODULE_NAME = "AxoSync_Settings"
Settings.LOAD_DELAY = 1

Settings._current = require(script.DefaultSettings) :: Settings
Settings._nextLoadTime = nil :: number?

function Settings._getModule(): ModuleScript?
	return TestService:FindFirstChild(Settings.MODULE_NAME) :: ModuleScript?
end

function Settings._getOrTryCreateModule(): ModuleScript?
	do
		local module = Settings._getModule()
		if module then
			return module
		end
	end
	
	local success, module = pcall(function()
		local module = script.DefaultSettings:Clone()
		module.Name = Settings.MODULE_NAME
		module.Parent = TestService
		return module
	end)
	
	if not success then
		Log.warn("Failed to open settings:", module)
		return nil
	end
	
	return module
end

function Settings.OpenAsync(): boolean
	local module = Settings._getOrTryCreateModule()
	if not module then
		return false
	end
	
	local success, message = ScriptEditorService:OpenScriptDocumentAsync(module)
	if not success then
		Log.warn("Failed to open settings (OpenScriptDocumentAsync failed):", message)
		return false
	end
	
	return true
end

function Settings.LoadAsync(): boolean
	Log.debug("Loading settings")
	
	local module = Settings._getOrTryCreateModule()
	if not module then
		return false
	end
	
	local func, err = loadstring(ScriptEditorService:GetEditorSource(module))
	if not func then
		Log.warn(`Failed to load settings from {module:GetFullName()}:`, err)
		return false
	end
	
	local success, result = pcall(func)
	if not success then
		Log.warn(`Failed to load settings from {module:GetFullName()}:`, result)
		return false
	end
	
	return Settings.Set(result)
end

function Settings.Set(newSettings: Settings): boolean
	local isValid, err = Settings.TYPECHECKS.Settings(newSettings)
	if not isValid then
		Log.warn("Invalid settings:", err)
		return false
	end
	
	local oldSettings = Settings._current
	
	Log._configuredLogLevel = Log.LEVEL[newSettings.logLevel]
	Settings._current = TableUtil.Lock(newSettings)
	
	if not TableUtil.DeepEquals(oldSettings, newSettings) then
		Log.info("Settings updated")
		local Inst = require(script.Parent.Inst) :: any
		if Inst.heartbeat then
			Log.warn("Changes to settings will not be reflected until you toggle AxoSync off and then back on again.")
		end
	end
	
	return true
end

function Settings.Get(): Settings
	return Settings._current
end

function Settings.GetInclude(): { [Instance]: true? }
	local config = Settings.Get()
	local visited: { [Instance]: true? } = {}
	local set: { [Instance]: true? } = {}
	for _, inst in config.include do
		if visited[inst] then
			continue
		end
		visited[inst] = true
		
		local shouldSkip = false
		for otherInst in set do
			if inst:IsDescendantOf(otherInst) then
				shouldSkip = true
				break
			elseif otherInst:IsDescendantOf(inst) then
				set[otherInst] = nil
			end
		end
		if shouldSkip then
			continue
		end
		set[inst] = true
	end
	return set
end

Cleanup:Add(ScriptEditorService.TextDocumentDidChange:Connect(function(doc)
	local module = Settings._getModule()
	if not module then
		return
	end
	
	if doc:GetScript() ~= module then
		return
	end

	Settings._nextLoadTime = os.clock() + Settings.LOAD_DELAY
end))

Settings.Set(Settings._current)
Settings.LoadAsync()

Cleanup:Add(RunService.Heartbeat:Connect(function()
	if Settings._nextLoadTime then
		if os.clock() >= Settings._nextLoadTime then
			Settings._nextLoadTime = nil
			Settings.LoadAsync()
		end
	end
end))

return Settings