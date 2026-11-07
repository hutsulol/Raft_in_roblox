----------------------------
--[[ MODIFIED BY ROBLOX ]]--
----------------------------

return {
	-- What saving method you would like to use
	-- Possible options:
	-- OrderedBackups: The berezaa method that ensures prevention of data loss
	-- Standard: Standard data stores. Equivalent to :GetDataStore(key):GetAsync(UserId)
	-- [[ ADDED BY ROBLOX ]] MigrateOrderedBackups: The Roblox-endorsed saving method that use Roblox Data Stores more efficiently and compatible with OrderedBackups
	SavingMethod = "MigrateOrderedBackups",

	-------------------------
	--[[ ADDED BY ROBLOX ]]--
	MigrationDataStoreScope = "global"
	-- Here, you can set the `MigrationDataStoreScope` that will be applied on
	-- the migrated data store.
	-------------------------
}
