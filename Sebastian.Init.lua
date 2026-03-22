--!strict
--!optimize 2
--!native

--[[
╔══════════════════════════════════════════════════════════════════════════╗
║  SEBASTIAN  v1.0  —  The Last Cleanup Module You'll Ever Need            ║
║  Parallel-array engine · zero-alloc Add · --!native compiled             ║
║                                                                          ║
║  TRACKING                                                                ║
║    :Add(obj, key?, method?)       track any object                       ║
║    :Give(obj)                     quick add, no options                  ║
║    :Has(obj | key)   -> bool      check if tracked                       ║
║    .key = value                   Maid-style assign                      ║
║                                                                          ║
║  SIGNALS                                                                 ║
║    :Connect(signal, fn, key?)     permanent connection                   ║
║    :Once(signal, fn, key?)        fires once then auto-disconnects       ║
║    :Many({{signal,fn}, ...})      connect many at once                   ║
║                                                                          ║
║  RUNSERVICE                                                              ║
║    :OnFrame(fn, key?)             Heartbeat every frame                  ║
║    :OnStep(fn, key?)              Stepped every physics step             ║
║    :Bind(name, priority, fn)      BindToRenderStep + auto-unbind         ║
║                                                                          ║
║  INSTANCES & CLASSES                                                     ║
║    :Make(Class, ...)              Class.new(...) + track                 ║
║    :Spawn(className, props?)      Instance.new + set props + track       ║
║    :Clone(instance)               clone + track                          ║
║    :Promise(promise)              track Promise; auto-cancel on clean    ║
║                                                                          ║
║  REMOVAL                                                                 ║
║    :Remove(key)                   remove by key + cleanup                ║
║    :RemoveList(k1, k2, ...)       remove many keys + cleanup             ║
║    :Drop(key)                     remove by key, NO cleanup              ║
║    :Free(obj)                     remove by reference + cleanup          ║
║                                                                          ║
║  GETTERS                                                                 ║
║    :Get(key)          -> any?     object at key                          ║
║    :GetAll()          -> table    frozen table of all named objects      ║
║    :Count()           -> number   total tracked objects                  ║
║    :Keys()            -> {string} all named keys                         ║
║    :Info()            -> table    full debug snapshot                    ║
║                                                                          ║
║  LINKING                                                                 ║
║    :Link(instance)                auto-Destroy when instance destroyed   ║
║    :LinkPlayer(player)            auto-Destroy when player leaves        ║
║    :LinkToInstances(...)          link multiple instances at once        ║
║    :When(signal, pred?)           auto-Clean when signal fires           ║
║                                                                          ║
║  SUB-GROUPS                                                              ║
║    :Group(key?)                   child Sebastian, cleaned with parent   ║
║    :ClearGroup(key)               clear only one named sub-group         ║
║                                                                          ║
║  HOOKS                                                                   ║
║    :BeforeClean(fn)               called before every Clean()            ║
║    :AfterClean(fn)                called after every Clean()             ║
║                                                                          ║
║  UTILITIES                                                               ║
║    :Debounce(fn, wait)            ignore calls faster than wait secs     ║
║    :Throttle(fn, interval)        trailing-edge coalesce                 ║
║    :Every(fn, secs)   -> stop()   repeat every N secs                    ║
║    :After(fn, secs)   -> thread   run once after N secs                  ║
║    :Next(fn)          -> thread   run next resumption cycle              ║
║                                                                          ║
║  LIFECYCLE                                                               ║
║    :Clean()                       destroy all, reusable                  ║
║    :Destroy()                     destroy all, permanently done          ║
║    :AsFunction()      -> fn       returns a fn that calls Clean()        ║
║    :Delay(secs)       -> cancel() scheduled Clean, cancelable            ║
║    s()                            calling as a function = Clean()        ║
╚══════════════════════════════════════════════════════════════════════════╝
]]

-- ══════════════════════════════════════════════════
--   STDLIB CACHE
--   local upvalues resolve in O(1) vs global hash
-- ══════════════════════════════════════════════════
local t_insert   = table.insert
local t_clear    = table.clear
local t_clone    = table.clone
local t_freeze   = table.freeze
local rawget_    = rawget
local rawset_    = rawset
local type_      = type
local typeof_    = typeof
local select_    = select
local tostring_  = tostring
local error_     = error
local assert_    = assert
local pcall_     = pcall
local newproxy_  = newproxy
local setmt      = setmetatable
local getmt      = getmetatable
local co_running = coroutine.running
local co_status  = coroutine.status
local tk_cancel  = task.cancel
local tk_defer   = task.defer
local tk_delay   = task.delay
local tk_spawn   = task.spawn
local os_clock   = os.clock

-- ── Services ──────────────────────────────────────
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

