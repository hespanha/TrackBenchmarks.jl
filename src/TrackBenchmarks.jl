module TrackBenchmarks

export Description
export saveBenchmark
export readParameterss, uniqueCols

using Printf

using Glob
using JLD2
using CSV
using DataFrames

using ConvergenceLoggers    # FIXME: only needed to load data

using Git
using Dates
using TimeZones
using TimerOutputs



# TODO remove from IPspars

#########################
## Backward compatibility
#########################

"""
Converter to enable loading with JLD2 the deprecated structures
`EstimationTools.TrackBenchmarks.Description`, which has since been replaced by `NamedTuple`

To use, include the following typemap when reading the JLD2 file:

typemap=Dict("EstimationTools.TrackBenchmarks.Description" 
             => JLD2.Upgrade(TrackBenchmarks.DescriptionContainer),
"""
struct DescriptionContainer
    value::NamedTuple
end
Base.convert(::Type{NamedTuple}, dc::DescriptionContainer) = dc.value
function JLD2.rconvert(::Type{DescriptionContainer}, nt::NamedTuple)
    if haskey(nt, :parNames)
        out::Dict{Symbol,Any} = Dict(
            Symbol(nt.parNames[i]) => nt.parValues[i]
            for i in eachindex(nt.parNames, nt.parValues))
        out[:name] = nt.name
        #@show NamedTuple((k, v) for (k, v) in out)
        return DescriptionContainer(NamedTuple((k, v) for (k, v) in out))
    end
    @show DescriptionContainer(nt)
    return DescriptionContainer(nt)
end

"""
Backwards compatible creation of a tuple of parameters/results.
"""
function Description(name::String; kwargs...)
    return (; name, kwargs...)
end
function Description(; kwargs...)
    return (; kwargs...)
end
Base.convert(::Type{Dict}, namedTuple::NamedTuple) = Dict(pairs(namedTuple))
function Base.convert(::Type{Dict}, timerOutput::TimerOutput)
    timers = TimerOutput[timerOutput]
    names = String["/"]
    out = Dict{String,Float64}("total time" => TimerOutputs.tottime(timerOutput) / 1e9) # convert to seconds
    #while true
    for _ in 1:10
        #@show names
        to = timers[end]
        name = to.name
        # add this timer
        out[joinpath(names)] = to.accumulated_data.time / 1e9 # convert to seconds
        children = to.inner_timers
        #@show keys(children)

        if isempty(children)
            # no children
            if isempty(timers)
                break
            end
            pop!(timers)
            pop!(names)
            # find next sibling
            siblings = timers[end].inner_timers
            foundMe = false
            #@show keys(siblings)
            for (k, v) in siblings
                if foundMe
                    push!(timers, v)
                    push!(names, v.name)
                    break
                end
                if k == name
                    foundMe = true
                end
            end
        else
            # go to 1st child
            (name, child) = first(to.inner_timers)
            push!(timers, child)
            push!(names, name)
        end
    end
    return out
end
function Base.convert(::Type{NamedTuple}, timerOutput::TimerOutput)
    dto = convert(Dict, timerOutput)
    NamedTuple((Symbol(k), dto[k]) for k in sort(collect(keys(dto))))
end

#######################################
## Saving of problem/solution summaries
#######################################

