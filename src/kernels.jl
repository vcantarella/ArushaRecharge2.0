using KernelAbstractions


"""
    compute_actual_et(pet, kc, soil_storage, soil_et) -> Float64

Calculate the actual evapotranspiration based on potential
 evapotranspiration and soil moisture conditions, according to the 1999 FAO guidelines.

# Arguments
- `pet`: Potential evapotranspiration rate
- `kc`: Crop coefficient that adjusts PET for specific vegetation type
- `soil_storage`: Current amount of water stored in the soil
- `soil_et`: Soil water threshold for evapotranspiration reduction

# Returns
- `scalar`: Actual evapotranspiration rate. Returns `pet * kc` when soil moisture is adequate 
  (soil_storage > soil_et), or a reduced rate `pet * kc * (soil_storage / soil_et)` when 
  soil moisture is limiting.

# Description
This function implements a simple soil moisture stress factor for evapotranspiration. 
When soil storage exceeds the ET threshold, actual ET equals potential ET adjusted by 
the crop coefficient. When soil storage is below the threshold, ET is linearly reduced 
based on the ratio of available to threshold soil moisture.
"""
@inline function compute_actual_et(pet, kc, soil_storage, soil_et)
    if soil_storage > soil_et
        return pet * kc
    else
        return pet * kc * (soil_storage / soil_et)
    end
end

@inline function compute_recharge(soil_storage, soil_cap, soil_ext_depth, prec)
    return max(0.0, soil_storage + prec - soil_cap * soil_ext_depth)
end

@inline function compute_eff_precip(prec, threshold)
    return min(prec, threshold)
end

@inline function compute_runoff(prec, threshold)
    return max(0.0, prec - threshold)
end

# Single unified kernel
@kernel function water_balance_step!(actet, @Const(pet), soil_storage, @Const(kc), @Const(soil_et),
    recharge, @Const(soil_cap), @Const(soil_ext_depth), eff_prec, prec, @Const(threshold), runoff)
    i = @index(Global)
    
    # Calculate actual ET
    actet[i] = compute_actual_et(pet[i], kc[i], soil_storage[i], soil_et[i])
    
    # Calculate effective precipitation and runoff
    eff_prec[i] = compute_eff_precip(prec[i], threshold[i])
    runoff[i] = compute_runoff(prec[i], threshold[i])
    
    # Calculate recharge
    recharge[i] = compute_recharge(soil_storage[i], soil_cap[i], soil_ext_depth[i], eff_prec[i])
    
    # Update soil storage
    soil_storage[i] += eff_prec[i] - actet[i] - recharge[i]
end