-- ── Internal Markers ──────────────────────────────
local FN_MARKER     = newproxy_() -- plain function
local THREAD_MARKER = newproxy_() -- coroutine/thread
local LINK_INDEX    = newproxy_() -- default singleton key for :Link()

-- ── Named Object Storage (weak-keyed) ─────────────
local NamedStorage: { [any]: { [any]: any } } = setmt({}, { __mode = "k" })

-- ══════════════════════════════════════════════════
--   PUBLIC TYPES  (full autocomplete in Studio)
-- ══════════════════════════════════════════════════

--- A Sebastian instance. Every method is fully typed for Studio autocomplete.
export type Sebastian = {

	-- ── TRACKING ──────────────────────────────────────────────────────────
	--- Track any object for automatic cleanup.
	--- Cleanup method is inferred from object type unless overridden.
	---
	--- | Type                  | Default cleanup     |
	--- |-----------------------|---------------------|
	--- | RBXScriptConnection   | :Disconnect()       |
	--- | function              | object()            |
	--- | Instance              | :Destroy()          |
	--- | thread                | task.cancel()       |
	--- | table w/ Destroy      | :Destroy()          |
	---
	--- ```lua
	--- s:Add(part)
	--- s:Add(tween, "Cancel")
	--- s:Add(part, "Destroy", "Floor")
	--- ```
	Add: (self: Sebastian, object: any, key: any?, cleanupMethod: (string | boolean)?) -> any,

	--- Quick-add shorthand. Identical to `:Add(object)`.
	---
	--- ```lua
	--- s:Give(part)
	--- s:Give(function() print("done") end)
	--- ```
	Give: (self: Sebastian, object: any) -> any,

	--- Returns `true` if the object or named key is currently tracked.
	---
	--- ```lua
	--- if s:Has("MyPart") then ... end
	--- if s:Has(connection) then ... end
	--- ```
	Has: (self: Sebastian, objectOrKey: any) -> boolean,

	-- ── SIGNALS ───────────────────────────────────────────────────────────
	--- Connect a callback to a signal and auto-track the connection.
	---
	--- ```lua
	--- s:Connect(workspace.ChildAdded, function(child)
	---     print(child.Name)
	--- end)
	--- ```
	Connect: (self: Sebastian, signal: RBXScriptSignal, fn: (...any) -> (), key: any?) -> RBXScriptConnection,

	--- Connect a callback that fires **once** then auto-disconnects.
	---
	--- ```lua
	--- s:Once(humanoid.Died, function()
	---     print("died!")
	--- end)
	--- ```
	Once: (self: Sebastian, signal: RBXScriptSignal, fn: (...any) -> (), key: any?) -> RBXScriptConnection,

	--- Connect many signals at once. Pass an array of `{signal, fn}` pairs.
	---
	--- ```lua
	--- s:Many({
	---     { part.Touched,    onTouched },
	---     { humanoid.Died,   onDied   },
	--- })
	--- ```
	Many: (self: Sebastian, pairs: { { any } }) -> { RBXScriptConnection },

	-- ── RUNSERVICE ────────────────────────────────────────────────────────
	--- Connect to `RunService.Heartbeat` (fires every frame).
	---
	--- ```lua
	--- s:OnFrame(function(dt)
	---     part.CFrame = part.CFrame * CFrame.new(0, 0, speed * dt)
	--- end)
	--- ```
	OnFrame: (self: Sebastian, fn: (dt: number) -> (), key: any?) -> RBXScriptConnection,

	--- Connect to `RunService.Stepped` (fires every physics step).
	---
	--- ```lua
	--- s:OnStep(function(time, dt) end)
	--- ```
	OnStep: (self: Sebastian, fn: (time: number, dt: number) -> (), key: any?) -> RBXScriptConnection,

	--- `RunService:BindToRenderStep` + auto-unbind on Clean.
	---
	--- ```lua
	--- s:Bind("CamRig", Enum.RenderPriority.Camera.Value, function(dt) end)
	--- ```
	Bind: (self: Sebastian, name: string, priority: number, fn: (dt: number) -> ()) -> (),

	-- ── INSTANCES & CLASSES ───────────────────────────────────────────────
	--- Construct from a class table or function and track the result.
	---
	--- ```lua
	--- local sig  = s:Make(Signal)
	--- local part = s:Make(Instance, "Part")
	--- ```
	Make: (self: Sebastian, class: any, ...any) -> any,

	--- `Instance.new(className)`, set properties, track it.
	---
	--- ```lua
	--- local part = s:Spawn("Part", {
	---     Size     = Vector3.new(4, 1, 4),
	---     Anchored = true,
	---     Parent   = workspace,
	--- })
	--- ```
	Spawn: (self: Sebastian, className: string, properties: { [string]: any }?) -> Instance,

	--- Clone an Instance and track the clone.
	---
	--- ```lua
	--- local cloned = s:Clone(template)
	--- cloned.Parent = workspace
	--- ```
	Clone: (self: Sebastian, instance: Instance) -> Instance,

	--- Track a roblox-lua-promise v4 object. Auto-cancels on Clean.
	---
	--- ```lua
	--- s:Promise(fetchData(userId)):andThen(print):catch(warn)
	--- ```
	Promise: (self: Sebastian, promise: any) -> any,

	-- ── REMOVAL ───────────────────────────────────────────────────────────
	--- Remove the object at `key` and run its cleanup.
	---
	--- ```lua
	--- s:Remove("Floor")
	--- ```
	Remove: (self: Sebastian, key: any) -> Sebastian,

	--- Remove and clean multiple keys at once.
	---
	--- ```lua
	--- s:RemoveList("A", "B", "C")
	--- ```
	RemoveList: (self: Sebastian, ...any) -> Sebastian,

	--- Remove the object at `key` WITHOUT running cleanup.
	---
	--- ```lua
	--- s:Drop("Floor")  -- untracked but NOT destroyed
	--- ```
	Drop: (self: Sebastian, key: any) -> Sebastian,

	--- Remove an object by direct reference and run its cleanup.
	---
	--- ```lua
	--- local part = s:Add(Instance.new("Part"))
	--- s:Free(part)
	--- ```
	Free: (self: Sebastian, object: any) -> boolean,

	-- ── GETTERS ───────────────────────────────────────────────────────────
	--- Return the object stored at `key`, or nil if not found.
	---
	--- ```lua
	--- local tween = s:Get("IntroTween")
	--- if tween then tween:Play() end
	--- ```
	Get: (self: Sebastian, key: any) -> any?,

	--- Return a frozen shallow copy of all named objects.
	---
	--- ```lua
	--- for key, obj in s:GetAll() do print(key, obj) end
	--- ```
	GetAll: (self: Sebastian) -> { [any]: any },

	--- Returns the total number of currently tracked objects.
	---
	--- ```lua
	--- print(s:Count())  --> 7
	--- ```
	Count: (self: Sebastian) -> number,

	--- Returns an array of every named key currently in use.
	---
	--- ```lua
	--- print(s:Keys())  --> {"Floor", "Tween"}
	--- ```
	Keys: (self: Sebastian) -> { string },

	--- Returns a debug snapshot of the Sebastian's state.
	---
	--- ```lua
	--- print(s:Info())
	--- ```
	Info: (self: Sebastian) -> { [string]: any },

	-- ── LINKING ───────────────────────────────────────────────────────────
	--- Calls `:Destroy()` automatically when `instance` is destroyed.
	--- Pass `allowMultiple = true` to keep multiple links active.
	---
	--- ```lua
	--- s:Link(character)
	--- ```
	Link: (self: Sebastian, instance: Instance, allowMultiple: boolean?) -> RBXScriptConnection,

	--- Link to multiple Instances at once. Returns a child Sebastian managing the links.
	---
	--- ```lua
	--- local links = s:LinkToInstances(a, b, c)
	--- links:Destroy()  -- sever all without cleaning s
	--- ```
	LinkToInstances: (self: Sebastian, ...Instance) -> Sebastian,

	--- Calls `:Destroy()` automatically when `player` leaves the game.
	---
	--- ```lua
	--- s:LinkPlayer(player)
	--- ```
	LinkPlayer: (self: Sebastian, player: Player) -> (),

	--- Calls `:Clean()` the next time `signal` fires.
	--- An optional predicate filters which firings count.
	---
	--- ```lua
	--- s:When(roundEnded)
	--- s:When(valueChanged, function(v) return v == false end)
	--- ```
	When: (self: Sebastian, signal: RBXScriptSignal, predicate: ((...any) -> boolean)?) -> RBXScriptConnection,

	-- ── SUB-GROUPS ────────────────────────────────────────────────────────
	--- Create a child Sebastian tracked by this one.
	--- Passing `key` stores it under a named slot (retrievable via `:Get`).
	---
	--- ```lua
	--- local combat = s:Group("combat")
	--- combat:Connect(signal, fn)
	--- s:ClearGroup("combat")
	--- ```
	Group: (self: Sebastian, key: any?) -> Sebastian,

	--- Clear only the named child group, leaving everything else intact.
	---
	--- ```lua
	--- s:ClearGroup("combat")
	--- ```
	ClearGroup: (self: Sebastian, key: any) -> (),

	--- @deprecated Use `:Group()` instead.
	Extend: (self: Sebastian) -> Sebastian,

	-- ── HOOKS ─────────────────────────────────────────────────────────────
	--- Register a callback that runs **before** every Clean().
	---
	--- ```lua
	--- s:BeforeClean(function() print("cleaning…") end)
	--- ```
	BeforeClean: (self: Sebastian, fn: () -> ()) -> (),

	--- Register a callback that runs **after** every Clean().
	---
	--- ```lua
	--- s:AfterClean(function() print("all clean!") end)
	--- ```
	AfterClean: (self: Sebastian, fn: () -> ()) -> (),

	-- ── UTILITIES ─────────────────────────────────────────────────────────
	--- Returns a debounced wrapper of `fn`.
	--- Calls within `wait` seconds of the previous accepted call are ignored.
	---
	--- ```lua
	--- local onTouch = s:Debounce(function(hit)
	---     print("touched!")
	--- end, 0.5)
	--- s:Connect(part.Touched, onTouch)
	--- ```
	Debounce: (self: Sebastian, fn: (...any) -> (), wait: number) -> (...any) -> (),

	--- Returns a throttled wrapper of `fn`.
	--- Rapid calls are coalesced; only the latest fires after `interval` seconds.
	---
	--- ```lua
	--- local save = s:Throttle(function() dataStore:SetAsync(key, data) end, 1)
	--- ```
	Throttle: (self: Sebastian, fn: (...any) -> (), interval: number) -> (...any) -> (),

	--- Repeat `fn` every `seconds` seconds. Returns a `stop()` function.
	---
	--- ```lua
	--- local stop = s:Every(function() print("ping") end, 5)
	--- stop()  -- stop early
	--- ```
	Every: (self: Sebastian, fn: () -> (), seconds: number) -> () -> (),

	--- Run `fn` once after `seconds` seconds. Auto-cancelled on Clean.
	---
	--- ```lua
	--- s:After(function() print("done") end, 5)
	--- ```
	After: (self: Sebastian, fn: () -> (), seconds: number) -> thread,

	--- Run `fn` on the next resumption cycle (`task.defer`). Auto-cancelled on Clean.
	---
	--- ```lua
	--- s:Next(function() print("next frame") end)
	--- ```
	Next: (self: Sebastian, fn: () -> ()) -> thread,

	-- ── LIFECYCLE ─────────────────────────────────────────────────────────
	--- Clean all tracked objects (LIFO order). Sebastian remains reusable.
	---
	--- ```lua
	--- s:Clean()
	--- s:Add(newPart)  -- still works
	--- ```
	Clean: (self: Sebastian) -> (),

	--- Clean all objects and permanently destroy this Sebastian.
	---
	--- ```lua
	--- s:Destroy()
	--- ```
	Destroy: (self: Sebastian) -> (),

	--- Returns a `() -> ()` function that calls Clean() when invoked.
	---
	--- ```lua
	--- return s:AsFunction()
	--- ```
	AsFunction: (self: Sebastian) -> () -> (),

	--- Schedule a Clean() after `seconds` seconds. Returns a cancel function.
	---
	--- ```lua
	--- local cancel = s:Delay(10)
	--- cancel()  -- abort the countdown
	--- ```
	Delay: (self: Sebastian, seconds: number) -> () -> (),
}