"""
# Example
   saveBenchmark("benchmarks.csv";
    solver=Description("quadratic minmax",linearSolver=:LDL,equalityTolerance=1e-8,muFactorAggressive=.9),
    problem=Description("Rock paper Scissors",nU=10,nEqU=1),
    time=Description(solveTime=.1,solveTimeWithoutPrint=.05),
    pruneBy=Hour(1))

> [!Tip] `problem`, `solver`, `result`, and `time` should only rely on basic types so that the JLDs
> files can be loaded without additional packges.
"""
function saveBenchmark(
    filename::String;
    func::String="",
    problem::NamedTuple,
    solver::NamedTuple,
    result::NamedTuple=(;),  # will be ignored
    loggers=(;),             # will be ignored
    time::NamedTuple,
    benchmarkTime::ZonedDateTime=now(localzone()),
    pruneBy::Period=Hour(0)
)

    if isempty(func)
        func=String[solver.name]
    end
    
    ## Read previous benchmark
    try
        df = DataFrame(CSV.File(filename))
    catch err
        display(err)
        @printf("saveBenchmark: could not read benchmark file \"%s\"\n", filename)
        df = []
    end

    if !isempty(df)
        # Convert Dates
        #display(df.benchmarkTime)
        #display(df.gitCommitTime)
        df.benchmarkTime = ZonedDateTime.(String.(df.benchmarkTime), "yyyy-mm-dd H:M:S.s z")
        df.gitCommitTime = df.gitCommitTime
        #df.gitCommitTime = ZonedDateTime.(String.(df.gitCommitTime), "yyyy-mm-dd H:M:S.s z")
        #display(df.benchmarkTime)
        #display(df.gitCommitTime)

        # Convert solve times
        #@show str1 = replace.(df.timeValues, r"[^[]*\[([^]]*)\]" => s"\1")
        #@show str2 = split.(str1, ",")
        #@show str3 = string.(str2)
        str2vector(str) = parse.(Float64, split(replace(str, r"[^[]*\[([^]]*)\]" => s"\1"), ","))
        df.timeValues = str2vector.(df.timeValues)
    end

    gitCommitHash = ""
    gitCommitTime = ""
    try
        dir = splitdir(Base.active_project())[1]
        arg1 = "--git-dir=$dir/.git"
        arg2 = "--work-tree=$dir"
        gitCommitHash = readchomp(`$(git()) $arg1 $arg2 log -1 --format='%H'`)
        gitCommitTimeS::String = readchomp(`$(git()) $arg1 $arg2 log -1 --format='%ai'`)
        gitCommitTimeDT =
            ZonedDateTime(gitCommitTimeS, "yyyy-mm-dd H:M:S z")
        gitCommitTime = Dates.format(gitCommitTimeDT, "yyyy-mm-dd H:M:S.s z")
    catch me
        display(me)
        @printf("saveBenchmark: could not get git commit from \"%s\"\n", dir)
        gitCommitTime = ""
    end
    ## Add current benchmark
    @show df1 = DataFrame(
        benchmarkTime=[benchmarkTime],                  # 1
        solverName=func,                                # 2
        problemName=[problem.name],                     # 3
        problemValues=[string(values(problem))],       # 4
        resultValues=[string(values(result))],         # 5
        timeValues=[collect(values(time))],             # 6
        resultParameters=[string(keys(result))],       # 7
        timesNames=[string(keys(time))],               # 8
        solverValues=[string(values(solver))],         # 9
        problemParameters=[string(keys(problem))],     #10
        solverParameters=[string(keys(solver))],       #11
        gitCommitHash=[gitCommitHash],                  #12
        gitCommitTime=[gitCommitTime],                  #13
    )
    #display(df)
    #display(df1)

    save = false

    ## prune
    if isempty(df)
        @printf("saveBenchmark: added to empty file\n")
        df = df1
        save = true
    elseif iszero(pruneBy)
        @printf("saveBenchmark: added (zero pruneBy)\n")
        df = vcat(df, df1)
    else
        ## compute rows that match solver+problem+result+prune time
        fields2match = [
            3, # problemName
            4, # problemValues
            10,# problemParameters
            8, # timesNames
            5, # resultValues
            7, # resultParameters
            2, # solverName
            9, # solverValues
            11,# solverParameters
        ]

        tMatch = (df[:, fields2match] .== df1[:, fields2match])
        kMatchProblem = vec(collect(all(Matrix(tMatch), dims=2))) # convert BitMatrix to Bool
        kMatchTime = (abs.(df.benchmarkTime - benchmarkTime) .< Dates.CompoundPeriod(pruneBy))
        kMatch = kMatchProblem .& kMatchTime

        if !any(kMatch)
            @printf("saveBenchmark: added (no match)\n")
            df = vcat(df, df1)
            save = true
        else
            dfMatch = copy(df[kMatch, :])
            ## find rows with all times better or equal to current times
            solveTimes2Matrix = hcat(dfMatch.timeValues...)'
            solveTimeAsVector = hcat(df1.timeValues[1]...)
            kBetterTime = all(solveTimes2Matrix .<= solveTimeAsVector, dims=2)
            if !any(kBetterTime)
                @printf("saveBenchmark: added (better times than matched)\n")
                df = vcat(df, df1)
                save = true
            else
                @printf("saveBenchmark: not added (not better times than matched)\n")
            end
        end
    end

    if save
        ## save updates file
        # making times more readable
        dfs = copy(df)
        dfs.benchmarkTime = Dates.format.(df.benchmarkTime, "yyyy-mm-dd H:M:S.s z")
        #dfs.gitCommitTime = Dates.format.(df.gitCommitTime, "yyyy-mm-dd H:M:S.s z")

        @printf("saveBenchmark: saving \"%s\"\n", filename)
        CSV.write(filename, dfs)
    end
    return df
