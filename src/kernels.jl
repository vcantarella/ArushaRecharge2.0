using KernelAbstractions


"""
    compute_actual_et(pet, kc, soil_storage, soil_et)

Calculate the actual evapotranspiration based on potential
 evapotranspiration and soil moisture conditions, according to the 1999 FAO guidelines.

# Arguments
- `pet`: Potential evapotranspiration rate (any numeric type)
- `kc`: Crop coefficient that adjusts PET for specific vegetation type
- `soil_storage`: Current amount of water stored in the soil
- `soil_et`: Soil water threshold for evapotranspiration reduction

# Returns
Actual evapotranspiration rate (same type as input). Returns `pet * kc` when soil moisture 
is adequate (soil_storage > soil_et), or a reduced rate `pet * kc * (soil_storage / soil_et)` 
when soil moisture is limiting.

# Description
This function implements a simple soil moisture stress factor for evapotranspiration. 
When soil storage exceeds the ET threshold, actual ET equals potential ET adjusted by 
the crop coefficient. When soil storage is below the threshold, ET is linearly reduced 
based on the ratio of available to threshold soil moisture.

This function is generic and works with any numeric type (Float32, Float64, etc.).
"""
@inline function compute_actual_et(pet, kc, soil_storage, soil_et, soil_cap, soil_ext_depth)
    if soil_storage > soil_et
        return pet * kc
    else
        return pet * kc * (soil_storage / (soil_cap * soil_ext_depth))
    end
end

"""
    compute_recharge(soil_storage, soil_cap, soil_ext_depth, prec)

Calculate groundwater recharge when soil storage exceeds soil capacity.

# Arguments
- `soil_storage`: Current amount of water stored in the soil (mm)
- `soil_cap`: Soil water holding capacity per unit depth (mm/mm or dimensionless)
- `soil_ext_depth`: Depth of the soil extraction zone (mm)
- `prec`: Effective precipitation input to soil (mm)

# Returns
Groundwater recharge rate (mm, same type as input). Returns 0 if soil is not saturated,
otherwise returns the excess water that percolates below the root zone.

# Description
Recharge occurs when the sum of current soil storage and incoming precipitation
exceeds the maximum soil water holding capacity (soil_cap × soil_ext_depth).
Any excess water is assumed to percolate as recharge. The function ensures
non-negative recharge using `max(0.0, ...)`.

This function is generic and works with any numeric type (Float32, Float64, etc.).

# Example
```julia
# Soil with 100 mm capacity, currently at 95 mm, receives 10 mm precipitation
recharge = compute_recharge(95.0, 100.0, 1.0, 10.0)  # Returns 5.0 mm
```
"""
@inline function compute_recharge(soil_storage, soil_cap, soil_ext_depth, prec)
    return max(zero(soil_storage), soil_storage + prec - soil_cap * soil_ext_depth)
end

"""
    compute_eff_precip(prec, threshold)

Calculate effective precipitation that infiltrates into the soil.

# Arguments
- `prec`: Total precipitation amount (mm, any numeric type)
- `threshold`: Maximum infiltration capacity threshold (mm)

# Returns
Effective precipitation that enters the soil (mm, same type as input). Returns the minimum
of total precipitation and the infiltration threshold.

# Description
This function implements a simple infiltration excess mechanism. Precipitation up to
the threshold value infiltrates into the soil as effective precipitation. Any precipitation
exceeding the threshold becomes runoff (see `compute_runoff`). The threshold typically
depends on soil type, land use, antecedent moisture conditions, and rainfall intensity.

This function is generic and works with any numeric type (Float32, Float64, etc.).

# Example
```julia
# 15 mm rainfall with 10 mm infiltration capacity
eff_prec = compute_eff_precip(15.0, 10.0)  # Returns 10.0 mm (5 mm becomes runoff)
```
"""
@inline function compute_eff_precip(prec, threshold)
    return min(prec, threshold)
end