--- The Sebastian module — call `Sebastian.new()` to create an instance.
export type SebastianClass = {
	--- Construct a new Sebastian instance.
	---
	--- ```lua
	--- local s = Sebastian.new()
	--- ```
	new: () -> Sebastian,

	--- Returns `true` if the given object is a Sebastian instance.
	---
	--- ```lua
	--- print(Sebastian.Is(s))  --> true
	--- ```
	Is: (object: any) -> boolean,
}

-- Internal shape (never exposed)
type _Internal = Sebastian & {
	_obj:      { any },
	_method:   { any },
	_key:      { any },
	_size:     number,
	_cleaning:  boolean,
	_destroyed: boolean,
	_hooks:    { before: { () -> () }, after: { () -> () } },
}

-- ══════════════════════════════════════════════════
--   INTERNAL HELPERS
-- ══════════════════════════════════════════════════

-- Resolve cleanup marker — ordered by frequency in typical Roblox code.
local function _resolve(object: any, method: any?): any
	if method then return method end
	local t = typeof_(object)
	if t == "RBXScriptConnection" then return "Disconnect"   end
	if t == "function"            then return FN_MARKER      end
	if t == "Instance"            then return "Destroy"      end
	if t == "thread"              then return THREAD_MARKER  end
	if t == "table" then
		local d  = rawget_(object, "Destroy")    or rawget_(object, "destroy")
		if typeof_(d)  == "function" then return "Destroy"    end
		local dc = rawget_(object, "Disconnect") or rawget_(object, "disconnect")
		if typeof_(dc) == "function" then return "Disconnect" end
		local cn = rawget_(object, "cancel")
		if typeof_(cn) == "function" then return "cancel"     end
		local mt = getmt(object)
		if mt then
			local idx = rawget_(mt, "__index")
			if type_(idx) == "table" then
				if typeof_(idx.Destroy)    == "function" then return "Destroy"    end
				if typeof_(idx.Disconnect) == "function" then return "Disconnect" end
				if typeof_(idx.cancel)     == "function" then return "cancel"     end
			end
		end
	end
	error_("[Sebastian] Cannot resolve cleanup for '"
		.. typeof_(object) .. "': " .. tostring_(object), 3)
