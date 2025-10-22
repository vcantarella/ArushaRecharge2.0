module ArushaRecharge
    include("kernels.jl")
    using JLD2
    using CSV, DataFrames
    using Dates
    include("lookuptable_management.jl")
    @load "julia_datasets/normalized_landuse.jld2" normalized_landuse landuse_mapping
    @load "julia_datasets/normalized_soiltype.jld2" normalized_soil soiltype_mapping
    @load "julia_datasets/elevation.jld2" elevation
    @load "julia_datasets/slope.jld2" slope

    model_landuse = normalized_landuse[normalized_landuse .> 0]
    model_soil = normalized_soil[normalized_landuse .> 0]

    # Lookup tables based on land use codes
    threshold_precipitation_lookup = Dict(
        1 => 0.6,
        21 => 1.5,
        31 => 1.3,
        32 => 1.2,
        33 => 1.2,
        36 => 1.0,
        307 => 0.9
    )
    thresh_prec_array = lookup_table_to_array(threshold_precipitation_lookup, landuse_mapping)

    crop_coefficient_lookup = Dict(
        1 => 0.6,
        21 => 1.5,
        31 => 1.3,
        32 => 1.2,
        33 => 1.2,
        36 => 1.0,
        307 => 0.9
    )
    crop_coeff_array = lookup_table_to_array(crop_coefficient_lookup, landuse_mapping)

    soil_ext_depth_lookup = Dict(
        1 => 300,
        21 => 1000,
        31 => 1000,
        32 => 1000,
        33 => 1000,
        36 => 600,
        307 => 1000
    )
    soil_ext_depth_array = lookup_table_to_array(soil_ext_depth_lookup, landuse_mapping)

    # Lookup tables based on soil type codes
    soil_capacity_lookup = Dict(
        10 => 0.13,
        11 => 0.12
    )
    soil_cap_array = lookup_table_to_array(soil_capacity_lookup, soiltype_mapping)

    prec_df = CSV.read("arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
    pet_df = CSV.read("arusha_recharge/Climate data/ET_2020.csv", DataFrame)
    prec = prec_df[!, "Precipitation (mm/day)"]
    pet = pet_df[!, "ET (mm/day)"]
    timestamps = prec_df[!, "Date"]
    timestamps = Date.(timestamps, dateformat"dd/mm/yyyy")
    months = month.(timestamps)
    periods = sort(unique(months))
    # Initialize results DataFrame where we will store monthly water balance results
    ResultDf = DataFrame(Month = Int[], 
        Total_ActET = Float64[],
        Total_Recharge = Float64[],
        Total_Runoff = Float64[],
        Total_EffPrec = Float64[])
    # initialize soil storage as half of the soil capacity
    n_cells = length(model_landuse)
    soil_storage = [soil_cap_array[model_soil[i]] / 2 for i in 1:n_cells]
    # prepare arrays to hold cumulative results
    total_actet = zeros(n_cells)
    total_recharge = zeros(n_cells)
    total_runoff = zeros(n_cells)
    total_eff_prec = zeros(n_cells)
    # prepare a copy of the arrays to hold the previous month's totals
    prev_total_actet = zeros(n_cells)
    prev_total_recharge = zeros(n_cells)
    prev_total_runoff = zeros(n_cells)
    prev_total_eff_prec = zeros(n_cells)
    #initialize the device
    dev = CPU()
    # Loop over each month
    for period in periods
        println("Processing month: $period")
        month_indices = findall(months .== period)
        n_timesteps = length(month_indices)
        kernel = water_balance_timeseries!(dev, n_cells)
        ev = kernel(
            total_actet, total_recharge, total_runoff, total_eff_prec,
            soil_storage,
            prec[month_indices], pet[month_indices],
            model_landuse, model_soil,
            thresh_prec_array, crop_coeff_array,
            soil_cap_array, soil_ext_depth_array,
            n_timesteps;
            ndrange = n_cells
        )
        synchronize(dev)
        ## The part below can also be done on the GPU for efficiency
        # Calculate monthly totals by subtracting previous totals (on GPU)
        monthly_actet = sum(total_actet .- prev_total_actet)./n_cells
        monthly_recharge = sum(total_recharge .- prev_total_recharge)./n_cells
        monthly_runoff = sum(total_runoff .- prev_total_runoff)./n_cells
        monthly_eff_prec = sum(total_eff_prec .- prev_total_eff_prec)./n_cells
        # Append monthly results to DataFrame
        push!(ResultDf, (period, monthly_actet, monthly_recharge, monthly_runoff, monthly_eff_prec))
        # Update previous totals for next iteration (on GPU)
        copyto!(prev_total_actet, total_actet)
        copyto!(prev_total_recharge, total_recharge)
        copyto!(prev_total_runoff, total_runoff)
        copyto!(prev_total_eff_prec, total_eff_prec)
    end

    # Now we have calculated the yearly water balance. 
    # Save the maps by mapping the results back to the full array
    final_soil_storage = zeros(size(normalized_landuse))
    final_soil_storage[normalized_landuse .> 0] = soil_storage
    final_recharge = zeros(size(normalized_landuse))
    final_recharge[normalized_landuse .> 0] = total_recharge
    final_runoff = zeros(size(normalized_landuse))
    final_runoff[normalized_landuse .> 0] = total_runoff
    final_actet = zeros(size(normalized_landuse))
    final_actet[normalized_landuse .> 0] = total_actet
    
    # Plot the maps using ArchGDAL
    import ArchGDAL as AG
    @load "julia_datasets/geotransform_landuse.jld2" gt
    @load "julia_datasets/projection_landuse.jld2" p
    AG.create(
    "./julia_datasets/annual_water_balance.tif",
    driver = AG.getdriver("GTiff"),
    width=size(normalized_landuse, 2),
    height=size(normalized_landuse, 1),
    nbands=4,
    dtype=Float64
    ) do dataset
        AG.write!(dataset, final_soil_storage, 1)
        AG.write!(dataset, final_recharge, 2)
        AG.write!(dataset, final_runoff, 3)
        AG.write!(dataset, final_actet, 4)
        AG.setgeotransform!(dataset, gt)
        AG.setproj!(dataset, p)
    end

    display(ResultDf)
end