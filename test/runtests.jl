using DotEnv
DotEnv.load!()

using Revise, Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using HealthQuery, Statistics, CSV, DataFrames

@assert haskey(ENV, "GOOGLE_API_KEY") "GOOGLE_API_KEY missing from .env"

backend = build_schema_index(verbose=false)
conn    = connect_database("test/data/omop_test.sqlite")

results = run_evaluation(backend, conn;
    models  = ["qwen3.5:4b", "gemini"],
    verbose = true
)

println(summarize_evaluation(results))
CSV.write("test/eval_results_combined.csv", results)