end

-- Execute one cleanup.
local function _exec(object: any, method: any)
	if method == FN_MARKER then
		object()
		return
	end
	if method == THREAD_MARKER then
		if co_running() ~= object then
			local ok = pcall_(tk_cancel, object)
			if not ok then
				local t = object
				tk_defer(function() tk_cancel(t) end)
			end
		end
		return
	end
	local fn = (object :: any)[method]
	if fn then pcall_(fn, object) end
end

-- Helpers for NamedStorage
local function _namedSet(self: any, key: any, obj: any)
	local store = NamedStorage[self]
	if not store then store = {}; NamedStorage[self] = store end
	rawset_(store, key, obj)
end
local function _namedGet(self: any, key: any): any?
	local store = NamedStorage[self]
	return if store then rawget_(store, key) else nil
end
local function _namedRemove(self: any, key: any): any?
	local store = NamedStorage[self]
	if store then
		local obj = rawget_(store, key)
		if obj ~= nil then rawset_(store, key, nil); return obj end
	end
	return nil
end

-- Swap-remove from parallel arrays (O(1)).
local function _swapRemove(self: _Internal, i: number)
	local n = rawget_(self, "_size")
	if i ~= n then
		local oa = rawget_(self, "_obj")
		local ma = rawget_(self, "_method")
		local ka = rawget_(self, "_key")
		oa[i] = oa[n]; ma[i] = ma[n]; ka[i] = ka[n]
	end
	rawget_(self, "_obj")[n]    = nil
	rawget_(self, "_method")[n] = nil
	rawget_(self, "_key")[n]    = nil
	rawset_(self, "_size", n - 1)
