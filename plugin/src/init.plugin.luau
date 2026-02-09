--!strict
--?angeld23

local RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

local Inst = require(script.Inst)
local Retry = require(script.Retry)
local Log = require(script.Log)
local Settings = require(script.Settings)
local Cleanup = require(script.Cleanup)

plugin.Unloading:Connect(function()
	Cleanup:Cleanup()
end)

local toolbar = plugin:CreateToolbar("AxoSync")
local toggleButton = toolbar:CreateButton("TrackingButton", "Start/stop instance tracking", "rbxassetid://134530880628806", "AxoSync")
toggleButton.ClickableWhenViewportHidden = true
local settingsButton = toolbar:CreateButton("SettingsButton", "Open AxoSync settings", "rbxassetid://128317424741902", "Settings")
settingsButton.ClickableWhenViewportHidden = true

Cleanup:Add(Inst.StopTracking)

local projectName: string? = nil
Cleanup:Add(toggleButton.Click:Connect(function()
	toggleButton.Enabled = false
	
	local success = Retry.LoudPcall(function()
		local wasActive = not not Inst.heartbeat
		if wasActive then
			Inst.StopTracking()
			Log.info(`Stopped tracking {projectName}.`)
		else
			local config = Settings.Get()
			local endpoint = `{config.host}:{config.port}`
			projectName = Inst.StartTrackingAsync()
			if projectName then
				Log.info(`Started tracking {projectName} at {endpoint}`)
			else
				Log.warn(`Failed to start tracking. Is the server running at {endpoint}?`)
				return false
			end
		end

		toggleButton.Enabled = true
		toggleButton:SetActive(not wasActive)

		return true
	end)

	if not success then
		toggleButton.Enabled = true
		toggleButton:SetActive(false)
	end
end))

Cleanup:Add(settingsButton.Click:Connect(function()
	settingsButton:SetActive(false)
	Settings.OpenAsync()
end))
