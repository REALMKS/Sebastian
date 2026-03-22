<div align="center">

# Sebastian

**The last cleanup module you'll ever need for Roblox.**

Zero-allocation parallel-array engine · Trove style · Janitor named keys · Maid property-assign · 40 methods · Full Studio autocomplete · `--!native` compiled

[![Luau](https://img.shields.io/badge/Luau-strict-blue?style=flat-square)](https://luau-lang.org)
[![Version](https://img.shields.io/badge/version-1.0-green?style=flat-square)](#)

</div>

---

## What is Sebastian?

Sebastian tracks objects — connections, instances, threads, functions, promises — and destroys all of them when you call `Clean()` or `Destroy()`. It replaces Trove, Janitor, and Maid simultaneously with a single file and a unified API.

```lua
local s = Sebastian.new()

s:Connect(humanoid.Died, onDied)
s:Bind("CamRig", Enum.RenderPriority.Camera.Value, onFrame)
s:Add(tween, "Cancel", "IntroTween")
s:Link(character) -- s:Destroy() fires automatically when character is removed

-- later...
s:Get("IntroTween"):Play()
s:Destroy()
```

---

## Why not just use Trove / Janitor / Maid?

| | Trove | Janitor | Maid | **Sebastian** |
|---|:---:|:---:|:---:|:---:|
| Auto type detection | ✅ | ✅ | ✅ | ✅ |
| Named keys | ❌ | ✅ | ❌ | ✅ |
| `s.slot = value` Maid-style | ❌ | ❌ | ✅ | ✅ |
| `:Connect()` shorthand | ✅ | ❌ | ❌ | ✅ |
| `:Once()` / `:Many()` | ❌ | ❌ | ❌ | ✅ |
| `:OnFrame()` / `:OnStep()` | ❌ | ❌ | ❌ | ✅ |
| `:Spawn()` with properties | ❌ | ❌ | ❌ | ✅ |
| Sub-groups | ✅ | ✅ | ❌ | ✅ |
| `:When()` signal trigger | ❌ | ❌ | ❌ | ✅ |
| `BeforeClean` / `AfterClean` hooks | ❌ | ❌ | ❌ | ✅ |
| Debounce / Throttle / Every | ❌ | ❌ | ❌ | ✅ |
| Debug (Count / Keys / Info) | ❌ | ❌ | ❌ | ✅ |
| Zero per-task allocations | ❌ | ❌ | ❌ | ✅ |
| `--!native` compiled | ❌ | ❌ | ❌ | ✅ |
| Full Studio autocomplete | ❌ | ❌ | ❌ | ✅ |
| Zero dependencies | ✅ | ❌ | ✅ | ✅ |

---

## Installation

**Option A — Copy the file**

Copy `Sebastian/Init.lua` into your project as a `ModuleScript`, e.g. `ReplicatedStorage.Sebastian`.

**Option B — Rojo**

```
src/
└── shared/
    └── Sebastian.lua  →  ReplicatedStorage.Sebastian
```

Then require it anywhere:

```lua
local Sebastian = require(ReplicatedStorage.Sebastian)
```

---

## Quick Start

```lua
local Sebastian = require(ReplicatedStorage.Sebastian)

local s = Sebastian.new()

-- Connect a signal
s:Connect(workspace.ChildAdded, function(child)
    print(child.Name .. " added")
end)

-- Track an Instance
local part = s:Spawn("Part", { Parent = workspace, Anchored = true })

-- Named key — old object cleaned automatically when key is reused
s:Add(TweenService:Create(part, TweenInfo.new(1), { Size = Vector3.one }), "Cancel", "Tween")
s:Get("Tween"):Play()

-- Tie lifetime to the part
s:Link(part)

-- Everything cleaned when part is destroyed
```

---

## API Reference

### Constructor

| Method | Description |
|--------|-------------|
| `Sebastian.new()` | Create a new Sebastian instance |
| `Sebastian.Is(obj)` | Returns `true` if `obj` is a Sebastian |

---

### Tracking

Track any object for automatic cleanup. The cleanup method is inferred from the object's type unless you override it.

| Object Type | Default Cleanup |
|---|---|
| `RBXScriptConnection` | `:Disconnect()` |
| `function` | `object()` |
| `Instance` | `:Destroy()` |
| `thread` | `task.cancel()` |
| `table` with `.Destroy` | `:Destroy()` |
| `table` with `.Disconnect` | `:Disconnect()` |

```lua
-- Basic
s:Add(part)                         -- Destroy() inferred
s:Add(connection)                   -- Disconnect() inferred
s:Add(function() cleanup() end)     -- called directly

-- Custom method
s:Add(tween, nil, "Cancel")         -- tween:Cancel()

-- Named key — retrieval, replacement, and targeted removal
s:Add(part, "Floor", "Destroy")
s:Add(newPart, "Floor", "Destroy")  -- old part Destroyed automatically

-- Quick add (no options)
s:Give(part)

-- Check if something is tracked
s:Has("Floor")     -- true/false
s:Has(connection)  -- true/false
```

**Maid-style property assign:**

```lua
s.walk = connection         -- tracked under "walk"
s.walk = newConnection      -- old disconnected, new tracked
s.walk = nil                -- disconnected and cleared
```

---

### Signals

```lua
-- Permanent connection
s:Connect(signal, fn)
s:Connect(signal, fn, "MyKey")

-- Fires once then auto-disconnects
s:Once(humanoid.Died, function()
    print("died!")
end)

-- Connect many at once
s:Many({
    { part.Touched,    onTouched  },
    { part.TouchEnded, onEnded    },
    { humanoid.Died,   onDied     },
})
```

---

### RunService

```lua
-- Heartbeat (every frame)
s:OnFrame(function(dt)
    character:TranslateBy(Vector3.new(0, 0, speed * dt))
end)

-- Stepped (every physics step)
s:OnStep(function(time, dt)
    -- physics logic
end)

-- BindToRenderStep — auto-unbinds on Clean
s:Bind("CameraShake", Enum.RenderPriority.Camera.Value, function(dt)
    camera.CFrame = computeShake(dt)
end)
```

---

### Instances & Classes

```lua
-- Construct from a class and track
local signal = s:Make(Signal)
local folder = s:Make(Instance, "Folder")

-- Instance.new with properties in one call
local part = s:Spawn("Part", {
    Size     = Vector3.new(4, 1, 4),
    Anchored = true,
    Parent   = workspace,
})

-- Clone and track
local cloned = s:Clone(template)
cloned.Parent = workspace

-- Track a Promise (evaera/roblox-lua-promise v4)
s:Promise(fetchData(userId))
    :andThen(function(data) print(data) end)
    :catch(warn)
-- Promise is cancelled automatically if s:Clean() is called first
```

---

### Removal

```lua
-- By named key — runs cleanup
s:Remove("Floor")
s:RemoveList("PartA", "PartB", "Conn1")

-- By named key — NO cleanup (take back ownership)
s:Drop("Floor")

-- By direct reference — runs cleanup
local part = s:Add(Instance.new("Part"))
s:Free(part)
```

---

### Getters & Debug

```lua
local tween = s:Get("IntroTween")   -- nil if not found
local all   = s:GetAll()            -- frozen { [key]: object }

s:Count()  -- number of tracked objects
s:Keys()   -- { "Floor", "Tween", ... }
s:Info()   -- { count=3, keys={...}, isCleaning=false, isDestroyed=false }
```

---

### Linking

```lua
-- Auto-Destroy when an Instance is destroyed
s:Link(character)
s:Link(part, true)  -- allowMultiple = true keeps both links active

-- Auto-Destroy when player leaves
s:LinkPlayer(player)

-- Link to multiple instances — returns a child Sebastian for manual control
local links = s:LinkToInstances(a, b, c)
links:Destroy()  -- sever all links without cleaning s

-- Auto-Clean when a signal fires
s:When(roundEnded)
s:When(valueChanged, function(v) return v == false end)
```

---

### Sub-Groups

Sub-groups let you partition tracked objects so you can clear one section independently without touching the rest.

```lua
local parent = Sebastian.new()

-- Anonymous sub-group
local vfx = parent:Group()
vfx:Add(spawnParticles())

-- Named sub-group — accessible via :Get or :Group("key")
local combat = parent:Group("combat")
combat:Connect(signal, handler)

-- Clear only the combat group
parent:ClearGroup("combat")

-- Clear parent — all sub-groups are cleaned too
parent:Clean()
```

---

### Lifecycle Hooks

```lua
s:BeforeClean(function()
    print("about to clean")
end)

s:AfterClean(function()
    print("all clean")
end)
```

---

### Utilities

**Debounce** — ignore calls faster than `wait` seconds:

```lua
local onTouch = s:Debounce(function(hit)
    takeDamage(hit)
end, 0.5)

s:Connect(part.Touched, onTouch)
```

**Throttle** — coalesce rapid calls, fire trailing edge:

```lua
local save = s:Throttle(function()
    dataStore:SetAsync(key, data)
end, 1)

dataChanged:Connect(save)
```

**Repeat on an interval:**

```lua
local stop = s:Every(function()
    spawnEnemy()
end, 5)

stop()  -- stop early
```

**Delayed execution:**

```lua
-- Run once after N seconds
s:After(function()
    showEndScreen()
end, 3)

-- Run on the next resumption cycle
s:Next(function()
    updateUI()
end)
```

---

### Lifecycle

```lua
-- Clean all tracked objects — Sebastian is reusable after this
s:Clean()
s:Add(newPart)  -- still works

-- Clean and permanently destroy — errors if used again
s:Destroy()

-- Get a plain function that calls Clean() — useful for callbacks
local destructor = s:AsFunction()
someSystem.onStop = destructor

-- Schedule a Clean after N seconds — returns cancel()
local cancel = s:Delay(10)
cancel()  -- abort

-- Calling the Sebastian as a function also triggers Clean()
s()
```

---

## Patterns & Real-World Examples

### Character Controller

```lua
local function onCharacterAdded(character: Model)
    local s = Sebastian.new()

    local humanoid = character:WaitForChild("Humanoid") :: Humanoid

    s:Connect(humanoid.Died, function()
        print("died")
    end)

    s:Bind("CharacterUpdate", Enum.RenderPriority.Character.Value, function(dt)
        -- per-frame logic
    end)

    s:Link(character)  -- s:Destroy() when character is removed
end

Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
```

---

### Per-Player Server State

```lua
local playerSessions: { [Player]: Sebastian.Sebastian } = {}

Players.PlayerAdded:Connect(function(player)
    local s = Sebastian.new()

    s:Add(PlayerData.new(player), "Data")
    s:Add(createLeaderstats(player), "Stats")

    s:LinkPlayer(player)
    playerSessions[player] = s
end)

Players.PlayerRemoving:Connect(function(player)
    playerSessions[player] = nil
end)

local function getPlayerData(player: Player)
    local s = playerSessions[player]
    return s and s:Get("Data")
end
```

---

### Round System with Sub-Groups

```lua
local game = Sebastian.new()  -- lives for the entire server session

game:BeforeClean(function()
    print("Server shutting down")
end)

local function startRound()
    local round = game:Group("round")

    round:Every(function()
        spawnEnemy()
    end, 10)

    round:Connect(roundEndedSignal, function()
        game:ClearGroup("round")  -- clean only this round
        startRound()              -- start fresh
    end)
end

startRound()
```

---

### Tween Replacement with Named Key

```lua
local s = Sebastian.new()

local function playTween(goal: { [string]: any })
    -- "ActiveTween" is Cancelled and replaced automatically
    local tween = s:Add(
        TweenService:Create(part, TweenInfo.new(0.5), goal),
        "ActiveTween",
        "Cancel"
    )
    tween:Play()
end

playTween({ Position = Vector3.new(0, 10, 0) })
task.wait(0.2)
playTween({ Position = Vector3.new(0, 0, 0) })  -- previous tween Cancelled

s:Destroy()
```

---

### Debounce + Touched

```lua
local s = Sebastian.new()

local onTouch = s:Debounce(function(hit: BasePart)
    local character = hit.Parent
    local humanoid  = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:TakeDamage(10)
    end
end, 0.5)

s:Connect(damagePart.Touched, onTouch)
s:Link(damagePart)
```

---

## Performance Notes

Sebastian is designed to produce as little garbage as possible on every `Add()` call.

**Parallel arrays instead of per-task tables:**

```
Standard approach:   _tasks = { {obj, method, key}, ... }
                     → 1 new table allocation per Add()

Sebastian:           _obj[]    = { obj,    obj,    ... }
                     _method[] = { method, method, ... }
                     _key[]    = { key,    key,    ... }
                     → zero allocations per Add()
```

**Other optimisations:**

- All stdlib functions cached as local upvalues (`rawget`, `rawset`, `table.clear`, `task.cancel`, etc.) — O(1) access vs global hash lookup
- `rawget` / `rawset` used for all internal state — skips `__index` metamethod on every guard check
- Swap-remove (O(1)) instead of `table.remove(i)` (O(n)) for removal
- Weak-keyed `NamedStorage` table — destroyed Sebastians never block the garbage collector
- Thread cancellation follows Janitor's safe-cancel pattern — never cancels the currently running coroutine
- `--!optimize 2` + `--!native` — Luau compiles the module to native machine code

---

## Compatibility Aliases

If you're migrating from Trove, Janitor, or Maid, these aliases work out of the box:

| Old call | Sebastian equivalent |
|---|---|
| `trove:Add(obj)` | `s:Add(obj)` ✅ |
| `trove:Connect(sig, fn)` | `s:Connect(sig, fn)` ✅ |
| `trove:Construct(Class)` | `s:Make(Class)` ✅ |
| `trove:BindToRenderStep(n, p, fn)` | `s:Bind(n, p, fn)` ✅ |
| `trove:AttachToInstance(inst)` | `s:Link(inst)` ✅ |
| `trove:Extend()` | `s:Extend()` ✅ |
| `trove:Clean()` | `s:Clean()` ✅ |
| `janitor:Add(obj, m, key)` | `s:Add(obj, key, m)` ✅ |
| `janitor:Get(key)` | `s:Get(key)` ✅ |
| `janitor:Remove(key)` | `s:Remove(key)` ✅ |
| `janitor:LinkToInstance(inst)` | `s:Link(inst)` ✅ |
| `maid:GiveTask(obj)` | `s:Give(obj)` ✅ |
| `maid.slot = value` | `s.slot = value` ✅ |

---