end

-- Core push (zero-alloc)
local function _push(self: any, object: any, method: any, key: any): any
	local n = rawget_(self, "_size") + 1
	rawset_(self, "_size", n)
	rawget_(self, "_obj")[n]    = object
	rawget_(self, "_method")[n] = method
	rawget_(self, "_key")[n]    = key
	return object
end

-- ══════════════════════════════════════════════════
--   CLASS + MAID-STYLE __newindex
-- ══════════════════════════════════════════════════
local Seb = {}
Seb.__index = Seb

-- Maid-style: s.myKey = value
-- Assigning nil removes and cleans the old object.
-- Assigning a new value replaces the old one cleanly.
Seb.__newindex = function(raw: { [any]: any }, key: any, value: any)
	-- Pass-through internal fields and real methods
	if type_(key) == "string" and (string.sub(key, 1, 1) == "_" or rawget_(Seb, key) ~= nil) then
		rawset_(raw, key, value)
		return
	end
	local self = raw :: any
	-- Clean out the old occupant at this key, if any
	local oldObj = _namedRemove(self, key)
	if oldObj ~= nil then
		local oa = rawget_(self, "_obj")
		local ma = rawget_(self, "_method")
		local ka = rawget_(self, "_key")
		local sz = rawget_(self, "_size")
		for i = sz, 1, -1 do
			if oa[i] == oldObj then
				_exec(oldObj, ma[i])
				_swapRemove(self :: any, i)
				break
			end
		end
	end
	if value ~= nil then
		local method = _resolve(value, nil)
		_namedSet(self, key, value)
		_push(self, value, method, key)
	end
end

-- ══════════════════════════════════════════════════
--   CONSTRUCTOR
-- ══════════════════════════════════════════════════

--[=[
	@class Sebastian
	High-performance unified cleanup module.
	Trove speed · Janitor named keys · Maid property-assign · Keeper utilities.

	Zero per-task allocations via parallel arrays.
	Compiled to native code via `--!native`.

	```lua
	local Sebastian = require(path.to.Sebastian)
	local s = Sebastian.new()
	```
]=]
function Seb.new(): Sebastian
	return setmt({
		_obj       = {} :: { any },
		_method    = {} :: { any },
		_key       = {} :: { any },
		_size      = 0,
		_cleaning  = false,
		_destroyed = false,
		_hooks     = { before = {}, after = {} },
	}, Seb) :: any
end

--[=[
	Returns `true` if `object` is a Sebastian instance.

	@param object any
	@return boolean
]=]
function Seb.Is(object: any): boolean
	return type_(object) == "table" and getmt(object) == Seb
end

