--!strict
--?angeld23

local HttpService = game:GetService("HttpService")

local T = require(script.Parent.T)
local Retry = require(script.Parent.Retry)

export type HttpMethod = "GET" | "HEAD" | "POST" | "PUT" | "DELETE" | "OPTIONS" | "TRACE" | "PATCH" 

export type RequestOptions = {
	Url: string,
	Method: HttpMethod?,
	Headers: { [string]: string | Secret }?,
	Body: any?,
	Compress: Enum.HttpCompression?,
}

export type RequestResponse = {
	Body: string,
	Headers: { [string]: string },
	StatusCode: number,
	StatusMessage: string,
	Success: boolean,
}

local HttpUtil = {}

function HttpUtil.Request(requestOptions: RequestOptions, retryOptions: Retry.Options?, allowUnsuccessfulResponse: boolean?): RequestResponse?
	local requestOptions = table.clone(requestOptions)
	if requestOptions.Body ~= nil and typeof(requestOptions.Body) ~= "string" then
		requestOptions.Body = HttpService:JSONEncode(requestOptions.Body)
		
		local headers = requestOptions.Headers or {}
		requestOptions.Headers = headers
		headers["Content-Type"] = "application/json"
	end
	
	return Retry.TryWithOptions(retryOptions, function()
		local result = HttpService:RequestAsync(requestOptions :: any) :: RequestResponse
		if allowUnsuccessfulResponse or result.Success then
			return result
		end
		error(if #result.StatusMessage > 0 then `{result.StatusCode} {result.StatusMessage}` else `{result.StatusCode}`)
	end)
end

function HttpUtil.TryGetSecret(key: string): Secret?
	local s, result = pcall(function()
		return HttpService:GetSecret(key)
	end)
	if s then
		return result
	end
	return nil
end

return HttpUtil