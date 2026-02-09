--!strict

-- TableUtil
-- Stephen Leitnick
-- September 13, 2017

-- Modifications made by angeld23

--[=[
	@class TableUtil

	A collection of helpful table utility functions. Many of these functions are carried over from JavaScript or
	Python that are not present in Lua.

	Tables that only work specifically with arrays or dictionaries are marked as such in the documentation.

	:::info Immutability
	All functions (_except_ `SwapRemove`, `SwapRemoveFirstValue`, and `Lock`) treat tables as immutable and will return
	copies of the given table(s) with the operations performed on the copies.
]=]
local TableUtil = {}

local HttpService = game:GetService("HttpService")

local Rand = Random.new()

--[=[
	@within TableUtil
	@function Copy
	@param tbl table -- Table to copy
	@param deep boolean? -- Whether or not to perform a deep copy
	@return table

	Creates a copy of the given table. By default, a shallow copy is
	performed. For deep copies, a second boolean argument must be
	passed to the function.
]=]
function TableUtil.Copy<T>(t: T, deep: boolean?): T
	if not deep then
		return (table.clone(t :: any) :: any) :: T
	end

	-- uglyburger0 sent this at some point Idk if he made it Lol

	local lookup = {}

	local function copy(object: any): any
		if typeof(object) ~= "table" then
			return object
		elseif lookup[object] then
			return lookup[object]
		end

		local newTable = {}
		lookup[object] = newTable

		for key, value in object do
			newTable[copy(key)] = copy(value)
		end

		return setmetatable(newTable, getmetatable(object))
	end

	return copy(t)
end

--[=[
	@within TableUtil
	@function DeepCopy
	@param tbl table -- Table to deep-copy
	@return table

	Creates a deep copy of the given table.
]=]
function TableUtil.DeepCopy<T>(t: T): T
	return TableUtil.Copy(t, true)
end

--[=[
	@within TableUtil
	@function Sync
	@param srcTbl table -- Source table
	@param templateTbl table -- Template table
	@return table

	Synchronizes the `srcTbl` based on the `templateTbl`. This will make
	sure that `srcTbl` has all of the same keys as `templateTbl`, including
	removing keys in `srcTbl` that are not present in `templateTbl`. This
	is a _deep_ operation, so any nested tables will be synchronized as
	well.

	```lua
	local template = {kills = 0, deaths = 0, xp = 0}
	local data = {kills = 10, experience = 12}
	data = TableUtil.Sync(data, template)
	print(data) --> {kills = 10, deaths = 0, xp = 0}
	```

	:::caution Data Loss Warning
	This is a two-way sync, so the source table will have data
	_removed_ that isn't found in the template table. This can
	be problematic if used for player data, where there might
	be dynamic data added that isn't in the template.

	For player data, use `TableUtil.Reconcile` instead.
]=]
function TableUtil.Sync<S, T>(srcTbl: S, templateTbl: T): T
	assert(type(srcTbl) == "table", "First argument must be a table")
	assert(type(templateTbl) == "table", "Second argument must be a table")

	local tbl = table.clone(srcTbl)

	-- If 'tbl' has something 'templateTbl' doesn't, then remove it from 'tbl'
	-- If 'tbl' has something of a different type than 'templateTbl', copy from 'templateTbl'
	-- If 'templateTbl' has something 'tbl' doesn't, then add it to 'tbl'
	for k, v in pairs(tbl) do
		local vTemplate = templateTbl[k]

		-- Remove keys not within template:
		if vTemplate == nil then
			tbl[k] = nil

			-- Synchronize data types:
		elseif type(v) ~= type(vTemplate) then
			if type(vTemplate) == "table" then
				tbl[k] = TableUtil.Copy(vTemplate, true)
			else
				tbl[k] = vTemplate
			end

			-- Synchronize sub-tables:
		elseif type(v) == "table" then
			tbl[k] = TableUtil.Sync(v, vTemplate)
		end
	end

	-- Add any missing keys:
	for k, vTemplate in pairs(templateTbl) do
		local v = tbl[k]

		if v == nil then
			if type(vTemplate) == "table" then
				tbl[k] = TableUtil.Copy(vTemplate, true)
			else
				tbl[k] = vTemplate
			end
		end
	end

	return (tbl :: any) :: T
