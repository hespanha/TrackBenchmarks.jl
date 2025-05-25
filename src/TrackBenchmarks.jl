module TrackBenchmarks

export Description, saveBenchmark

using Printf
#using Formatting

using CSV
using DataFrames
using Git
using Dates
using TimeZones

# TODO remove from IPsparse

"""
Structure used to store the description of a problem, solver, etc.

# Example
   d=Description("quadratic minmax";linearSolver=:LDL,equalityTolerance=1e-8,muFactorAggressive=.9)
   d=Description(solveTime=.1,solveTimeWithoutPrint=.05)
"""
struct Description
    name::String
    parNames::Vector{String}
    parValues
    function Description(name::String; varargs...)
        parNames = [string(key) for (key, value) in varargs]
        parValues = [value for (key, value) in varargs]
        if isempty(parNames)
            parNames = String[]
            parValues = Any[]
        end
        return new(name, parNames, parValues)
    end
    function Description(; varargs...)
        return Description(""; varargs...)
    end
end
@inline Base.isempty(d::Description) = isempty(d.name) && isempty(d.parNames)
function Base.show(io::IO, d::Description)
    if ~isempty(d)
        if ~isempty(d.name)
            @printf(io, "%s:", d.name)
        else
            @printf(io, "Description:")
        end
        for i in 1:length(d.parNames)
            str = string(d.parValues[i])
            if length(str) > 80
                str = str[1:35] * " … " * str[end-35:end]
            end
            @printf(io, "\n   %-25s: %s", d.parNames[i], str)
        end
    end
    return nothing
end
Base.convert(::Type{Dict}, d::Description) =
    Dict(Symbol(d.parNames[i]) => d.parValues[i] for i in eachindex(d.parNames, d.parValues))
Base.convert(::Type{NamedTuple}, d::Description) =
    NamedTuple(Symbol(d.parNames[i]) => d.parValues[i] for i in eachindex(d.parNames, d.parValues))

"""Get parameters in Description using `.parName`"""
@inline function Base.getproperty(d::Description, sym::Symbol)
    if sym == :name || sym == :parNames || sym == :parValues
        return getfield(d, sym)
    end
    parNames = getfield(d, :parNames)
    k = findfirst(parNames .== string(sym))
    if isnothing(k)
        return getfield(d, sym)
    else
        parValues = getfield(d, :parValues)
        return parValues[k]
    end
end
@inline Base.getproperty(d::Description, sym::String) = getproperty(d, Symbol(sym))
"""Check if Description has a given parameter"""
@inline Base.haskey(d::Description, sym::String) = (sym == "name" || sym in d.parNames)
@inline Base.haskey(d::Description, sym::Symbol) = haskey(d, String(sym))
@inline Base.keys(d::Description) = vcat("name", d.parNames)

# TODO: pruning not implemented
"""
# Example
   saveBenchmark(
    "IPbenchmarks.csv";
    solver=Description("quadratic minmax",linearSolver=:LDL,equalityTolerance=1e-8,muFactorAggressive=.9),
    problem=Description("Rock paper Scissors",nU=10,nEqU=1),
    time=Description(solveTime=.1,solveTimeWithoutPrint=.05),
    pruneBy=Hour(1))
"""
function saveBenchmark(
    filename::String;
    solver::Description,
    problem::Description,
    result::Description=Description(),
    time::Description,
    benchmarkTime::ZonedDateTime=now(localzone()),
    pruneBy::Period=Hour(0))

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
    df1 = DataFrame(
        benchmarkTime=[benchmarkTime],                  # 1
        solverName=String[solver.name],                 # 2
        problemName=[problem.name],                     # 3
        problemValues=[string(problem.parValues)],      # 4
        resultValues=[string(result.parValues)],        # 5
        timeValues=[time.parValues],                    # 6
        resultParameters=[string(result.parNames)],     # 7
        timesNames=[string(time.parNames)],             # 8
        solverValues=[string(solver.parValues)],        # 9
        problemParameters=[string(problem.parNames)],   #10
        solverParameters=[string(solver.parNames)],     #11
        gitCommitHash=[gitCommitHash],                  #12
        gitCommitTime=[gitCommitTime],)                 #13
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


end