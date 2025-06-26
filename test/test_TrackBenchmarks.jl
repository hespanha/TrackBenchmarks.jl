"""
Unit tests for TrackBenchmarks.jl

2024 (C) Joao Hespanha
"""

using Dates
using TimerOutputs
using Glob
using Test

using PersistentCache
using TrackBenchmarks

@testset "TrackBenchmarks: Description" begin
    d = Description()
    @test isempty(d) == true
    display(d)

    d = Description("Qminmax.jl", linearSolver=:LDL, equalityTolerance=1e-8, muFactorAggressive=0.9)
    display(d)
    @test isempty(d) == false
    @test length(d) == 4
    @test haskey(d, :linearSolver)
    @test haskey(d, :name)
    @test haskey(d, :equalityTolerance)
    @test !haskey(d, :xxx)
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
end;

@testset "TrackBenchamrks: TimerOutput => description" begin
    t0 = time()
    timerOutput = TimerOutput()

    @timeit timerOutput "" sleep(0.2)
    @timeit timerOutput "start" x = 0
    @timeit timerOutput "loop" for i in 1:100
        @timeit timerOutput "sleep" sleep(0.01)
        @timeit timerOutput "assign" y = 0
    end
    for i in 1:100
        @timeit timerOutput "sleep" sleep(0.01)
    end
    @show dt = time() - t0
    display(timerOutput)
    dto = convert(Dict, timerOutput)
    display(dto)
    @test sort(collect(keys(dto))) == [
        "/"
        "/loop"
        "/loop/assign"
        "/loop/sleep"
        "/sleep"
        "/start"
        "total time"]
    @test abs(dto["total time"] - 2.5) < 0.2
    @test abs(dto["/"] - 0.2) < 0.1
    @test abs(dto["/loop"] - 100 * 0.01) < 0.2
    @test abs(dto["/loop/sleep"] - 100 * 0.01) < 0.2
    @test abs(dto["/loop/assign"]) < 0.1
    @test abs(dto["/start"]) < 0.1
    @test abs(dto["/sleep"] - 100 * 0.01) < 0.2

    tto = convert(NamedTuple, timerOutput)
    display(tto)

    @test keys(tto) == (
        :/,
        Symbol("/loop"),
        Symbol("/loop/assign"),
        Symbol("/loop/sleep"),
        Symbol("/sleep"),
        Symbol("/start"),
        Symbol("total time"))
    @test sort(collect(values(dto))) == sort(collect(values(tto)))
end;

@testset "TrackBenchmarks: saveBenchmark" begin
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
        "(10.5,)",
        "()",
        "(50,)",
        "(10.5, 51.0)"
    ]
end;

@testset "TrackBenchmarks: readParameters" begin

    prefix = joinpath("test", "tmp_")
    M = @pcacheref prefix rand(10, 10)
    mn = @pcacheref prefix minimum(M; dims=1)
    mx1 = @pcacheref prefix maximum(M; dims=1)
    sm = @pcacheref prefix sum(M; dims=1)

    df = readParameterss(pattern="tmp_*.jld2", directory="test")
    @test size(df) == (4, 5) # 4 functions

    (dfu, dfnu) = TrackBenchmarks.uniqueCols(df)
    display(dfu)
    display(dfnu)
    @test size(dfu) == (4, 2)  # only one function has 2 arguments (so unique) and dims
    @test size(dfnu) == (4, 3) # remaining parameters

    # remove files created for test
    files2remove = glob(joinpath("test", "tmp_*.jld2"))
    for file in files2remove
        rm(file)
    end
end