"""
    compute_runoff(prec, threshold)

Calculate surface runoff when precipitation exceeds infiltration capacity.

# Arguments
- `prec`: Total precipitation amount (mm, any numeric type)
- `threshold`: Maximum infiltration capacity threshold (mm)

# Returns
Surface runoff amount (mm, same type as input). Returns 0 if precipitation is below threshold,
otherwise returns the excess precipitation that does not infiltrate.

# Description
This function implements infiltration excess (Horton) overland flow. When precipitation
exceeds the soil's infiltration capacity (threshold), the excess water becomes surface
runoff. This is a complementary function to `compute_eff_precip`, ensuring that:
`prec = eff_prec + runoff`.

This function is generic and works with any numeric type (Float32, Float64, etc.).

# Example
```julia
# 15 mm rainfall with 10 mm infiltration capacity
runoff = compute_runoff(15.0, 10.0)  # Returns 5.0 mm
```

# See Also
- [`compute_eff_precip`](@ref): Calculates the infiltrating portion of precipitation
"""
@inline function compute_runoff(prec, eff_prec)
    return max(zero(prec), prec - eff_prec)
end


"""
    water_balance_timeseries!(total_actet, total_recharge, total_runoff, total_eff_prec,
                              soil_storage, prec, pet, landuse, soil,
                              thresh_prec_array, crop_coeff_array, soil_cap_array, 
                              soil_ext_depth_array, soil_et_array, n_timesteps)

Compute water balance over multiple time steps for each grid cell independently.

# Arguments
- `total_actet`: Output - cumulative actual ET (mm)
- `total_recharge`: Output - cumulative recharge (mm)
- `total_runoff`: Output - cumulative runoff (mm)
- `total_eff_prec`: Output - cumulative effective precipitation (mm)
- `soil_storage`: Input/Output - initial soil storage (read), final soil storage (written) (mm)
- `prec`: Precipitation time series [n_timesteps] (mm)
- `pet`: Potential ET time series [n_timesteps] (mm)
- `landuse`: Normalized land use indices [n_cells]
- `soil`: Normalized soil type indices [n_cells]
- `thresh_prec_array`: Infiltration threshold lookup table by land use
- `crop_coeff_array`: Crop coefficient lookup table by land use
- `soil_cap_array`: Soil capacity lookup table by soil type
- `soil_ext_depth_array`: Extraction depth lookup table by land use
- `n_timesteps`: Number of time steps to simulate

# Description

Each grid cell is processed independently through all time steps. For each cell:

1. Lookup parameters from land use and soil type indices
2. Loop through all time steps:
   - Calculate actual ET, infiltration, runoff, and recharge
   - Update soil storage
   - Accumulate fluxes
3. Write cumulative totals and final storage

The time loop is inside the kernel (GPU-optimized). Each thread processes one spatial location
through all time steps.
"""
@kernel function water_balance_timeseries!(
    total_actet, total_recharge, total_runoff, total_prec,
    soil_storage,  # initial/final storage
    @Const(prec), @Const(pet), @Const(landuse), @Const(soil),
    @Const(thresh_prec_array), @Const(crop_coeff_array),
    @Const(soil_cap_array), @Const(soil_ext_depth_array),
    n_timesteps
)
    i = @index(Global)  # grid cell index

    threshold = thresh_prec_array[landuse[i]]
    kc = crop_coeff_array[landuse[i]]
    soil_cap = soil_cap_array[soil[i]]
    soil_ext_depth = soil_ext_depth_array[landuse[i]]
    soil_et = soil_ext_depth * soil_cap * 0.5f0
    # Example: ET threshold as half of extraction depth
    
    storage = soil_storage[i]  # local copy
    
    # Initialize accumulators for this cell (use zero(T) to match input type)
    T = typeof(storage)
    actet_sum = zero(T)
    recharge_sum = zero(T)
    runoff_sum = zero(T)
    prec_sum = zero(T)
    
    # Time loop for this grid cell
    @inbounds for t in 1:n_timesteps
        # Compute water balance for time step t
        eff_prec_t = compute_eff_precip(prec[t], threshold)
        runoff_t = compute_runoff(prec[t], eff_prec_t)
        recharge_t = compute_recharge(storage, soil_cap, soil_ext_depth, eff_prec_t)
        
        # Update storage
        storage += eff_prec_t - recharge_t
        actet_t = compute_actual_et(pet[t], kc, storage, soil_et, soil_cap, soil_ext_depth)
        storage -= actet_t
        # Accumulate
        actet_sum += actet_t
        recharge_sum += recharge_t
        runoff_sum += runoff_t
        prec_sum += prec[t]
    end
    
    # Write final results
    total_actet[i] = actet_sum
    total_recharge[i] = recharge_sum
    total_runoff[i] = runoff_sum
    total_prec[i] = prec_sum
    soil_storage[i] = storage
end
