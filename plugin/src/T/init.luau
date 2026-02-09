--!strict
--!native
--?angeld23

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local t = require(script.t)

type function indexWithEquals(dict: { [any]: any }, key: any): any
	local normalIndexResult = dict[key]
	if normalIndexResult ~= nil then
		return normalIndexResult
	end

	for otherKey, value in dict do
		if otherKey == key then
			return value
		end
	end

	return nil
end

type function stringify(a: any, noNesting: boolean?, visited: { [any]: true? }?): string
	local visited = visited or {}
	local _f = stringify
	local _n = noNesting
	local function stringify(b: any, noNesting: boolean?): string
		return _f(b, if noNesting ~= nil then noNesting else _n, visited)
	end

	local function isVisited(b: any): boolean
		if b == nil then
			return false
		end

		if visited[b] then
			return true
		end

		for key in visited do
			if extends(key, b) and extends(b, key) then
				return true
			end
		end

		return false
	end

	if typeof(a) == "table" then
		if isVisited(a) then
			return "(*CYCLE*)"
		end
		visited[a] = true

		if a.read and a.read == a.write then
			return stringify(a.read)
		end

		local s = "{ "
		for i, v in a do
			local iStr = stringify(i)
			local vStr = stringify(v)
			s = s .. `{if iStr:sub(1, 1) == '"' then iStr else `"{iStr}"`}: {if vStr:sub(1, 1) == "{" then vStr else `"{vStr}"`}, `
		end
		if s == "{ " then
			return "{}"
		end
		s = s:sub(1, -3) .. " }"
		return s
	elseif typeof(a) :: any == "type" then
		local a = a :: type

		if a:is("table") or a:is("class") then
			if isVisited(a) then
				return "(*CYCLE*)"
			end
			visited[a] = true
		end

		if a:is("singleton") then
			local value = a:value()
			if typeof(value) == "string" then
				return `"{value}"`
			end
			return tostring(value)
		elseif a:is("union") then
			local t = {}
			for _, v in a:components() do
				table.insert(t, stringify(v))
			end
			return table.concat(t, " | ")
		elseif a:is("intersection") then
			local t = {}
			for _, v in a:components() do
				table.insert(t, stringify(v))
			end
			return table.concat(t, " & ")
		elseif a:is("function") then
			return stringify({
				params = a:parameters(),
				returns = a:returns(),
			})
		elseif a:is("generic") then
			if a:ispack() then
				return `<{a:name()}...>`
			else
				return `<{a:name()}>`
			end
		elseif not noNesting and (a:is("class") or a:is("table")) then
			return stringify(a:properties(), true)
		end

		return `types.{a.tag}`
	end

	return tostring(a)
end

type function numberify(a: any): number
	local n =
		if typeof(a) == "type" :: any then tonumber(a:value())
		else tonumber(a)

	assert(n, `count not make into a number: {stringify(a)}`)
	return n
end

type function extends(extendingType: any, baseType: any): boolean
	-- extendingType must at least have all members that are in baseType, but it usually has more

	if typeof(extendingType) ~= typeof(baseType) then
		return false
	end

	if extendingType == baseType then
		return true
	end

	if typeof(extendingType) == "table" then
		assert(typeof(baseType) == "table")

		for key, value in baseType do
			if not extends(extendingType[key], value) then
				return false
			end
		end

		return true
	end

	if typeof(extendingType) ~= "type" :: any then
		error("what")
	end

	local extendingType = extendingType :: type
	local baseType = baseType :: type

	local extIsNeg = extendingType:is("negation")
	local baseIsNeg = baseType:is("negation")
	if extIsNeg or baseIsNeg then
		error("negations not supported yet")
	end

	if extendingType:is("class") and baseType:is("class") then
		local found = false
		forSelfAndAllParents(extendingType, function(p: type)
			if p == baseType then
				found = true
			end
		end)
		return found
	end

	if extendingType:is("never") then
		return baseType:is("never")
	end

	if baseType:is("any") or baseType:is("unknown") then
		return true
	end

	if baseType:is("union") then
		if extendingType:is("union") then
			for _, v in extendingType:components() do
				if not extends(v, baseType) then
					return false
				end
			end

			return true
		else
			for _, v in baseType:components() do
				if extends(extendingType, v) then
					return true
				end
			end
		end
		return false
	elseif extendingType:is("singleton") then
		if baseType:is("singleton") then
			return extendingType:value() == baseType:value()
		elseif baseType:is(typeof(extendingType:value())) then
			return true
		end
	end

	local tag = baseType.tag
	if extendingType.tag == tag then
		if tag == "nil" or tag == "boolean" or tag == "number" or tag == "string" or tag == "buffer" or tag == "thread" then
			return true
		end
	end

	return extendingType.tag == baseType.tag
