--!strict
-- Small helpers shared by server and client.

local Util = {}

function Util.clamp(x: number, a: number, b: number): number
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.smoothstep(edge0: number, edge1: number, x: number): number
	if edge0 == edge1 then
		return if x < edge0 then 0 else 1
	end
	local t = Util.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

function Util.lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, Util.clamp(t, 0, 1))
end

-- Exponential smoothing that is independent of frame rate.
function Util.damp(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

function Util.dampVector(current: Vector3, target: Vector3, rate: number, dt: number): Vector3
	return target + (current - target) * math.exp(-rate * dt)
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function Util.angleBetweenFlat(a: Vector3, b: Vector3): number
	local fa, fb = Util.flatUnit(a), Util.flatUnit(b)
	return math.deg(math.acos(Util.clamp(fa:Dot(fb), -1, 1)))
end

function Util.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value :: any do
		out[k] = Util.deepCopy(v)
	end
	return (out :: any) :: T
end

-- Fills missing keys in `target` from `template`, recursively.
function Util.reconcile(target: { [any]: any }, template: { [any]: any })
	for k, v in template do
		if target[k] == nil then
			target[k] = Util.deepCopy(v)
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and #v == 0 then
			Util.reconcile(target[k], v)
		end
	end
end

function Util.weightedPick<T>(rng: Random, entries: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, e in entries do
		total += math.max(0, weightOf(e))
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	for _, e in entries do
		roll -= math.max(0, weightOf(e))
		if roll <= 0 then
			return e
		end
	end
	return entries[#entries]
end

function Util.formatTime(seconds: number): string
	seconds = math.max(0, seconds)
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%d:%05.2f", m, s)
end

function Util.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

function Util.ordinal(n: number): string
	local suffix = "th"
	local lastTwo = n % 100
	if lastTwo < 11 or lastTwo > 13 then
		local last = n % 10
		if last == 1 then
			suffix = "st"
		elseif last == 2 then
			suffix = "nd"
		elseif last == 3 then
			suffix = "rd"
		end
	end
	return tostring(n) .. suffix
end

-- Layered value noise. Returns roughly -1..1.
function Util.fbm(x: number, z: number, octaves: number, seed: number, lacunarity: number?, gain: number?): number
	local lac = lacunarity or 2
	local g = gain or 0.5
	local amp, freq, sum, norm = 1, 1, 0, 0
	for i = 1, octaves do
		sum += math.noise(x * freq, z * freq, seed + i * 17.31) * amp
		norm += amp
		amp *= g
		freq *= lac
	end
	return sum / norm * 1.6
end

-- Ridged noise for mountain ranges. Returns 0..1.
function Util.ridged(x: number, z: number, octaves: number, seed: number): number
	local amp, freq, sum, norm = 1, 1, 0, 0
	for i = 1, octaves do
		local n = 1 - math.abs(math.noise(x * freq, z * freq, seed + i * 9.7) * 1.6)
		sum += n * n * amp
		norm += amp
		amp *= 0.5
		freq *= 2.1
	end
	return Util.clamp(sum / norm, 0, 1)
end

-- Deterministic hash of integers into 0..1.
function Util.hash01(a: number, b: number?, c: number?): number
	local h = math.sin(a * 127.1 + (b or 0) * 311.7 + (c or 0) * 74.7) * 43758.5453
	return h - math.floor(h)
end

function Util.shuffle<T>(rng: Random, list: { T })
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

function Util.countKeys(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Disconnects or destroys everything handed to it.
export type Maid = {
	Give: (self: Maid, item: any) -> any,
	Clean: (self: Maid) -> (),
}

function Util.newMaid(): Maid
	local items: { any } = {}
	local maid = {}
	function maid.Give(_self, item: any)
		table.insert(items, item)
		return item
	end
	function maid.Clean(_self)
		for i = #items, 1, -1 do
			local item = items[i]
			items[i] = nil
			local kind = typeof(item)
			if kind == "RBXScriptConnection" then
				item:Disconnect()
			elseif kind == "Instance" then
				item:Destroy()
			elseif kind == "function" then
				item()
			elseif kind == "thread" then
				pcall(task.cancel, item)
			elseif kind == "table" and item.Destroy then
				item:Destroy()
			end
		end
	end
	return (maid :: any) :: Maid
end

return Util
