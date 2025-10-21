using ArushaRecharge
using KernelAbstractions
using Test

# Needed arrays:
# actet, pet, soil_storage, kc, soil_et,
#    recharge, soil_cap, soil_ext_depth,
# eff_prec, prec, threshold, runoff
actet = zeros(3)  ## mm
pet = [1.5, 1.5, 1.5]   ## mm
soil_storage = [60.0, 40.0, 50.0] ## mm
soil_storage0 = copy(soil_storage)
kc = [0.8, 0.9, 1.0]
soil_et = [30.0, 30.0, 30.0] ##
recharge = zeros(3) ## mm
soil_cap = [100.0, 100.0, 100.0] ##
soil_ext_depth = [50.0, 50.0, 50.0] ##
eff_prec = zeros(3) ## mm
prec = [10.0, 5.0, 0.0] ## mm
threshold = [8.0, 6.0, 4.0]
runoff = zeros(3) ## mm

dev = CPU()
ev = ArushaRecharge.water_balance_step!(dev, length(actet))(actet, pet, soil_storage, kc, soil_et,
    recharge, soil_cap, soil_ext_depth, eff_prec, prec, threshold, runoff;
    ndrange = length(actet))
synchronize(dev)

@test all(soil_storage0 .+ eff_prec .- actet .- recharge .≈ soil_storage)