end

type function singletonUnion(...: string | boolean)
	local t = types :: typeof(types)

	local union: {type} = {}
	for _, v in { ... } do
		table.insert(union, t.singleton(v))
	end
	return t.unionof(table.unpack(union))
end

type function setProperty(target: type, key: type, currentValue: { read: type?, write: type? }, map: (ty: type, accessType: "read" | "write" | "both") -> type)
	if currentValue.read and currentValue.read == currentValue.write then
		target:setproperty(key, map(currentValue.read, "both"))
		return
	end

	if currentValue.read then
		target:setreadproperty(key, map(currentValue.read, "read"))
	end

	if currentValue.write then
		target:setwriteproperty(key, map(currentValue.write, "write"))
	end
end

type function forSelfAndAllParents(a: type, fn: (p: type, accessType: "read" | "write" | "both", levelsUpward: number) -> (), accessType: ("read" | "write" | "both")?, levelsUpward: number?)	
	local levelsUpward = levelsUpward or 0

	fn(a, "both", levelsUpward)
	for i = 1, 16 do
		if not a:is("class") then
			return
		end

		local read = a:readparent()
		local write = a:writeparent()

		if read and read == write then
			fn(read, "both", levelsUpward + 1)

			a = read
			accessType = "both"
			continue
		end

		if read ~= write then
			print("ahh! read ~= write!", levelsUpward)
		end

		if read then
			fn(read, "read", levelsUpward + 1)

			a = read
			accessType = "read"
			continue
		elseif write then -- TODO: what if read and write both ~= nil but read ~= write?
			fn(write, "write", levelsUpward + 1)

			a = write
			accessType = "write"
			continue
		end

		break
	end
end

type function allProperties(a: type): { [type]: { hostType: type?, read: type?, write: type? } }
	local t = types :: typeof(types)

	assert(a:is("table") or a:is("class"), "expected table or class, got " .. a.tag)

	local properties: { [type]: { hostType: type?, read: type?, write: type? } } = {}
	forSelfAndAllParents(a, function(p: type)
		for key, value in p:properties() do
			properties[key] = {
				hostType = p,
				read = value.read,
				write = value.write
			}
		end
	end)
	return properties
end

