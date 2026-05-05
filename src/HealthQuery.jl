module HealthQuery

using Logging
using RAGTools
using PromptingTools
using Statistics
using GoogleGenAI

include("Types.jl")
include("Retrieval.jl")   
include("Generation.jl")
include("PostProcessing.jl")
include("Database.jl")
include("Evaluation.jl")

export query_health_data
export build_schema_index
export retrieve_context
export generate_funsql
export generate_funsql_gemini
export execute_funsql
export run_evaluation
export connect_database
export parse_funsql_code
export get_rendered_sql
export run_evaluation
export summarize_evaluation
export GOLDEN_DATASET

"""
    query_health_data(question, backend, conn; model, verbose) -> QueryResult

The main entry point for HealthQuery. Runs the full RAG pipeline:
  1. Retrieve relevant OMOP schema chunks
  2. Generate @funsql code via LLM
  3. Parse and validate the generated code
  4. Execute against the OMOP database
  5. Return a QueryResult with the DataFrame and metadata

# Example
```julia
backend = build_schema_index()
conn    = connect_database("test/data/omop_test.sqlite")
result  = query_health_data("How many female patients are there?", backend, conn)
println(result.dataframe)
println("SQL used: ", result.sql_string)
```
"""
function query_health_data(
    question :: String,
    backend  :: InMemoryBackend,
    conn;
    model    :: String = "qwen3.5:4b",
    verbose  :: Bool   = true
) :: QueryResult

    t_start = time()

    # Step 1: Retrieve
    ctx = retrieve_context(backend, question; verbose=false)

    # Step 2: Generate
    raw = if occursin("gemini", lowercase(model))
        generate_funsql_gemini(question, ctx; verbose=verbose)
    else
        generate_funsql(question, ctx; model=model, verbose=verbose)
    end

    # Step 3: Parse
    code, valid, parse_msg = parse_funsql_code(raw)

    if !valid
        return QueryResult(question, code, "", DataFrame(),
            (time() - t_start) * 1000, 0.0, false, parse_msg)
    end

    # Step 4: Execute
    df, sql_str = try
        sql = get_rendered_sql(code, conn)
        result = execute_funsql(code, conn; verbose=verbose)
        result, sql
    catch e
        return QueryResult(question, code, "", DataFrame(),
            (time() - t_start) * 1000, 0.0, false, sprint(showerror, e))
    end

    elapsed_ms = (time() - t_start) * 1000

    return QueryResult(question, code, sql_str, df, elapsed_ms, 0.0, true, nothing)
end

end