----------------------------
--[[ NEW FILE BY ROBLOX ]]--
----------------------------

--[[
    MigrateOrderedBackups.Lua

	Roblox Migration Module:

	This script will take DataStore2 data stored with `OrderedBackups` and migrate it to a standard Roblox Data Store.
	
	MigrateOrderedBackups:Get() will try to retrieve migrated data from the migrated Data Store, and if that data does not exist, it will
	instead retrieve it from the OrderedBackups Data Stores.
	
	MigrateOrderedBackups:Set() will send data to standard Roblox Data Store named  rather than to the OrderedBackups Data Stores.
	
	By simply changing the setting from `OrderedBackups` to `MigrateOrderedBackups` the experience should see a smooth data migration with no extra
	action needed by the developer.
--]]


--------------
-- Services --
--------------
local DataStoreServiceRetriever = require(script.Parent.Parent.DataStoreServiceRetriever)
local Promise = require(script.Parent.Parent.Promise)
local Settings = require(script.Parent.Parent.Settings)
local OrderedBackups = require(script.Parent.OrderedBackups)

----------------------
-- Class Definition --
----------------------
local MigrateOrderedBackups = {}
MigrateOrderedBackups.__index = MigrateOrderedBackups

--[[
    Gets the data in the DataStore.
    This will be data in the migrated data store, if it exists. Otherwise, it
    will fallback to retrieving the data from the OrderedBackups Data Stores.
--]]
function MigrateOrderedBackups:Get()

	-- try retrieving from Standard Data Store `[dataStoreName]`
	return Promise.async(function(resolve)
		resolve(self.migratedDataStore:GetAsync(self.dataStore2.UserId))
	end):andThen(function(data)
		-- return data if it was found
		if data ~= nil then
			return data
		else
			-- try retrieving from `OrderedBackups` Data Stores
			return self.orderedBackups:Get()
		end
	end)
end

--[[
    Save the data to the DataStore.
    This function saves to the migrated data store, unlike the `OrderedBackups`
    method.
    ---------------------------------------------------------------------------
    
    value: the value to save to the data store.
--]]
function MigrateOrderedBackups:Set(value)

	-- store to Standard Data Store `[dataStoreName]` with [userId]:[value]
	return Promise.async(function(resolve)
		self.migratedDataStore:SetAsync(self.dataStore2.UserId, value)
		resolve()
	end)
end

--[[
    Class constructor.
    ------------------

    dataStore2: The DataStore2 instance that utilizes this saving method.
--]]
function MigrateOrderedBackups.new(dataStore2)
	local dataStoreService = DataStoreServiceRetriever.Get()
	local dataStoreKey = dataStore2.Name .. "/" .. dataStore2.UserId -- name of the original `OrderedBackups` Data Stores
	local migratedDataStoreKey  = dataStore2.Name
	local migratedDataStoreScope = Settings.MigrationDataStoreScope or "global" -- the optionally defined scope -- see `Settings.lua` to set this value

	local info = {
		dataStore2 = dataStore2,
		dataStore = dataStoreService:GetDataStore(dataStoreKey),
		orderedDataStore = dataStoreService:GetOrderedDataStore(dataStoreKey),
		migratedDataStore = dataStoreService:GetDataStore(migratedDataStoreKey, migratedDataStoreScope),
		orderedBackups = OrderedBackups.new(dataStore2)
	}

	return setmetatable(info, MigrateOrderedBackups)
end

-- export the class definition
return MigrateOrderedBackups