-- ── Guard helpers ──────────────────────────────────
local function _guardAdd(self: any)
	if rawget_(self, "_destroyed") then error_("[Sebastian] Cannot call Add — Destroy()d", 3) end
	if rawget_(self, "_cleaning")  then error_("[Sebastian] Cannot call Add — cleaning",   3) end
end
local function _guard(self: any, name: string)
	if rawget_(self, "_destroyed") then error_("[Sebastian] Cannot call "..name.." — Destroy()d", 3) end
end

-- ══════════════════════════════════════════════════
--   TRACKING
-- ══════════════════════════════════════════════════

function Seb:Add(object: any, key: any?, cleanupMethod: (string | boolean)?): any
	_guardAdd(self)
	local method = _resolve(object, cleanupMethod)
	if key ~= nil then
		local oldObj = _namedRemove(self, key)
		if oldObj ~= nil then
			local oa = rawget_(self, "_obj")
			local ma = rawget_(self, "_method")
			local sz = rawget_(self, "_size")
			for i = sz, 1, -1 do
				if oa[i] == oldObj then
					_exec(oldObj, ma[i])
					_swapRemove(self, i)
					break
				end
			end
		end
		_namedSet(self, key, object)
	end
	return _push(self, object, method, key)
end

function Seb:Give(object: any): any
	return Seb.Add(self, object, nil, nil)
end

function Seb:Has(objectOrKey: any): boolean
	if type_(objectOrKey) == "string" or type_(objectOrKey) ~= "string" then
		-- Check named storage first
		local store = NamedStorage[self]
		if store and rawget_(store, objectOrKey) ~= nil then return true end
		-- Check by reference
		local oa = rawget_(self, "_obj")
		local sz = rawget_(self, "_size")
		for i = 1, sz do
			if oa[i] == objectOrKey then return true end
		end
	end
	return false
end

-- ══════════════════════════════════════════════════
--   SIGNALS
-- ══════════════════════════════════════════════════

function Seb:Connect(signal: RBXScriptSignal, fn: (...any) -> (), key: any?): RBXScriptConnection
	_guardAdd(self)
	return Seb.Add(self, signal:Connect(fn), key, nil)
end

function Seb:Once(signal: RBXScriptSignal, fn: (...any) -> (), key: any?): RBXScriptConnection
	_guardAdd(self)
	local conn: RBXScriptConnection
	conn = signal:Once(function(...)
		fn(...)
		if not rawget_(self, "_cleaning") then
			Seb.Free(self, conn)
		end
	end)
	return Seb.Add(self, conn, key, nil)
end

function Seb:Many(pairs: { { any } }): { RBXScriptConnection }
	_guardAdd(self)
	local result: { RBXScriptConnection } = {}
	for _, pair in pairs do
		t_insert(result, Seb.Connect(self,
			pair[1] :: RBXScriptSignal,
			pair[2] :: (...any) -> ()))
	end
	return result
end

-- ══════════════════════════════════════════════════
--   RUNSERVICE
-- ══════════════════════════════════════════════════

function Seb:OnFrame(fn: (dt: number) -> (), key: any?): RBXScriptConnection
	_guardAdd(self)
	return Seb.Connect(self, RunService.Heartbeat, fn :: (...any) -> (), key)
end

function Seb:OnStep(fn: (time: number, dt: number) -> (), key: any?): RBXScriptConnection
	_guardAdd(self)
	return Seb.Connect(self, RunService.Stepped, fn :: (...any) -> (), key)
end

function Seb:Bind(name: string, priority: number, fn: (dt: number) -> ())
	_guardAdd(self)
	RunService:BindToRenderStep(name, priority, fn)
	_push(self, function() RunService:UnbindFromRenderStep(name) end, FN_MARKER, nil)
	rawset_(self, "_size", rawget_(self, "_size"))
end

-- ══════════════════════════════════════════════════
--   INSTANCES & CLASSES
-- ══════════════════════════════════════════════════

function Seb:Make(class: any, ...: any): any
	_guardAdd(self)
	local obj
	if type_(class) == "table" then
		obj = class.new(...)
	elseif type_(class) == "function" then
		obj = class(...)
	else
		error_("[Sebastian] Make requires a table (.new) or constructor function", 2)
	end
	return Seb.Add(self, obj, nil, nil)
end

function Seb:Spawn(className: string, properties: { [string]: any }?): Instance
	_guardAdd(self)
	local inst = Instance.new(className)
	if properties then
		for prop, val in properties do
			(inst :: any)[prop] = val
		end
	end
	Seb.Add(self, inst, nil, nil)
	return inst
end

function Seb:Clone(instance: Instance): Instance
	_guardAdd(self)
	local cloned = instance:Clone()
	Seb.Add(self, cloned, nil, nil)
	return cloned
end