end

--[=[
	@within TableUtil
	@function Reconcile
	@param source table
	@param template table
	@return table

	Performs a one-way sync on the `source` table against the
	`template` table. Any keys found in `template` that are
	not found in `source` will be added to `source`. This is
	useful for syncing player data against data template tables
	to ensure players have all the necessary keys, while
	maintaining existing keys that may no longer be in the
	template.

	This is a deep operation, so nested tables will also be
	properly reconciled.

	```lua
	local template = {kills = 0, deaths = 0, xp = 0}
	local data = {kills = 10, abc = 20}
	local correctedData = TableUtil.Reconcile(data, template)
	
	print(correctedData) --> {kills = 10, deaths = 0, xp = 0, abc = 20}
	```
]=]
function TableUtil.Reconcile<S, T>(src: S, template: T): S & T
	assert(type(src) == "table", "First argument must be a table")
	assert(type(template) == "table", "Second argument must be a table")

	local tbl = table.clone(src)

	for k, v in template do
		local sv = src[k]
		if sv == nil then
			if type(v) == "table" then
				tbl[k] = TableUtil.Copy(v, true)
			else
				tbl[k] = v
			end
		elseif type(sv) == "table" then
			if type(v) == "table" then
				tbl[k] = TableUtil.Reconcile(sv, v)
			else
				tbl[k] = TableUtil.Copy(sv, true)
			end
		end
	end

	return (tbl :: any) :: S & T
end

