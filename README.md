# TrackBenchmarks

This package facilitates keeping track of the results obtained by executing one (or several)
functions, for multiple values of input parameters:

+ Creates a `Description` NamedTuple that can be used to store 
    1. parameters about a problem to be solved
    2. parameters passed to a function that "solves" the problem (simulations/data
       analysis/learning/etc.)
    3. results produced by the function
    4. timing information about function compute times

+ Provides a function `saveBenchmark` function to save `Description` NamedTuples with
    1. parameters about a problem to be solved
    2. parameters passed to a function that "solves" the problem (simulations/data
       analysis/learning/etc.)
    3. results produced by the function
    4. timing information about function compute times
    5. git-commit information for the function's project

  The same "benchmarks" file can be used to solve the result of many runs of the same function or
  different functions that save the same (or similar) problems

+ Provides a function `readParameters` to read `Description` NamedTuples or outputs from
  `PersistentCache` and summarize them into a `DataFrame` 

## Todo 

1) May be possible to build upon and reuse some fo the functionalities of
   [DrWatson](https://github.com/JuliaDynamics/DrWatson.jl) 