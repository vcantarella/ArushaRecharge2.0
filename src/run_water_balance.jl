using JLD2
using CSV, DataFrames
using Dates
using Statistics
using KernelAbstractions
using Metal
using CSV, DataFrames, Dates

"""
    run_water_balance(prec, pet, timestamp, backend_type::Symbol=:CPU)

Run the water balance model with the given precipitation and potential evapotranspiration data.
Supports multiyear analysis by processing data on a year-month basis.

# Arguments
- `prec`: Vector of precipitation values (mm/day) for all timesteps
- `pet`: Vector of potential evapotranspiration values (mm/day) for all timesteps
- `timestamp`: Vector of Date objects corresponding to each timestep in prec and pet
- `backend_type`: Symbol indicating computation backend, either `:CPU` or `:GPU` (default: `:CPU`)

# Returns
- `ResultDf`: DataFrame with monthly water balance results containing:
  - `Year`: Year of the period
  - `Month`: Month of the period (1-12)
  - `ActET`: Actual evapotranspiration (mm/month)
  - `Recharge`: Groundwater recharge (mm/month)
  - `Runoff`: Surface runoff (mm/month)
  - `Prec`: Total precipitation (mm/month)
  - `ChangeinStorage`: Change in soil storage (mm/month)

# Details
The function processes data by unique (year, month) combinations, making it suitable for
multiyear analyses. Each year-month period is processed independently, with soil storage
carried forward between periods.

# Example
```julia


# Load data with timestamps
prec_df = CSV.read("arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
pet_df = CSV.read("arusha_recharge/Climate data/ET_2020.csv", DataFrame)
prec = prec_df[!, "Precipitation (mm/day)"]
pet = pet_df[!, "ET (mm/day)"]
timestamps = Date.(prec_df[!, "Date"], dateformat"dd/mm/yyyy")

# Run on CPU
results_cpu = run_water_balance(prec, pet, timestamps, :CPU)

# Run on GPU (requires Metal.jl on Apple Silicon)
results_gpu = run_water_balance(prec, pet, timestamps, :GPU)

# Analyze results by year
using Statistics

yearly_recharge = combine(groupby(results_cpu, :Year), :Recharge => sum)
```
"""
function run_water_balance(prec, pet, timestamp, backend_type::Symbol=:CPU)

    # Validate backend type
    if backend_type ∉ [:CPU, :GPU]
        error("backend_type must be either :CPU or :GPU, got: $backend_type")
    end
    
    # Load spatial data (30m resolution) using the new loader for precompilation compatibility
    normalized_landuse, landuse_mapping, normalized_soil, soiltype_mapping, elevation, slope = load_datasets()
    # Extract model cells (CPU arrays for now)
    model_landuse_cpu = normalized_landuse[normalized_landuse .> 1]
    model_soil_cpu = normalized_soil[normalized_landuse .> 1]
    
    # Lookup tables based on land use codes
    threshold_precipitation_lookup = Dict(
        1 => 12.0,
        21 => 15.0,
        31 => 17.5,
        32 => 16.0,
        33 => 18.5,
        36 => 17.5,
        307 => 17.5,
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
    
    # Process timestamps to create year-month periods for multiyear analysis
    years = year.(timestamp)
    months = month.(timestamp)
    # Create unique period identifiers as tuples of (year, month)
    year_month_pairs = collect(zip(years, months))
    periods = sort(unique(year_month_pairs))
    
    # Initialize results DataFrame with Year and Month columns
    ResultDf = DataFrame(
        Year = Int[],
        Month = Int[], 
        ActET = Float32[],
        Recharge = Float32[],
        Runoff = Float32[],
        Prec = Float32[],
        ChangeinStorage = Float32[]
    )
    
    # Initialize soil storage as half of the soil capacity
    n_cells = length(model_landuse_cpu)
    
    # Compute initial storage on CPU using CPU arrays
    soil_storage = Float32[soil_cap_array[model_soil_cpu[i]] * 
                           soil_ext_depth_array[model_landuse_cpu[i]] / 2.0f0 
                           for i in 1:n_cells]
    
    # Convert to appropriate backend
    if backend_type == :GPU
        model_landuse = MtlArray(Int32.(model_landuse_cpu))
        model_soil = MtlArray(Int32.(model_soil_cpu))
        thresh_prec_array = MtlArray(Float32.(thresh_prec_array))
        crop_coeff_array = MtlArray(Float32.(crop_coeff_array))
        soil_ext_depth_array = MtlArray(Float32.(soil_ext_depth_array))
        soil_cap_array = MtlArray(Float32.(soil_cap_array))
        soil_storage = MtlArray(Float32.(soil_storage))
        prec_array = MtlArray(Float32.(prec))
        pet_array = MtlArray(Float32.(pet))
        backend = Metal.MetalBackend()
    else  # CPU
        model_landuse = Int32.(model_landuse_cpu)
        model_soil = Int32.(model_soil_cpu)
        thresh_prec_array = Float32.(thresh_prec_array)
        crop_coeff_array = Float32.(crop_coeff_array)
        soil_ext_depth_array = Float32.(soil_ext_depth_array)
        soil_cap_array = Float32.(soil_cap_array)
        soil_storage = Float32.(soil_storage)
        prec_array = Float32.(prec)
        pet_array = Float32.(pet)
        backend = CPU()
    end
    
    initial_soil_storage = copy(soil_storage)
    
    # Prepare arrays to hold cumulative results
    if backend_type == :GPU
        total_actet = MtlArray(zeros(Float32, n_cells))
        total_recharge = MtlArray(zeros(Float32, n_cells))
        total_runoff = MtlArray(zeros(Float32, n_cells))
        total_prec = MtlArray(zeros(Float32, n_cells))
    else
        total_actet = zeros(Float32, n_cells)
        total_recharge = zeros(Float32, n_cells)
        total_runoff = zeros(Float32, n_cells)
        total_prec = zeros(Float32, n_cells)
    end
    
    # Loop over each year-month period
    for period in periods
        year_val, month_val = period
        initial_month_soil_storage = copy(soil_storage)
        # Find indices matching both year and month
        period_indices = findall((years .== year_val) .& (months .== month_val))
        n_timesteps = length(period_indices)
        
        kernel = water_balance_timeseries!(backend, 64)
        ev = kernel(
            total_actet, total_recharge, total_runoff, total_prec,
            soil_storage,
            prec_array[period_indices], pet_array[period_indices],
            model_landuse, model_soil,
            thresh_prec_array, crop_coeff_array,
            soil_cap_array, soil_ext_depth_array,
            n_timesteps;
            ndrange = n_cells
        )
        KernelAbstractions.synchronize(backend)
        
        # Calculate monthly totals
        monthly_actet = sum(total_actet) / n_cells
        monthly_recharge = sum(total_recharge) / n_cells
        monthly_runoff = sum(total_runoff) / n_cells
        monthly_prec = sum(total_prec) / n_cells
        change_in_storage_month = sum(soil_storage .- initial_month_soil_storage) / n_cells
        
        # Append monthly results to DataFrame
        push!(ResultDf, (year_val, month_val, monthly_actet, monthly_recharge,
            monthly_runoff, monthly_prec, change_in_storage_month))
    end
    
    final_soil_storage = copy(soil_storage)
    
    # Calculate the model error in the water balance
    change_in_storage = sum(final_soil_storage .- initial_soil_storage) / n_cells
    total_input = sum(ResultDf.Prec)
    total_output = sum(ResultDf.ActET .+ ResultDf.Recharge .+ ResultDf.Runoff)
    balance_error = total_input - total_output - change_in_storage
    
    return ResultDf, balance_error
end
