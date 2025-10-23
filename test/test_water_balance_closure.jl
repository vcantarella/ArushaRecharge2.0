using Test
using ArushaRecharge
using CSV, DataFrames, Dates

@testset "Water balance closure for 1 year (CPU)" begin
    # Load base year data (2020)
    prec_df = CSV.read("../arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
    pet_df = CSV.read("../arusha_recharge/Climate data/ET_2020.csv", DataFrame)
    base_prec = prec_df[!, "Precipitation (mm/day)"]
    base_pet = pet_df[!, "ET (mm/day)"]
    base_timestamps = Date.(prec_df[!, "Date"], dateformat"dd/mm/yyyy")

    # Run model on CPU
    result, balance_error = ArushaRecharge.run_water_balance(base_prec, base_pet, base_timestamps, :CPU)

    # The error should be very small (numerical tolerance)
    @test isapprox(balance_error, 0.0; atol=1e-2, rtol=1e-2)
end