type function arrayExtend(a: {any}, b: {any}): {any}
	local tbl = table.clone(a) :: { any }
	return table.move(b, 1, #b, #tbl + 1, tbl)
end

export type function Expand(a: type)
	local t = types :: typeof(types)

	local tbl = t.newtable()
	for i, ty in if a:is("intersection") then a:components() else {a} do
		if ty:is("intersection") then
			ty = Expand(ty)
		end
		for key, value in allProperties(ty) do
			setProperty(tbl, key, value, function(b)
				return b
			end)
		end
	end
	return tbl
end

type function generalDict(a: type, enableStringIndexer: boolean)
	local t = types :: typeof(types)

	local originalA = a
	if a:is("intersection") then
		a = Expand(a)
	end

	assert(a:is("table") or a:is("class"), "expected table or class, got " .. a.tag)

	local tbl = t.newtable()

	local canHaveStringIndexer = false

	local values: {type} = {}
	for key, value in allProperties(a) do
		if key:is("singleton") and typeof(key:value()) == "string" then
			canHaveStringIndexer = true
		end

		setProperty(tbl, key, value, function(ty: type)
			if ty:is("function") then
				local params = ty:parameters()
				if params.head and params.head[1] then
					local first = params.head[1]
					if extends(originalA, first) then
						params.head[1] = tbl
					end
				end

				ty:setparameters(params.head, params.tail)
			end
			return ty
		end)

		if value.read then
			table.insert(values, value.read)
		end
	end

	if enableStringIndexer and canHaveStringIndexer then
		tbl:setindexer(t.string, t.optional(t.unionof(table.unpack(values))))
	end

	local meta = a:metatable()
	if meta then
		tbl:setmetatable(meta)
	end

	return tbl
end

export type function Dict(a: type)
	return generalDict(a, true)
end

export type function StrictDict(a: type)
	return generalDict(a, false)
end

export type function Partial(a: type)
	local t = types :: typeof(types)

	if not a:is("table") then
		a = StrictDict(a)
	end

	for key, value in a:properties() do
		setProperty(a, key, value, function(ty: type)
			return t.optional(ty)
		end)
	end

	return a
end

export type NonOptionalFields<T> = T -- TODO: bruh

--export type function NonOptionalFields(a: type)
--	local t = types :: typeof(types)

--	if not a:is("table") then
--		a = StrictDict(a)
--	end

--	for key, value in a:properties() do
--		setProperty(a, key, value, function(ty: type)
--			if ty:is("union") then
--				local components: {type} = {}
--				for _, component in ty:components() do
--					if component:is("nil") or component:is("singleton") and not component:value() then
--						continue
--					end

--					table.insert(components, component)
--				end

--				if #components == 0 then
--					return ty
--				end

--				return ToUnion(components)
--			end

--			return ty
--		end)
--	end

--	return a
--end

type function generalMapValueType(a: type, from: type, to: type, useExtends: boolean)
	local t = types :: typeof(types)

	if not a:is("table") then
		a = StrictDict(a)
	end

	for key, value in a:properties() do
		setProperty(a, key, value, function(ty: type)
			if ty == from or useExtends and extends(ty, from) then
				return to
			end
			return ty
		end)
	end

	return a
end

export type function MapValue(a: type, from: type, to: type)
	return generalMapValueType(a, from, to, true)
end

export type function MapExactValue(a: type, from: type, to: type)
	return generalMapValueType(a, from, to, false)
end

type function generalMapKeyType(a: type, from: type, to: type, useExtends: boolean)
	local t = types :: typeof(types)

	local tbl = t.newtable()
	for key, value in allProperties(a) do
		if key == from or useExtends and extends(key, from) then
			setProperty(tbl, key, value, function()
				return to
			end)
		else
			setProperty(tbl, key, value, function(ty: type)
				return ty
			end)
		end
	end

	local meta = a:metatable()
	if meta then
		tbl:setmetatable(meta)
	end

	return tbl
end

export type function MapKey(a: type, from: type, to: type)
	return generalMapKeyType(a, from, to, true)
end

export type function MapExactKey(a: type, from: type, to: type)
	return generalMapKeyType(a, from, to, false)
end

type function generalWithoutKeyType(a: type, from: type, useExtends: boolean)
	local t = types :: typeof(types)

	local tbl = t.newtable()
	for key, value in allProperties(a) do
		if key == from or useExtends and extends(key, from) then
			setProperty(tbl, key, value, function()
				return nil
			end)
		else
			setProperty(tbl, key, value, function(ty: type)
				return ty
			end)
		end
	end

	local meta = a:metatable()
	if meta then
		tbl:setmetatable(meta)
	end

	return tbl
end

export type function WithoutExactKey(a: type, key: type)
	return generalWithoutKeyType(a, key, false)
end

export type function WithoutKey(a: type, key: type)
	return generalWithoutKeyType(a, key, true)
end

type function generalReplaceKeyType(a: type, keyToReplace: type, newValue: type, useExtends: boolean)
	local t = types :: typeof(types)

	local tbl = t.newtable()
	for key, value in allProperties(a) do
		if key == keyToReplace or useExtends and extends(key, keyToReplace) then
			setProperty(tbl, key, value, function()
				return newValue
			end)
		else
			setProperty(tbl, key, value, function(ty: type)
				return ty
			end)
		end
	end

	local meta = a:metatable()
	if meta then
		tbl:setmetatable(meta)
	end

	return tbl
end

export type function ReplaceExactKey(a: type, keyToReplace: type, newValue: type)
	return generalReplaceKeyType(a, keyToReplace, newValue, false)
end

export type function ReplaceKey(a: type, keyToReplace: type, newValue: type)
	return generalReplaceKeyType(a, keyToReplace, newValue, true)
end

type function getComponents(a: type | {type}): {type}
	local t = types :: typeof(types)

	if typeof(a) == "table" then
		return a :: any
	end
	local a = a :: type

	if a:is("union") or a:is("intersection") then
		return a:components()
	elseif a:is("table") or a:is("class") then
		local v1 = a:readproperty(t.singleton("v1"))
		if v1 then
			local components = {v1}
			for i = 2, 16 do
				local v = a:readproperty(t.singleton(`v{i}`))
				if not v then
					break
				end
				table.insert(components, v)
			end
			return components
		end

		local indexer = a:indexer()
		if indexer then
			return getComponents(indexer.readresult)
		end
	end

	return {a}
end

type function getUniqueComponents(a: type | {type}): {type}
	local components = getComponents(a)

	if #components == 1 then
		return components
	end

	local newArray = table.create(#components) :: {type}
	local visited: { [type]: true? } = {}
	for _, component in components do
		if indexWithEquals(visited, component) then
			continue
		end
		visited[component] = true
		table.insert(newArray, component)
	end

	return newArray
end

export type function ExtractComponent(a: type | {type}, n: any)
	local n = numberify(n)
	local b = getComponents(a)[n]
	if b then
		return b
	end
	error(`component #{n} does not exist`)
end

type function getNthFromHeadAndTail(a: { head: {type}?, tail: type? }, n: any, dontReturnNilSingleton: boolean?): type?
	local t = types :: typeof(types)

	local n = numberify(n)

	local total = 0
	total += if a.head then #a.head else 0
	total += if a.tail then 1 else 0

	if n < 0 then
		n = total + n + 1
	end

	local nilReturn = if dontReturnNilSingleton then nil else t.singleton(nil)

	if a.head and n <= #a.head then
		return a.head[n] or nilReturn
	end

	if a.tail and n == total then
		return a.tail or nilReturn
	end

	return nilReturn
end

export type function Argument(fn: type, n: any)
	assert(fn:is("function"), "expected function, got " .. fn.tag)
	return getNthFromHeadAndTail(fn:parameters(), n)
end

export type function ExtractReturn(fn: type, n: any)
	assert(fn:is("function"), "expected function, got " .. fn.tag)
	return getNthFromHeadAndTail(fn:returns(), n)
end

export type function Return(fn: type)
	return ExtractReturn(fn, 1)
end

export type function ToIntersection(a: type | {type})
	local t = types :: typeof(types)

	local components = getComponents(a)
	if #components <= 1 then
		return components[1]
	end

	return t.intersectionof(table.unpack(components))
end

export type function ToUnion(a: type | {type})
	local t = types :: typeof(types)

	local components = getComponents(a)
	if #components <= 1 then
		return components[1]
	end

	return t.unionof(table.unpack(components))
end

export type function Tuple(a: type | {type})
	local t = types :: typeof(types)

	local tbl = t.newtable()
	local components = getComponents(a)
	for i, component in components do
		tbl:setproperty(t.singleton(`v{i}`), component)
	end
	tbl:setproperty(t.singleton("unpack"), t.newfunction({ head = {tbl} }, { head = components }))
	tbl:setindexer(t.number, ToUnion(getUniqueComponents(a)))

	return tbl
end
export type Tuple1<V1> = Tuple<V1>
export type Tuple2<V1, V2> = Tuple<V1 | V2>
export type Tuple3<V1, V2, V3> = Tuple<V1 | V2 | V3>
export type Tuple4<V1, V2, V3, V4> = Tuple<V1 | V2 | V3 | V4>
export type Tuple5<V1, V2, V3, V4, V5> = Tuple<V1 | V2 | V3 | V4 | V5>

export type function UnionTuplesElementWise(a: type | {type})
	local t = types :: typeof(types)

	local tuples = getComponents(a) :: {type}

	local maxAmount = 0
	for i, tuple in tuples do
		local amount = #getComponents(tuple)
		if amount > maxAmount then
			maxAmount = amount
		end
	end

	local unionArrays: {{type}} = {}
	for i, tuple in tuples do
		local components = getComponents(tuple)
		if #components ~= maxAmount then
			error(`Tuple components must be equal in amount (Tuple #{i} has {#components}, max is {maxAmount})`)
		end
		for j = 1, maxAmount do
			unionArrays[j] = unionArrays[j] or {}
			unionArrays[j][i] = components[j] or t.singleton(nil)
		end
	end

	local unions: {type} = {}
	for i, array in unionArrays do
		unions[i] = ToUnion(array)
	end

	return Tuple(unions)
end

export type function UnionTuples(a: type | {type})
	local t = types :: typeof(types)

	local tuples = getComponents(a) :: {type}
	local withUnionedElements = UnionTuplesElementWise(tuples) :: type

	local newSelfArg: type = ToUnion(tuples)

	local unpackKey = t.singleton("unpack")
	local unionedUnpackReturns = assert(withUnionedElements:readproperty(unpackKey)):returns()
	local head = unionedUnpackReturns.head or {}

	for _, tuple in tuples do
		local func = tuple:readproperty(unpackKey) :: type
		local params = func:parameters() :: { head: {type}, tail: type? }
		params.head[1] = newSelfArg

		func:setparameters(params.head, params.tail)
		func:setreturns(unionedUnpackReturns.head, unionedUnpackReturns.tail)
		tuple:setproperty(unpackKey, func)
	end

	return ToUnion(tuples)
end

export type ResultTuple<T> = UnionTuples<Tuple<true & T> | Tuple<false & string>>

export type ReadOnly<T> = T -- TODO: bruh

--export type function ReadOnly(a: type)
--	local t = types :: typeof(types)

--	if not a:is("table") and not a:is("class") then
--		return a
--	end

--	local tbl = t.newtable()
--	for key, value in allProperties(a) :: { [type]: { hostType: type?, read: type?, write: type? } } do
--		if value.read then
--			if value.read:is("function") then
--				local params =  value.read:parameters()
--				if params.head and params.head[1] == (value.hostType or a) then
--					params.head[1] = tbl
--				end
--				value.read:setparameters(params.head, params.tail)
--			end
--			tbl:setreadproperty(key, ReadOnly(value.read))
--		end
--	end

--	local indexer = a:readindexer()
--	if indexer then
--		tbl:setindexer(indexer.index, indexer.result)
--	end

--	local mt = a:metatable()
--	if mt and mt:is("table") then
--		tbl:setmetatable(ReadOnly(mt))
--	end

--	return tbl
--end

type function allPossibleCombinationsOfComponents(a: type | {type}, intersectionsInsteadOfUnions: boolean?): {type}
	local t = types :: typeof(types)

	local components = getComponents(a) :: {type}
	local bits = #components
	if bits == 0 then
		return {}
	elseif bits == 1 then
		return components
	end

	local result: {type} = {}

	local iterations = 2 ^ bits
	for i = 1, iterations - 1 do -- note that we skip iteration 0 (empty)
		local iterationComponents = {}
		for n = 0, bits - 1 do
			if bit32.btest(i, 2 ^ n) then
				table.insert(iterationComponents, components[n + 1])
			end

		end
		if intersectionsInsteadOfUnions then
			table.insert(result, t.intersectionof(table.unpack(iterationComponents)))
		else
			table.insert(result, t.unionof(table.unpack(iterationComponents)))
		end
	end

	return result
end

export type function Array(a: type)
	local t = types :: typeof(types)

	if a:is("union") then
		local components: {type} = {}
		for _, combo in allPossibleCombinationsOfComponents(a) :: {type} do
			local tbl = t.newtable()
			tbl:setindexer(t.number, combo)
			table.insert(components, tbl)
		end
		return ToUnion(components)
	else
		local tbl = t.newtable()
		tbl:setindexer(t.number, a)
		return tbl
	end
end

local T = {}
setmetatable(T, { __index = t })

local function id<T>(x: T): T
	return x
end

T.As = id :: <T>(a: any, example: T?) -> T
T.NotNil = id :: <T>(a: T | T?) -> T
T.AsDict = id :: <T>(a: T) -> Dict<T>
T.AsStrictDict = id :: <T>(a: T) -> StrictDict<T>
T.AsArrayItem = id :: <T>(a: any, arr: T?) -> index<T, number>
T.AsReadOnly = id :: <T>(a: T) -> ReadOnly<T>

local function makeTupleFromArray(values: {any}): any
	local total = math.max(1, table.maxn(values))

	local metatable = getmetatable(values) or {}
	setmetatable(values, metatable)
	local index = metatable.__index
	local newIndex = metatable.__newindex

	local getValue: any =
		if typeof(index) == "function" then index
		elseif typeof(index) == "table" then function (self, key)
			return index[key]
		end
		else rawget
	local setValue: any =
		if typeof(newIndex) == "function" then newIndex
		elseif typeof(newIndex) == "table" then function (self, key, value)
			index[key] = value
		end
		else rawset

	local firstByteExpected = ("v"):byte()
	local zeroByte = ("0"):byte()
	local function toIndex(key: any)
		-- this is like 25% faster than `return key:sub(1, 1) == "v" and tonumber(key:sub(2)) or key`
		if typeof(key) == "string" then
			local a, b, c = key:byte(1, 3)
			if a == firstByteExpected and b then
				-- we don't do any range checks for b and c cuz it adds overhead
				-- shouldn't really matter
				if c then
					return (b - zeroByte) * 10 + c - zeroByte
				else
					return b - zeroByte
				end
			end
		end

		return key
	end
	metatable.__index = function(self, key)
		if key == "unpack" then
			return function(self)
				return table.unpack(self)
			end
		end

		return getValue(self, toIndex(key))
	end
	metatable.__newindex = function(self, key, value)
		setValue(self, toIndex(key), value)
	end
	metatable.__len = function()
		return total
	end
	metatable.__tostring = function(self)
		local str = "Tuple("
		for i, v in self :: {any} do
			if typeof(v) == "string" then
				str ..= `"{v}"`
			else
				str ..= tostring(v)
			end
			if i < total then
				str ..= ", "
			end
		end
		str ..= ")"
		return str
	end
	metatable.__serdeType = "Tuple"

	return values
end
local function makeTuple(...: any): any
	return makeTupleFromArray({...})	
end
type function makeTupleFunctionType()
	local t = types :: typeof(types)

	local overloads: {type} = {}
	for i = 1, 5 do
		local generics: {type} = {}
		for j = 1, i do
			table.insert(generics, t.generic("V" .. j))
		end
		local func = t.newfunction({ head = generics }, { head = {Tuple(ToUnion(generics))} }, generics)
		table.insert(overloads, func)
	end

	return ToIntersection(overloads)
end
T.MakeTuple = makeTuple :: makeTupleFunctionType<>
T.uple = T.MakeTuple

function newPcall(func: (...any) -> any, ...: any): any
	return T.MakeTuple(pcall(func, ...)) :: any
end
T.pcall = newPcall :: (
	& ((func: (...any) -> ()) -> UnionTuples<Tuple<true & nil> | Tuple<false & string>>)
	& (<R1>(func: (...any) -> R1) -> UnionTuples<Tuple<true & R1> | Tuple<false & string>>)
	& (<R1, R2>(func: (...any) -> (R1, R2)) -> UnionTuples<Tuple<true & R1 & R2> | Tuple<false & string & nil>>)
	& (<R1, R2, R3>(func: (...any) -> (R1, R2, R3)) -> UnionTuples<Tuple<true & R1 & R2 & R3> | Tuple<false & string & nil & nil>>)
	& (<R1, R2, R3, R4>(func: (...any) -> (R1, R2, R3, R4)) -> UnionTuples<Tuple<true & R1 & R2 & R3 & R4> | Tuple<false & string & nil & nil & nil>>)
)

export type function Print(t: any)
	print(stringify(t))
	return t
end

return T