--!strict
--?angeld23

local HttpService = game:GetService("HttpService")

local T = require(script.Parent.T)
local HttpUtil = require(script.Parent.HttpUtil)
local Retry = require(script.Parent.Retry)
local InstTypes = require(script.Parent.Inst.Types)
local Log = require(script.Parent.Log)
local Settings = require(script.Parent.Settings)

local Comm = {}

function Comm.RequestAsync(requestOptions: HttpUtil.RequestOptions, retryOptions: Retry.Options?, allowUnsuccessfulResponse: boolean?): HttpUtil.RequestResponse?
	local requestOptions = table.clone(requestOptions)
	
	if requestOptions.Url:sub(1, 5) ~= "http:" and requestOptions.Url:sub(1, 6) ~= "https:" then
		local config = Settings.Get()
		requestOptions.Url = `{config.host}:{config.port}/{requestOptions.Url}`
	end
	
	local response = HttpUtil.Request(requestOptions, retryOptions, if allowUnsuccessfulResponse ~= nil then allowUnsuccessfulResponse else true)
	if response and not response.Success then
		Log.warn(`RequestAsync failed: {response.StatusCode} {response.StatusMessage}`)
	end
	return response
end

function Comm.GetFilePathsAsync(): T.ResultTuple<{string}>
	local response = Comm.RequestAsync({
		Url = "getFilePaths"
	})
	if not response then
		return T.uple(false, "No response")
	end
	
	return T.uple(true, HttpService:JSONDecode(response.Body))
end

function Comm.SourcemapSetAsync(path: {string}, value: InstTypes.SourcemapInstance?, noOverwriteChildren: boolean?): HttpUtil.RequestResponse?
	return Comm.RequestAsync({
		Url = "sourcemapSet",
		Method = "POST",
		Compress = Enum.HttpCompression.Gzip,
		Body = {
			path = path,
			value = value,
			noOverwriteChildren = noOverwriteChildren,
		},
	})
end

function Comm.GetProjectFolderNameAsync(): T.ResultTuple<{string}>
	local response = Comm.RequestAsync({
		Url = "getProjectFolderName",
		Method = "GET",
	})
	if not response then
		return T.uple(false, "No response")
	end
	
	return T.uple(true, response.Body)
end

return Comm