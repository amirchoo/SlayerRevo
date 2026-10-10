--!strict
local HealthService = require(script.HealthService)
local TownBuilder = require(script.TownBuilder)
local WeaponService = require(script.WeaponService)
local EnemyService = require(script.EnemyService)

HealthService.start()
TownBuilder.build()
WeaponService.start()
EnemyService.start()
