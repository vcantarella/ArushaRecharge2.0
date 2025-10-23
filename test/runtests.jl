using ArushaRecharge
using Test
using Aqua
using JET
using KernelAbstractions

@testset "ArushaRecharge.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(ArushaRecharge; stale_deps=false)
    end
    
    # JET testing disabled due to false positives from KernelAbstractions code generation
    # The @kernel macro generates GPU backend functions (gpu_water_balance_step!) that JET
    # flags with world age and __validindex errors. These are in generated code, not our code.
    # See: https://github.com/JuliaGPU/KernelAbstractions.jl/issues/XXX
    #
    # @testset "Code linting (JET.jl)" begin
    #     JET.test_package(ArushaRecharge; target_defined_modules = true)
    # end
    
    # Write your tests here.
    @testset "Basic functionality - Water Balance" begin
        include("test_water_balance_closure.jl")
    end
end