end

############################################
## Explore parameters/results in saved files
############################################

"""
    dataRow(nt::NamedTuple, prefix)

Convert a NamedTuple to a single-row DataFrame

# Parameters
+ `nt::NamedTuple`
+ `prefix::String`

# Returns
+ df::DataFrame
"""
dataRow(
    nt::TrackBenchmarks.DescriptionContainer,
    prefix::String
) = dataRow(convert(NamedTuple, nt), prefix)
function dataRow(
    nt::NamedTuple,
    prefix::String
)
    # make v a list to avoid expansion of arrays over rows
    ntt = NamedTuple(
        (Symbol(prefix * string(k)), [v])
        for (k, v) in zip(keys(nt), nt))
    # convert to data frame
    return df = DataFrame(ntt)
end

"""
    df=readParameterss(files;typemap::Dict{String,Any})
    
Summarizes the parameters/results saved in a collection of files into a DataFrame, with one file per
row and the parameters as columns.

# Parameters

+ `files::Vector{String}`: vector of filenames to read

+ `typemap::Dict{String,Any}=Dict{String,Any}()`: typmap map used by JLD2 to convert types (see JLD2
  documentation)

"""
readParameterss(;
    pattern::String,
    directory::String,
    typemap::Dict{String,Any}=Dict{String,Any}()) = readParameterss(glob(pattern, directory); typemap)
function readParameterss(
    files::Vector{String};
    typemap::Dict{String,Any}=Dict{String,Any}()
)
    @printf("readParameters (%d files)\n", length(files))
    # backwards compatibility
    typemap["EstimationTools.TrackBenchmarks.Description"] =
        JLD2.Upgrade(TrackBenchmarks.DescriptionContainer)
    typemap["EstimationTools.ConvergenceLogging.TimeSeriesLogger"] =
        ConvergenceLoggers.TimeSeriesLogger
    #"ElasticArrays.ElasticArray" => JLD2.Upgrade(Nothing),
    #"ReinforcementLearningCore.Player" => JLD2.Upgrade(Nothing),
    df = DataFrame()
    for file in files
        jldopen(file, "r";
            typemap
        ) do content
            # file with "report"
            if haskey(content, "report")
                report = content["report"]
                dp = dataRow(report.problem, "problem.")
                ds = dataRow(report.solver, "solver.")
                dr = dataRow(report.result, "result.")
                dt = dataRow(report.time, "time.")
                row = hcat(DataFrame("filename" => file), dp, ds, dr, dt)
                if isempty(df)
                    df = row
                else
                    df = vcat(df, row, cols=:union)
                end
            elseif haskey(content, "pars")
                pars = content["pars"]
                for i in eachindex(pars.fun, pars.args, pars.kwargs)
                    fun = pars.fun[i]
                    args = pars.args[i]
                    ntArgs = NamedTuple(Symbol("arg_$j") => args[j] for j in eachindex(args))
                    kwargs = NamedTuple(pars.kwargs[i])
                    da = dataRow(ntArgs, "")
                    dk = dataRow(kwargs, "")
                    row = hcat(DataFrame("filename" => file, "fun" => fun), da, dk)
                    if isempty(df)
                        df = row
                    else
                        df = vcat(df, row, cols=:union)
                    end
                end
            else
                println("  unknown content for $file")
            end
        end
    end
    return df
end

function uniqueCols(df::DataFrame; nomissing=true)
    if nomissing
        ku = [length(unique(skipmissing(df[:, col]))) == 1 for col in axes(df, 2)]
    else
        ku = [length(unique(df[:, col])) == 1 for col in axes(df, 2)]
    end
    @printf("uniqueCols: %dx%s tables has %d constant columns and %d variable columns\n",
        size(df, 1), size(df, 2), sum(ku), sum(.!ku))
    return (df[:, ku], df[:, .!(ku)])
end

end