function Seb:Promise(promise: any): any
	_guardAdd(self)
	assert_(
		type_(promise) == "table"
			and type_(promise.getStatus) == "function"
			and type_(promise.finally)   == "function"
			and type_(promise.cancel)    == "function",
		"[Sebastian] Promise() expects roblox-lua-promise v4"
	)
	if promise:getStatus() == "Started" then
		promise:finally(function()
			if rawget_(self, "_cleaning") then return end
			Seb.Free(self, promise)
		end)
		Seb.Add(self, promise, nil, "cancel")
	end
	return promise
end

-- ══════════════════════════════════════════════════
--   REMOVAL
-- ══════════════════════════════════════════════════

function Seb:Remove(key: any): Sebastian
	_guard(self, "Remove")
	local obj = _namedRemove(self, key)
	if obj == nil then return self :: any end
	local oa = rawget_(self, "_obj")
	local ma = rawget_(self, "_method")
	local sz = rawget_(self, "_size")
	for i = sz, 1, -1 do
		if oa[i] == obj then
			local m = ma[i]
			_swapRemove(self, i)
			_exec(obj, m)
			break
		end
	end
	return self :: any
end

function Seb:RemoveList(...: any): Sebastian
	local n = select_("#", ...)
	for i = 1, n do Seb.Remove(self, (select_(i, ...))) end
	return self :: any
end

function Seb:Drop(key: any): Sebastian
	_guard(self, "Drop")
	local obj = _namedRemove(self, key)
	if obj == nil then return self :: any end
	local oa = rawget_(self, "_obj")
	local sz = rawget_(self, "_size")
	for i = sz, 1, -1 do
		if oa[i] == obj then _swapRemove(self, i); break end
	end
	return self :: any
end

function Seb:Free(object: any): boolean
	_guard(self, "Free")
	local oa = rawget_(self, "_obj")
	local ma = rawget_(self, "_method")
	local ka = rawget_(self, "_key")
	local sz = rawget_(self, "_size")
	for i = sz, 1, -1 do
		if oa[i] == object then
			local m = ma[i]
			local k = ka[i]
			_swapRemove(self, i)
			if k ~= nil then _namedRemove(self, k) end
			_exec(object, m)
			return true
		end
	end
	return false
end

-- ══════════════════════════════════════════════════
--   GETTERS + DEBUG
-- ══════════════════════════════════════════════════

function Seb:Get(key: any): any?
	return _namedGet(self, key)
end

function Seb:GetAll(): { [any]: any }
	local store = NamedStorage[self]
	return if store then t_freeze(t_clone(store)) else {}
end

function Seb:Count(): number
	return rawget_(self, "_size")
end

function Seb:Keys(): { string }
	local store = NamedStorage[self]
	local result: { string } = {}
	if store then
		for k in store do
			if type_(k) == "string" then t_insert(result, k) end
		end
	end
	return result
end

function Seb:Info(): { [string]: any }
	return {
		count       = rawget_(self, "_size"),
		keys        = Seb.Keys(self),
		isCleaning  = rawget_(self, "_cleaning"),
		isDestroyed = rawget_(self, "_destroyed"),
	}
end

-- ══════════════════════════════════════════════════
--   LINKING
-- ══════════════════════════════════════════════════

function Seb:Link(instance: Instance, allowMultiple: boolean?): RBXScriptConnection
	_guardAdd(self)
	local indexKey = if allowMultiple then newproxy_(false) else LINK_INDEX
	local conn = instance.Destroying:Connect(function()
		Seb.Destroy(self)
	end)
	return Seb.Add(self, conn, indexKey, "Disconnect")
end

function Seb:LinkToInstances(...: Instance): Sebastian
	local child = Seb.new()
	for i = 1, select_("#", ...) do
		local inst = select_(i, ...)
		if typeof_(inst) == "Instance" then
			child:Add(Seb.Link(self, inst, true), nil, "Disconnect")
		end
	end
	return child :: any
end

function Seb:LinkPlayer(player: Player)
	_guardAdd(self)
	Seb.Add(self, Players.PlayerRemoving:Connect(function(leaving: Player)
		if leaving == player then Seb.Destroy(self) end
	end), nil, nil)
end

function Seb:When(signal: RBXScriptSignal, predicate: ((...any) -> boolean)?): RBXScriptConnection
	_guardAdd(self)
	local conn: RBXScriptConnection
	conn = signal:Connect(function(...)
		if predicate and not predicate(...) then return end
		Seb.Free(self, conn)
		conn:Disconnect()
		Seb.Clean(self)
	end)
	return Seb.Add(self, conn, nil, nil)
end

-- ══════════════════════════════════════════════════
--   SUB-GROUPS
-- ══════════════════════════════════════════════════

