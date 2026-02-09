--!strict
--?angeld23

local T = require(script.Parent.T)

local Log = {}
Log.TYPECHECKS = {}

export type LogLevel = "ERROR" | "WARN" | "INFO" | "DEBUG"
Log.TYPECHECKS.LogLevel = T.literal("ERROR", "WARN", "INFO", "DEBUG")

Log.LEVEL = {
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	DEBUG = 4,
} :: {
	ERROR: number,
	WARN: number,
	INFO: number,
	DEBUG: number,
	[LogLevel]: number,
}
Log.PREFIX = "[AxoSync]"
Log._configuredLogLevel = 67

function Log._log(level: number, ...: any)
	if level > Log._configuredLogLevel then
		return
	end
	
	if level == Log.LEVEL.WARN then
		warn(Log.PREFIX, ...)
	elseif level == Log.LEVEL.INFO then
		print(Log.PREFIX, ...)
	elseif level == Log.LEVEL.DEBUG then
		local scriptName: string, lineNumber: number = debug.info(3, "sl")
		print(`{Log.PREFIX} ({scriptName}:{lineNumber} DEBUG)`, ...)
	end
end

function Log.error(...: any): never
	error(table.concat({Log.PREFIX, ...}, " "), 2)
end

function Log.warn(...: any): ()
	Log._log(Log.LEVEL.WARN, ...)
end

function Log.info(...: any): ()
	Log._log(Log.LEVEL.INFO, ...)
end

function Log.debug(...: any): ()
	Log._log(Log.LEVEL.DEBUG, ...)
end

return Log