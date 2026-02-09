--!strict
--?angeld23

return {
	host = "http://localhost",
	port = 33752,
	logLevel = "INFO",
	include = {
		game:GetService("Workspace"),
		game:GetService("Players"),
		game:GetService("Lighting"),
		game:GetService("ReplicatedFirst"),
		game:GetService("ReplicatedStorage"),
		game:GetService("ServerScriptService"),
		game:GetService("ServerStorage"),
		game:GetService("StarterGui"),
		game:GetService("StarterPack"),
		game:GetService("StarterPlayer"),
		game:GetService("SoundService"),
		game:GetService("Chat"),
		game:GetService("LocalizationService"),
		game:GetService("TestService"),
	},
}