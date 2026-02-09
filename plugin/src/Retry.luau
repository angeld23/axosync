--!strict
--?angeld23
--[[
	Authors:
		angeld23
	Purpose:
		Retry helpers for functions: fixed-delay (Try), infinite (TryForever), exponential backoff
		(TryExponential / ...WithMaxRetries), plus LoudPcall to show errors without terminating the calling thread.
]]

local Log = require(script.Parent.Log)

local Retry = {}

function Retry.Try<T>(func: () -> T?, retries: number?, interval: number?): T?
	local retries = retries or 1
	local interval = math.max(0, interval or 0)
	
	for i = 1, retries do
		local success, result = pcall(func)
		if success then
			return result
		end
		Log.warn(debug.traceback(`[Retry.Try] {result}`, 2))
		task.wait(interval)
	end
	
	return nil
end

function Retry.TryForever<T>(func: () -> T, interval: number?): T
	return Retry.Try(func, math.huge, interval) :: T
end

function Retry.TryExponentialWithMaxRetries<T>(func: () -> T?, retries: number, baseInterval: number?, maxInterval: number?): T?
	local baseInterval = baseInterval or 1
	local maxInterval = maxInterval or math.huge
	
	local interval = baseInterval
	for i = 1, retries do
		local success, result = pcall(func)
		if success then
			return result
		end
		Log.warn(debug.traceback(`[Retry.TryExponential] {result}`, 2))
		task.wait(interval)
		interval = math.min(maxInterval, interval * 2)
	end
	
	return nil
end

function Retry.TryExponential<T>(func: () -> T, baseInterval: number?, maxInterval: number?): T
	return Retry.TryExponentialWithMaxRetries(func, math.huge, baseInterval, maxInterval) :: T
end

--[[
	Calls a function and returns the result if it succeeds.
	If it fails, an error will be thrown to the console with a stack trace but the thread calling it will not be stopped.
]]
function Retry.LoudPcall<T>(func: () -> T?): T?
	local result: T?
	local done = false
	local event = Instance.new("BindableEvent")
	local thread = task.spawn(function()
		result = func()
		done = true
		event:Fire()
	end)
	
	-- for if an error actually happens
	local checkThread = task.spawn(function()
		while coroutine.status(thread) ~= "dead" do
			task.wait()
		end
		done = true
		event:Fire()
	end)
	
	-- for if the task completes immediately
	if done then
		return result
	end
	
	event.Event:Wait()
	task.cancel(checkThread)
	return result
end

-- Options

export type Options = {
	retryFunc: (...any) -> any?,
	args: {any},	
}

local Options = {} do
	function Options.Try(retries: number?, interval: number?): Options
		return {
			retryFunc = Retry.Try,
			args = {retries, interval}
		}
	end
	
	function Options.TryForever(interval: number?): Options
		return {
			retryFunc = Retry.TryForever,
			args = {interval}
		}
	end
	
	function Options.TryExponentialWithMaxRetries(retries: number?, baseInterval: number?, maxInterval: number?): Options
		return {
			retryFunc = Retry.TryExponentialWithMaxRetries,
			args = {retries, baseInterval, maxInterval}
		}
	end
	
	function Options.TryExponential(baseInterval: number?, maxInterval: number?): Options
		return {
			retryFunc = Retry.TryExponential,
			args = {baseInterval, maxInterval}
		}
	end
	
	function Options.LoudPcall(): Options
		return {
			retryFunc = Retry.LoudPcall,
			args = {}
		}
	end
end
Retry.Options = Options

function Retry.TryWithOptions<T>(options: Options?, func: () -> T): T?
	local options = options or Options.Try()
	return options.retryFunc(func, table.unpack(options.args))
end

return Retry