require "busted.runner" ()

--- @type RCLootCouncil
local addon = dofile(".specs/AddonLoader.lua").LoadToc("RCLootCouncil.toc")
---@type RCVotingFrame
local VotingFrame = addon.modules.RCVotingFrame
local Council = addon.Require "Data.Council"
local Player = addon.Require "Data.Player"

dofile(".specs/EmulatePlayerLogin.lua")
describe("#VotingFrame #ChangeResponse", function()
	addon.Print = addon.noop
	dofile(".specs/Helpers/SetupRaid.lua")(20)

	local snapshot
	before_each(function()
		snapshot = assert:snapshot()
		wipe(addon.db.global.verTestCandidates)
		addon.player = addon.Require "Data.Player":Get("player")
		WoWAPI_FireUpdate(GetTime() + 5000) -- Trigger "UpdateCandidatesInGroup"
		addon:CallModule("masterlooter")
		addon:GetActiveModule("masterlooter"):NewML(addon.player)
		addon:GetActiveModule("masterlooter"):Test { 159366, 165584, }
		WoWAPI_FireUpdate(GetTime() + 10)
		RCLootCouncilML:StartSession()
	end)
	after_each(function()
		RCLootCouncilML:EndSession()
		WoWAPI_FireUpdate()
		snapshot:revert()
	end)

	it("ReannounceOrRequestRoll should set responses to 'WAIT' when called as non-roll", function()
		local receivedSpy = spy.new()
		addon.Require "Services.Comms":Subscribe(addon.PREFIXES.MAIN, "ResponseWait", receivedSpy)

		WoWAPI_FireUpdate(GetTime() + 20)
		VotingFrame:ReannounceOrRequestRoll(true, 1, false, false, false)
		WoWAPI_FireUpdate(GetTime() + 30)

		assert.spy(receivedSpy).was.called(1)
		local lootTable = VotingFrame:GetLootTable()
		for name, v in pairs(lootTable[1].candidates) do
			if name ~= addon.player.name then -- We might already have autopassed
				assert.Equal("WAIT", v.response)
			end
		end
		-- Session 2 should remain untouched.
		for name, v in pairs(lootTable[2].candidates) do
			assert.Equal("NOTHING", v.response)
		end
	end)

	it("ReannounceOrRequestRoll should not touch responses when 'isRoll' is true", function()
		local receivedSpy = spy.new()
		addon.Require "Services.Comms":Subscribe(addon.PREFIXES.MAIN, "ResponseWait", receivedSpy)

		WoWAPI_FireUpdate(GetTime() + 20)
		VotingFrame:ReannounceOrRequestRoll(true, 1, true, false, false)
		WoWAPI_FireUpdate(GetTime() + 30)

		assert.spy(receivedSpy).was.called(0)
		for _, data in ipairs(VotingFrame:GetLootTable()) do
			for _, v in pairs(data.candidates) do
				assert.Equal("NOTHING", v.response)
			end
		end
	end)

	it("ReannounceOrRequestRoll should use old system if council has pre v3.13.0", function()
		addon.db.global.verTestCandidates = {
			[(GetRaidRosterInfo(2))] = {"3.12.0", nil, time()}
		}
		Council:Add(Player:Get((GetRaidRosterInfo(2))))
		local responseWaitSpy = spy.new()
		addon.Require "Services.Comms":Subscribe(addon.PREFIXES.MAIN, "ResponseWait", responseWaitSpy)
		local changeResponseSpy = spy.new()
		addon.Require "Services.Comms":Subscribe(addon.PREFIXES.MAIN, "change_response", changeResponseSpy)

		WoWAPI_FireUpdate(GetTime() + 20)
		VotingFrame:ReannounceOrRequestRoll(true, 1, false, false, false)
		WoWAPI_FireUpdate(GetTime() + 30)

		assert.spy(responseWaitSpy).was.called(0)
		assert.spy(changeResponseSpy).was.called(GetNumGroupMembers())
	end)
end)