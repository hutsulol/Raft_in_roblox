return {
 ModelName="Raft_fishing_spot", TemplateName="Fisherman_R6",
 WeightMinKg=.4, WeightMaxKg=3.2,
 Price=20, CatchChance=.75, WaitMin=5, WaitMax=9, WalkSpeed=3.5,
 WorkStart=6.5, WorkEnd=19,
 NightWaitMultiplier=5, -- Same catch chance; nighttime waiting takes five times longer.
 -- Image content IDs, not catalogue clothing IDs. Set by asset import.
 Shirt="rbxassetid://91458829920963", Pants="rbxassetid://98453104262126",
 Events={TakeRod=.95, Cast=.84, PutFish=1.02, ReturnRod=.95},
}