function Seb:Group(key: any?): Sebastian
	_guardAdd(self)
	if key ~= nil then
		local existing = _namedGet(self, key)
		if existing and Seb.Is(existing) then return existing :: any end
	end
	local child = Seb.new()
	Seb.Add(self, child, key, nil)
	return child :: any
end

function Seb:ClearGroup(key: any)
	local child = _namedGet(self, key)
	if child and Seb.Is(child) then
		(child :: any):Clean()
	end
end

function Seb:Extend(): Sebastian
	return Seb.Group(self, nil)
end

-- ══════════════════════════════════════════════════
--   HOOKS
-- ══════════════════════════════════════════════════

function Seb:BeforeClean(fn: () -> ())
	t_insert(rawget_(self, "_hooks").before, fn)
end

function Seb:AfterClean(fn: () -> ())
	t_insert(rawget_(self, "_hooks").after, fn)
end

-- ══════════════════════════════════════════════════
--   UTILITIES
-- ══════════════════════════════════════════════════

function Seb:Debounce(fn: (...any) -> (), wait: number): (...any) -> ()
	local last   = -math.huge
	local active = true
	Seb.Add(self, function() active = false end, nil, nil)
	return function(...)
		if not active then return end
		local now = os_clock()
		if now - last >= wait then
			last = now
			fn(...)
		end
	end
end

function Seb:Throttle(fn: (...any) -> (), interval: number): (...any) -> ()
	local pending   = false
	local latestArgs: { any } = {}
	local pendingT:   thread? = nil
	local active = true
	Seb.Add(self, function()
		active = false
		if pendingT then pcall_(tk_cancel, pendingT) end
	end, nil, nil)
	return function(...)
		if not active then return end
		latestArgs = { ... }
		if not pending then
			pending = true
			local t: thread
			t = tk_delay(interval, function()
				if not active then return end
				pending = false; pendingT = nil
				fn(table.unpack(latestArgs))
			end)
			pendingT = t
		end
	end
end

function Seb:Every(fn: () -> (), seconds: number): () -> ()
	_guardAdd(self)
	local running = true
	local bg = tk_spawn(function()
		while running do
			task.wait(seconds)
			if running then fn() end
		end
	end)
	local stop: () -> () = function()
		if not running then return end
		running = false
		pcall_(tk_cancel, bg)
	end
	Seb.Add(self, stop, nil, nil)
	return stop
end

function Seb:After(fn: () -> (), seconds: number): thread
	_guardAdd(self)
	local t: thread = if seconds > 0 then tk_delay(seconds, fn) else tk_spawn(fn)
	if co_status(t) ~= "dead" then Seb.Add(self, t, nil, nil) end
	return t
end

function Seb:Next(fn: () -> ()): thread
	_guardAdd(self)
	local t: thread = tk_defer(fn)
	if co_status(t) ~= "dead" then Seb.Add(self, t, nil, nil) end
	return t
end

-- ══════════════════════════════════════════════════
--   LIFECYCLE
-- ══════════════════════════════════════════════════

function Seb:Clean()
	if rawget_(self, "_cleaning") or rawget_(self, "_destroyed") then return end
	rawset_(self, "_cleaning", true)

	local hooks = rawget_(self, "_hooks")
	for _, fn in hooks.before do pcall_(fn) end

	local oa = rawget_(self, "_obj")
	local ma = rawget_(self, "_method")
	local ka = rawget_(self, "_key")

	-- Reverse-order LIFO loop (Janitor technique)
	local i = rawget_(self, "_size")
	while i > 0 do
		local obj = oa[i]; local method = ma[i]
		oa[i] = nil; ma[i] = nil; ka[i] = nil
		i -= 1
		if obj ~= nil then _exec(obj, method) end
	end
	rawset_(self, "_size", 0)

	local store = NamedStorage[self]
	if store then t_clear(store); NamedStorage[self] = nil end

	rawset_(self, "_cleaning", false)

	for _, fn in hooks.after do pcall_(fn) end
end

function Seb:Destroy()
	Seb.Clean(self)
	rawset_(self, "_destroyed", true)
	t_clear(rawget_(self, "_obj"))
	t_clear(rawget_(self, "_method"))
	t_clear(rawget_(self, "_key"))
	setmt(self :: any, nil)
end

function Seb:AsFunction(): () -> ()
	return function() Seb.Clean(self) end
end

function Seb:Delay(seconds: number): () -> ()
	local cancelled = false
	local t = tk_delay(seconds, function()
		if not cancelled then Seb.Clean(self) end
	end)
	return function()
		cancelled = true
		pcall_(tk_cancel, t)
	end
end

-- __call = Clean()
Seb.__call = function(self: any) Seb.Clean(self) end
Seb.__tostring = function() return "Sebastian" end

return Seb :: SebastianClass
