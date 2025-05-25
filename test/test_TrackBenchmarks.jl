"""
Unit tests for TrackBenchmarks.jl

2024 (C) Joao Hespanha
"""

using Dates
using Test

using TrackBenchmarks

@testset "saveBenchmark" begin
    d = Description()
    @test isempty(d) == true
    display(d)

    d = Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9)
    display(d)
    @test isempty(d) == false
    @test length(d.parNames) == 3
    @test length(d.parValues) == 3
    @test haskey(d, :linearSolver)
    @test haskey(d, "name")
    @test haskey(d, "equalityTolerance")
    @test !haskey(d, "xxx")
    @test d.linearSolver == :LDL
    @test d.equalityTolerance == 1e-8

    d = Description(solveTime=0.1, solveTimeWithoutPrint=0.05, nIter=4)
    display(d)
    @test isempty(d) == false

    di = convert(Dict, d)
    display(di)
    @test di == Dict(:solveTime => 0.1, :solveTimeWithoutPrint => 0.05, :nIter => 4)

    dn = convert(NamedTuple, d)
    display(dn)
    @test dn == (solveTime=0.1, solveTimeWithoutPrint=0.05, nIter=4)

    filename = "test/testTrackBenchmarks.csv"
    try
        run(`rm $filename`)
    catch err
        display(err)
    end

    @time df = saveBenchmark(
        filename,
        solver=Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9),
        problem=Description("Rock paper Scissors", nU=10, nEqU=1),
        time=Description(solveTime=0.1, solveTimeWithoutPrint=0.05, nIter=5),
        result=Description(minimum=10.5),
        pruneBy=Minute(100))

    # not better and equal
    @time df = saveBenchmark(
        filename,
        solver=Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9),
        problem=Description("Rock paper Scissors", nU=10, nEqU=1),
        time=Description(solveTime=0.1, solveTimeWithoutPrint=0.05, nIter=5),
        result=Description(minimum=10.5),
        pruneBy=Minute(100))

    # better
    @time df = saveBenchmark(
        filename,
        solver=Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9),
        problem=Description("Rock paper Scissors", nU=10, nEqU=1),
        time=Description(solveTime=0.1, solveTimeWithoutPrint=0.05, nIter=4),
        pruneBy=Minute(100))

    # worse but different
    @time df = saveBenchmark(
        filename,
        solver=Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9),
        problem=Description("Rock paper Scissors", nU=10, nEqU=1),
        time=Description(solveTime=0.1, nIter=6.0),
        result=Description(maximum=50),
        pruneBy=Minute(100))

    # better but different
    @time df = saveBenchmark(
        filename,
        solver=Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9),
        problem=Description("Rock paper Scissors", nU=10, nEqU=1),
        time=Description(solveTime=0.1, nIter=5.0),
        result=Description(minimum=10.5, maximum=51.0),
        pruneBy=Minute(100))

    @test size(df, 1) == 4

    @test df.timeValues == [
        [0.1, 0.05, 5.0],
        [0.1, 0.05, 4.0],
        [0.1, 6.0],
        [0.1, 5.0]]

    @test df.resultValues == [
        "[10.5]",
        "Any[]",
        "[50]",
        "[10.5, 51.0]"
    ]
end