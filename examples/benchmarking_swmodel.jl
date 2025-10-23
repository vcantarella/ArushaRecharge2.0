"""
Benchmark script for water balance model performance testing.

This script benchmarks the CPU vs GPU performance of the water balance model
by replicating yearly data across multiple years (1-100 years) and measuring
execution time for both backends.
"""

using CSV, DataFrames, Dates
using BenchmarkTools
using Statistics
using Plots
using ArushaRecharge


println("=" ^ 70)
println("Water Balance Model Performance Benchmark")
println("=" ^ 70)

# Load base year data (2020)
println("\nLoading base year data...")
prec_df = CSV.read("arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
pet_df = CSV.read("arusha_recharge/Climate data/ET_2020.csv", DataFrame)
base_prec = prec_df[!, "Precipitation (mm/day)"]
base_pet = pet_df[!, "ET (mm/day)"]
base_timestamps = Date.(prec_df[!, "Date"], dateformat"dd/mm/yyyy")
base_year = year(base_timestamps[1])

println("Base year: $base_year")
println("Days in base year: $(length(base_prec))")

"""
    replicate_yearly_data(base_data, base_timestamps, n_years)

Replicate yearly data across multiple years by incrementing the year.
Handles leap year dates (Feb 29) by skipping them in non-leap years.

# Arguments
- `base_data`: Vector of daily values (precipitation or ET) for one year
- `base_timestamps`: Vector of Date objects for the base year
- `n_years`: Number of years to replicate (1-100)

# Returns
- Tuple of (replicated_data, replicated_timestamps)
"""
function replicate_yearly_data(base_data, base_timestamps, n_years)
    # Validate input
    if n_years < 1 || n_years > 200
        error("n_years must be between 1 and 200, got: $n_years")
    end
    
    # Get base year
    base_year = year(base_timestamps[1])
    
    # Use vectors that can grow dynamically to handle leap year issues
    replicated_data = Float64[]
    replicated_timestamps = Date[]
    
    # Replicate data for each year
    for year_offset in 0:(n_years - 1)
        new_year = base_year + year_offset
        
        # Process each day in the base year
        for (idx, d) in enumerate(base_timestamps)
            m, day_val = month(d), day(d)
            
            # Skip Feb 29 if the target year is not a leap year
            if m == 2 && day_val == 29 && !isleapyear(new_year)
                continue
            end
            
            # Create new date and append data
            try
                new_date = Date(new_year, m, day_val)
                push!(replicated_timestamps, new_date)
                push!(replicated_data, base_data[idx])
            catch e
                # Skip any problematic dates
                @warn "Skipping date: Year $new_year, Month $m, Day $day_val" exception=e
                continue
            end
        end
    end
    
    return replicated_data, replicated_timestamps
end

"""
    benchmark_model(n_years::Int)

Run benchmark for a given number of years on both CPU and GPU.

# Arguments
- `n_years`: Number of years to simulate (1-100)

# Returns
- Tuple of (cpu_time_seconds, gpu_time_seconds)
"""
function benchmark_model(n_years::Int, base_prec, base_pet, base_timestamps)
    println("\n" * "-" ^ 70)
    println("Benchmarking with $n_years year$(n_years > 1 ? "s" : "")...")
    
    # Replicate data
    prec_multi, timestamps_multi = replicate_yearly_data(base_prec, base_timestamps, n_years)
    pet_multi, _ = replicate_yearly_data(base_pet, base_timestamps, n_years)
    
    println("Total timesteps: $(length(prec_multi))")
    println("Period: $(year(timestamps_multi[1])) - $(year(timestamps_multi[end]))")
    
    # Benchmark CPU
    println("\nBenchmarking CPU...")
    cpu_time = @elapsed begin
        result_cpu = ArushaRecharge.run_water_balance(prec_multi, pet_multi, timestamps_multi, :CPU)
    end
    println("CPU time: $(round(cpu_time, digits=3)) seconds")
    
    # Benchmark GPU
    println("\nBenchmarking GPU...")
    gpu_time = @elapsed begin
        result_gpu = ArushaRecharge.run_water_balance(prec_multi, pet_multi, timestamps_multi, :GPU)
    end
    println("GPU time: $(round(gpu_time, digits=3)) seconds")
    
    # Calculate speedup
    speedup = cpu_time / gpu_time
    println("\nSpeedup (CPU/GPU): $(round(speedup, digits=2))x")
    
    return cpu_time, gpu_time
end

# Run benchmarks for different numbers of years
println("\n" * "=" ^ 70)
println("Starting benchmark suite...")
println("=" ^ 70)

# Test different year counts
year_counts = [1, 2, 5, 10, 20, 50, 100, 200]

# Initialize results DataFrame
benchmark_results = DataFrame(
    model_years = Int[],
    CPU = Float64[],
    GPU = Float64[]
)

# Run benchmarks
for n_years in year_counts
    cpu_time, gpu_time = benchmark_model(n_years, base_prec, base_pet, base_timestamps)
    push!(benchmark_results, (n_years, cpu_time, gpu_time))
end

# Display results
println("\n" * "=" ^ 70)
println("Benchmark Results Summary")
println("=" ^ 70)
display(benchmark_results)

# Calculate and display speedups
benchmark_results.Speedup = benchmark_results.CPU ./ benchmark_results.GPU
println("\n" * "=" ^ 70)
println("Speedup Analysis")
println("=" ^ 70)
display(select(benchmark_results, :model_years, :Speedup))

# Save results to CSV
output_file = "benchmark_results.csv"
CSV.write(output_file, benchmark_results)
println("\n" * "=" ^ 70)
println("Results saved to: $output_file")
println("=" ^ 70)

println("\nCreating benchmark plots...")

# Ensure timestamp is defined before use
timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")

# Plot 1: Execution time comparison
p1 = plot(
    benchmark_results.model_years, 
    [benchmark_results.CPU benchmark_results.GPU],
    label=["CPU" "GPU"],
    xlabel="Model Years",
    ylabel="Execution Time (seconds)",
    title="CPU vs GPU Performance",
    marker=:circle,
    linewidth=2,
    legend=:topleft,
    grid=true,
    size=(800, 500),
    dpi=300
)

# Plot 2: Speedup factor
p2 = plot(
    benchmark_results.model_years,
    benchmark_results.Speedup,
    label="GPU Speedup",
    xlabel="Model Years",
    ylabel="Speedup Factor (CPU/GPU)",
    title="GPU Speedup Over CPU",
    marker=:circle,
    linewidth=2,
    color=:green,
    legend=:bottomright,
    grid=true,
    size=(800, 500),
    dpi=300
)
hline!([1.0], label="Baseline (CPU)", linestyle=:dash, color=:red)

# Combine plots
p_combined = plot(p1, p2, layout=(1, 2), size=(1600, 500), dpi=300)

# Save plots
plot_file = "benchmark_comparison.png"
savefig(p_combined, plot_file)
println("\nPlot saved to: $plot_file")

# Also save individual plots for README
savefig(p1, "benchmark_time.png")
savefig(p2, "benchmark_speedup.png")
println("Individual plots saved:")
println("  - benchmark_time.png")
println("  - benchmark_speedup.png")

println("\n" * "=" ^ 70)
println("Benchmarking Complete!")
println("=" ^ 70)