--[=[
	@within TableUtil
	@function SwapRemove
	@param tbl table -- Array
	@param i number -- Index

	Removes index `i` in the table by swapping the value at `i` with
	the last value in the array, and then trimming off the last
	value from the array.

	This allows removal of the value at `i` in `O(1)` time, but does
	not preserve array ordering. If a value needs to be removed from
	an array, but ordering of the array does not matter, using
	`SwapRemove` is always preferred over `table.remove`.

	In the following example, we remove "B" at index 2. SwapRemove does
	this by moving the last value "E" over top of "B", and then trimming
	off "E" at the end of the array:
	```lua
	local t = {"A", "B", "C", "D", "E"}
	TableUtil.SwapRemove(t, 2) -- Remove "B"
	print(t) --> {"A", "E", "C", "D"}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.SwapRemove<T>(t: { T }, i: number)
	local n = #t
	t[i] = t[n]
	t[n] = nil
end

--[=[
	@within TableUtil
	@function SwapRemoveFirstValue
	@param tbl table -- Array
	@param v any -- Value to find
	@return number?

	Performs `table.find(tbl, v)` to find the index of the given
	value, and then performs `TableUtil.SwapRemove` on that index.

	```lua
	local t = {"A", "B", "C", "D", "E"}
	TableUtil.SwapRemoveFirstValue(t, "C")
	print(t) --> {"A", "B", "E", "D"}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.SwapRemoveFirstValue<T>(t: { T }, v: T): number?
	local index: number? = table.find(t, v)
	if index then
		TableUtil.SwapRemove(t, index)
	end
	return index
end

--[=[
	@within TableUtil
	@function Map
	@param tbl table
	@param predicate (value: any, key: any, tbl: table) -> newValue: any
	@return table

	Performs a map operation against the given table, which can be used to
	map new values based on the old values at given keys/indices.

	For example:

	```lua
	local t = {A = 10, B = 20, C = 30}
	local t2 = TableUtil.Map(t, function(value)
		return value * 2
	end)
	print(t2) --> {A = 20, B = 40, C = 60}
	```
]=]
function TableUtil.Map<K, V, M>(t: { [K]: V }, f: (V, K, { [K]: V }) -> M): { [K]: M }
	assert(type(t) == "table", "First argument must be a table")
	assert(type(f) == "function", "Second argument must be a function")
	local newT: { [K]: M } = table.create(#t) :: any
	for k, v in t do
		newT[k] = f(v, k, t)
	end
	return newT
end

-- added by angeld23
--[[
	Receives an array of keys and a function that generates values for those keys and returns the resulting dictionary.
	The function will only be run once for each *unique* key. If an item repeats in the array, it will be skipped.
]]
function TableUtil.MakeDictionaryFromKeys<K, V>(keys: {K}, f: (K, number, {K}) -> V): { [K]: V }
	local newT: { [K]: V } = {}
	local keysToSkip: { [K]: true } = {}
	for i, k in keys do
		if keysToSkip[k] then
			continue
		end

		newT[k] = f(k, i, keys)
		keysToSkip[k] = true
	end
	return newT
end

-- added by angeld23
--[[
	Returns a dictionary that maps each unique value in the given array to its first index of appearance.
]]
function TableUtil.FirstIndices<T>(arr: {T}): { [T]: number }
	return TableUtil.MakeDictionaryFromKeys(arr, function(_, index) return index end)
end

-- added by angeld23
--[[
	Receives an array of values and returns a dictionary where each key is a value from the array and each value is true.
]]
function TableUtil.MakeSet<T>(items: {T}): { [T]: true? }
	return TableUtil.MakeDictionaryFromKeys(items, function() return true end) :: any
end

--[=[
	@within TableUtil
	@function Filter
	@param tbl table
	@param predicate (value: any, index: number, tbl: table) -> keep: boolean
	@return table

	Performs a filter operation against the given table array, which can be used to
	filter out unwanted values.
]=]
function TableUtil.Filter<T>(t: { T }, predicate: (T, number, { T }) -> boolean): { T }
	assert(type(t) == "table", "First argument must be a table")
	assert(type(predicate) == "function", "Second argument must be a function")
	local newT = table.create(#t)
	if #t > 0 then
		local n = 0
		for i, v in t do
			if predicate(v, i, t) then
				n += 1
				newT[n] = v
			end
		end
	end
	return newT
end

-- added by angeld23
--[[
	Removes all keys from the provided table that do not pass the predicate.
]]
function TableUtil.FilterDictionaryInPlace<K, V>(t: { [K]: V }, predicate: (V, K, { [K]: V }) -> boolean)
	for k, v in t do
		if not predicate(v, k, t) then
			t[k] = nil
		end
	end
end

-- added by angeld23
--[[
	Creates a shallow copy of the provided table using only the keys that pass the predicate.
]]
function TableUtil.FilterDictionary<K, V>(t: { [K]: V }, predicate: (V, K, { [K]: V }) -> boolean): { [K]: V }
	local newT = {}
	for k, v in t do
		if predicate(v, k, t) then
			newT[k] = v
		end
	end
	return newT
end

-- added by angeld23
--[[
	Filters an array in-place using a callback that receives an item and returns whether it should be kept.
	Items are pruned via an "unordered remove", which moves the current last item in the array to replace the removed item.
]]
function TableUtil.UnorderedFilterInPlace<T>(array: {T}, predicate: (T, number, {T}) -> boolean)
	local i = 1
	local oldIndex = 1
	while true do
		local item = array[i]
		if not item then
			break
		end

		if not predicate(item, oldIndex, array) then
			local len = #array
			local lastItem = array[len]
			array[i] = lastItem
			array[len] = nil
		else
			i += 1
		end

		oldIndex += 1
	end
end

--[=[
	@within TableUtil
	@function Reduce
	@param tbl table
	@param predicate (accumulator: any, value: any, index: any, tbl: table) -> result: any
	@return table

	Performs a reduce operation against the given table, which can be used to
	reduce the table into a single value. This could be used to sum up a table
	or transform all the values into a compound value of any kind.

	For example:

	```lua
	local t = {10, 20, 30, 40}
	local result = TableUtil.Reduce(t, function(accum, value)
		return accum + value
	end)
	print(result) --> 100
	```
]=]
function TableUtil.Reduce<T, R>(t: { T }, predicate: (R, T, any, { T }) -> R, init: R): R
	assert(type(t) == "table", "First argument must be a table")
	assert(type(predicate) == "function", "Second argument must be a function")
	local result = init :: R
	if #t > 0 then
		local start = 1
		if init == nil then
			result = (t[1] :: any) :: R
			start = 2
		end
		for i = start, #t do
			result = predicate(result, t[i], i, t)
		end
	else
		local start = nil
		if init == nil then
			result = (next(t) :: any) :: R
			start = result
		end
		for k, v in next, t, start :: any? do
			result = predicate(result, v, k, t)
		end
	end
	return result
end

--[=[
	@within TableUtil
	@function Assign
	@param target table
	@param ... table
	@return table

	Copies all values of the given tables into the `target` table.

	```lua
	local t = {A = 10}
	local t2 = {B = 20}
	local t3 = {C = 30, D = 40}
	local newT = TableUtil.Assign(t, t2, t3)
	print(newT) --> {A = 10, B = 20, C = 30, D = 40}
	```
]=]
function TableUtil.Assign<T>(target: { T }, ...: { any }): { T } & { any }
	local tbl = table.clone(target)
	for _, src in { ... } do
		for k, v in src do
			tbl[k] = v
		end
	end
	return tbl
end

--[=[
	@within TableUtil
	@function Extend
	@param target table
	@param extension table
	@return table

	Extends the target array with the extension array.

	```lua
	local t = {10, 20, 30}
	local t2 = {30, 40, 50}
	local tNew = TableUtil.Extend(t, t2)
	print(tNew) --> {10, 20, 30, 30, 40, 50}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.Extend<T, E>(target: { T }, extension: { E }): { T } & { E }
	local tbl = table.clone(target) :: { any }
	for _, v in extension do
		table.insert(tbl, v)
	end
	return tbl
end

--[=[
	@within TableUtil
	@function Reverse
	@param tbl table
	@return table

	Reverses the array.

	```lua
	local t = {1, 5, 10}
	local tReverse = TableUtil.Reverse(t)
	print(tReverse) --> {10, 5, 1}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.Reverse<T>(tbl: { T }): { T }
	local n = #tbl
	local tblRev = table.create(n)
	for i = 1, n do
		tblRev[i] = tbl[n - i + 1]
	end
	return tblRev
end

--[=[
	@within TableUtil
	@function Shuffle
	@param tbl table
	@param rngOverride Random?
	@return table

	Shuffles the table.

	```lua
	local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}
	local shuffled = TableUtil.Shuffle(t)
	print(shuffled) --> e.g. {9, 4, 6, 7, 3, 1, 5, 8, 2}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.Shuffle<T>(tbl: { T }, rngOverride: Random?): { T }
	assert(type(tbl) == "table", "First argument must be a table")
	local shuffled = table.clone(tbl)
	local random = if typeof(rngOverride) == "Random" then rngOverride else Rand
	for i = #tbl, 2, -1 do
		local j = random:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end
	return shuffled
end

--[=[
	@within TableUtil
	@function Sample
	@param tbl table
	@param sampleSize number
	@param rngOverride Random?
	@return table

	Returns a random sample of the table.

	```lua
	local t = {1, 2, 3, 4, 5, 6, 7, 8, 9}
	local sample = TableUtil.Sample(t, 3)
	print(sample) --> e.g. {6, 2, 5}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.Sample<T>(tbl: { T }, size: number, rngOverride: Random?): { T }
	assert(type(tbl) == "table", "First argument must be a table")
	assert(type(size) == "number", "Second argument must be a number")

	-- If given table is empty, just return a new empty table:
	local len = #tbl
	if len == 0 then
		return {}
	end

	local shuffled = table.clone(tbl)
	local sample = table.create(size)
	local random = if typeof(rngOverride) == "Random" then rngOverride else Rand

	-- Clamp sample size to be no larger than the given table size:
	size = math.clamp(size, 1, len)

	for i = 1, size do
		local j = random:NextInteger(i, len)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	table.move(shuffled, 1, size, 1, sample)

	return sample
end

-- added by angeld23
--[[
	Returns a single random value from the provided array (unless it's empty).
]]
function TableUtil.SampleOne<T>(tbl: {T}, rngOverride: Random?): T?
	local len = #tbl
	if len <= 0 then
		return
	end

	return tbl[(rngOverride or Rand):NextInteger(1, len)]
end

--[=[
	@within TableUtil
	@function Flat
	@param tbl table
	@param depth number?
	@return table

	Returns a new table where all sub-arrays have been
	bubbled up to the top. The depth at which the scan
	is performed is dictated by the `depth` parameter,
	which is set to `1` by default.

	```lua
	local t = {{10, 20}, {90, 100}, {30, 15}}
	local flat = TableUtil.Flat(t)
	print(flat) --> {10, 20, 90, 100, 30, 15}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.Flat<T>(tbl: { T }, depth: number?): { T }
	local maxDepth: number = if type(depth) == "number" then depth else 1
	local flatTbl = table.create(#tbl)
	local function Scan(t: { any }, d: number)
		for _, v in t do
			if type(v) == "table" and d < maxDepth then
				Scan(v, d + 1)
			else
				table.insert(flatTbl, v)
			end
		end
	end
	Scan(tbl, 0)
	return flatTbl
end

--[=[
	@within TableUtil
	@function FlatMap
	@param tbl table
	@param predicate (key: any, value: any, tbl: table) -> newValue: any
	@return table

	Calls `TableUtil.Map` on the given table and predicate, and then
	calls `TableUtil.Flat` on the result from the map operation.

	```lua
	local t = {10, 20, 30}
	local result = TableUtil.FlatMap(t, function(value)
		return {value, value * 2}
	end)
	print(result) --> {10, 20, 20, 40, 30, 60}
	```

	:::note Arrays only
	This function works on arrays, but not dictionaries.
]=]
function TableUtil.FlatMap<T, M>(tbl: { T }, callback: (T, number, { T }) -> M): { M }
	return TableUtil.Flat(TableUtil.Map(tbl, callback))
end

--[=[
	@within TableUtil
	@function Keys
	@param tbl table
	@return table

	Returns an array with all the keys in the table.

	```lua
	local t = {A = 10, B = 20, C = 30}
	local keys = TableUtil.Keys(t)
	print(keys) --> {"A", "B", "C"}
	```

	:::caution Ordering
	The ordering of the keys is never guaranteed. If order is imperative, call
	`table.sort` on the resulting `keys` array.
	```lua
	local keys = TableUtil.Keys(t)
	table.sort(keys)
	```
]=]
function TableUtil.Keys<K, V>(tbl: { [K]: V }): { K }
	local keys = table.create(#tbl)
	for k in tbl do
		table.insert(keys, k)
	end
	return keys
end

--[=[
	@within TableUtil
	@function Values
	@param tbl table
	@return table

	Returns an array with all the values in the table.

	```lua
	local t = {A = 10, B = 20, C = 30}
	local values = TableUtil.Values(t)
	print(values) --> {10, 20, 30}
	```

	:::caution Ordering
	The ordering of the values is never guaranteed. If order is imperative, call
	`table.sort` on the resulting `values` array.
	```lua
	local values = TableUtil.Values(t)
	table.sort(values)
	```
]=]
function TableUtil.Values<K, V>(tbl: { [K]: V }): { V }
	local values = table.create(#tbl)
	for _, v in tbl do
		table.insert(values, v)
	end
	return values
end

--[=[
	@within TableUtil
	@function Find
	@param tbl table
	@param callback (value: any, index: any, tbl: table) -> boolean
	@return (value: any?, key: any?)

	Performs a linear scan across the table and calls `callback` on
	each item in the array. Returns the value and key of the first
	pair in which the callback returns `true`.

	```lua
	local t = {
		{Name = "Bob", Age = 20};
		{Name = "Jill", Age = 30};
		{Name = "Ann", Age = 25};
	}

	-- Find first person who has a name starting with J:
	local firstPersonWithJ = TableUtil.Find(t, function(person)
		return person.Name:sub(1, 1):lower() == "j"
	end)

	print(firstPersonWithJ) --> {Name = "Jill", Age = 30}
	```

	:::caution Dictionary Ordering
	While `Find` can also be used with dictionaries, dictionary ordering is never
	guaranteed, and thus the result could be different if there are more
	than one possible matches given the data and callback function.
]=]
function TableUtil.Find<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): (V?, K?)
	for k, v in tbl do
		if callback(v, k, tbl) then
			return v, k
		end
	end
	return nil, nil
end

--[=[
	@within TableUtil
	@function Every
	@param tbl table
	@param callback (value: any, index: any, tbl: table) -> boolean
	@return boolean

	Returns `true` if the `callback` also returns `true` for _every_
	item in the table.

	```lua
	local t = {10, 20, 40, 50, 60}

	local allAboveZero = TableUtil.Every(t, function(value)
		return value > 0
	end)

	print("All above zero:", allAboveZero) --> All above zero: true
	```
]=]
function TableUtil.Every<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): boolean
	for k, v in tbl do
		if not callback(v, k, tbl) then
			return false
		end
	end
	return true
end

--[=[
	@within TableUtil
	@function Some
	@param tbl table
	@param callback (value: any, index: any, tbl: table) -> boolean
	@return boolean

	Returns `true` if the `callback` also returns `true` for _at least
	one_ of the items in the table.

	```lua
	local t = {10, 20, 40, 50, 60}

	local someBelowTwenty = TableUtil.Some(t, function(value)
		return value < 20
	end)

	print("Some below twenty:", someBelowTwenty) --> Some below twenty: true
	```
]=]
function TableUtil.Some<K, V>(tbl: { [K]: V }, callback: (V, K, { [K]: V }) -> boolean): boolean
	for k, v in tbl do
		if callback(v, k, tbl) then
			return true
		end
	end
	return false
end

--[=[
	@within TableUtil
	@function Truncate
	@param tbl table
	@param length number
	@return table

	Returns a new table truncated to the length of `length`. Any length
	equal or greater than the current length will simply return a
	shallow copy of the table.

	```lua
	local t = {10, 20, 30, 40, 50, 60, 70, 80}
	local tTruncated = TableUtil.Truncate(t, 3)
	print(tTruncated) --> {10, 20, 30}
	```
]=]
function TableUtil.Truncate<T>(tbl: { T }, len: number): { T }
	local n = #tbl
	len = math.clamp(len, 1, n)
	return if len == n then table.clone(tbl) else table.move(tbl, 1, len, 1, table.create(len))
end

--[=[
	@within TableUtil
	@function Zip
	@param ... table
	@return (iter: (t: table, k: any) -> (key: any?, values: table?), tbl: table, startIndex: any?)

	Returns an iterator that can scan through multiple tables at the same time side-by-side, matching
	against shared keys/indices.

	```lua
	local t1 = {10, 20, 30, 40, 50}
	local t2 = {60, 70, 80, 90, 100}

	for key,values in TableUtil.Zip(t1, t2) do
		print(key, values)
	end

	--[[
		Outputs:
		1 {10, 60}
		2 {20, 70}
		3 {30, 80}
		4 {40, 90}
		5 {50, 100}
	--]]
	```
]=]
function TableUtil.Zip(...: { [any]: any }): ((t: { any }, k: any) -> (any, any), { any }, any)
	assert(select("#", ...) > 0, "Must supply at least 1 table")
	local function ZipIteratorArray(all: { any }, k: number): (number?, { any }?)
		k += 1
		local values = {}
		for i, t in all do
			local v = t[k]
			if v ~= nil then
				values[i] = v
			else
				return nil, nil
			end
		end
		return k, values
	end
	local function ZipIteratorMap(all: { [any]: any }, k: any): (number?, { any }?)
		local values = {}
		for i, t in all do
			local v = next(t, k)
			if v ~= nil then
				values[i] = v
			else
				return nil, nil
			end
		end
		return k, values
	end
	local all = { ... }
	if #all[1] > 0 then
		return ZipIteratorArray, all, 0
	else
		return ZipIteratorMap, all, nil
	end
end

--[=[
	@within TableUtil
	@function Lock
	@param tbl table
	@return table

	Locks the table using `table.freeze`, as well as any
	nested tables within the given table. This will lock
	the whole deep structure of the table, disallowing any
	further modifications.

	```lua
	local tbl = {xyz = {abc = 32}}
	tbl.xyz.abc = 28 -- Works fine
	TableUtil.Lock(tbl)
	tbl.xyz.abc = 64 -- Will throw an error (cannot modify readonly table)
	```
]=]
function TableUtil.Lock<T>(tbl: T): T
	if not table.isfrozen(tbl) then
		table.freeze(tbl)
	end
	for _, v in tbl do
		if typeof(v) == "table" then
			TableUtil.Lock(v)
		end
	end
	return tbl
end

--[=[
	@within TableUtil
	@function IsEmpty
	@param tbl table
	@return boolean

	Returns `true` if the given table is empty. This is
	simply performed by checking if `next(tbl)` is `nil`
	and works for both arrays and dictionaries. This is
	useful when needing to check if a table is empty but
	not knowing if it is an array or dictionary.

	```lua
	TableUtil.IsEmpty({}) -- true
	TableUtil.IsEmpty({"abc"}) -- false
	TableUtil.IsEmpty({abc = 32}) -- false
	```
]=]
function TableUtil.IsEmpty(tbl: { any }): boolean
	return next(tbl) == nil
end

--[=[
	@within TableUtil
	@function EncodeJSON
	@param value any
	@return string

	Proxy for [`HttpService:JSONEncode`](https://developer.roblox.com/en-us/api-reference/function/HttpService/JSONEncode).
]=]
function TableUtil.EncodeJSON(value: any): string
	return HttpService:JSONEncode(value)
end

--[=[
	@within TableUtil
	@function DecodeJSON
	@param value any
	@return string

	Proxy for [`HttpService:JSONDecode`](https://developer.roblox.com/en-us/api-reference/function/HttpService/JSONDecode).
]=]
function TableUtil.DecodeJSON(str: string): any
	return HttpService:JSONDecode(str)
end

-- added by angeld23
--[[
	Counts the number of items in a table.
]]
function TableUtil.Count(tbl: { [any]: any }): number
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

-- added by angeld23
--[[
	Returns whether two values are structurally equal.
]]
function TableUtil.DeepEquals(a: any, b: any, ignoreFunctions: boolean?): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		if a ~= a and b ~= b then -- NaN
			return true
		end

		if ignoreFunctions and type(a) == "function" or type(b) == "function" then
			return true
		end

		return a == b
	end

	for key, aValue in a do
		local bValue = b[key]
		if aValue ~= bValue and not TableUtil.DeepEquals(aValue, bValue, ignoreFunctions) then
			return false
		end
	end

	for key, bValue in b do
		local aValue = a[key]
		if aValue ~= bValue and not TableUtil.DeepEquals(aValue, bValue, ignoreFunctions) then
			return false
		end
	end

	return true
end

-- added by angeld23
--[[
	table.sort except it only runs if the table isn't already sorted
]]
function TableUtil.SortIfNeeded<T>(arr: {T}, cmp: ((a: T, b: T) -> boolean)?): boolean
	local isSorted = true
	for i = 1, #arr - 1 do
		if cmp then
			if not cmp(arr[i], arr[i + 1]) then
				isSorted = false
				break
			end
		elseif arr[i] :: any > arr[i + 1] then
			isSorted = false
			break
		end
	end
	if not isSorted then
		table.sort(arr, cmp)
	end
	return isSorted
end

return TableUtil
