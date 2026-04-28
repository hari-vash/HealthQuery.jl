using DataFrames

const GOLDEN_DATASET = [
    (
        question    = "How many patients are in the database?",
        golden_code = """@funsql begin
            from(person)
            group()
            select(count())
        end""",
        description = "Simple aggregate count — tests group() requirement"
    ),
    (
        question    = "Find all female patients and their birth year",
        golden_code = """@funsql begin
            from(person)
            filter(gender_concept_id == 8532)
            select(person_id, year_of_birth)
        end""",
        description = "Filter on coded column — tests concept_id knowledge"
    ),
    (
        question    = "Which distinct states do patients live in?",
        golden_code = """@funsql begin
            from(person)
            join(loc => from(location), on = location_id == loc.location_id)
            select(state => loc.state)
            group(state)
            select(state)
        end""",
        description = "Join + project + group for distinct values"
    ),
    (
        question    = "How many distinct patients appear in the condition_occurrence table?",
        golden_code = """@funsql begin
            from(condition_occurrence)
            group(person_id)
            select(count())
        end""",
        description = "Count distinct patients via group(person_id)"
    ),
    (
        question    = "What is the earliest and latest visit date in the database?",
        golden_code = """@funsql begin
            from(visit_occurrence)
            group()
            select(min(visit_start_date), max(visit_start_date))
        end""",
        description = "Multi-aggregate with min/max — tests aggregate variety"
    ),
    (
        question    = "List all patients born after 1950, showing their person_id and birth year",
        golden_code = """@funsql begin
            from(person)
            filter(year_of_birth > 1950)
            select(person_id, year_of_birth)
        end""",
        description = "Numeric comparison filter — tests inequality operators"
    ),
    (
        question    = "For each patient, how many drug exposures do they have?",
        golden_code = """@funsql begin
            from(drug_exposure)
            group(person_id)
            select(person_id, count())
        end""",
        description = "Group-by with key in select — tests per-group results"
    ),
    (
        question    = "List the distinct person_ids of patients who have at least one measurement",
        golden_code = """@funsql begin
            from(measurement)
            group(person_id)
            select(person_id)
        end""",
        description = "Distinct patients via group(person_id) — true deduplication test"
    ),
]

"""
    dataframes_equal(df1::DataFrame, df2::DataFrame) -> Bool

Compares two DataFrames for semantic equality:
  - Same column names (order-insensitive)
  - Same rows (order-insensitive, sorted before comparison)

Order-insensitivity is critical: two valid SQL queries can return rows in
different orders. We sort both DataFrames before comparing so that
`[("IL"), ("NY")]` == `[("NY"), ("IL")]`.
"""
function dataframes_equal(df1::DataFrame, df2::DataFrame) :: Bool
    
    ncol(df1) != ncol(df2) && return false

    nrow(df1) != nrow(df2) && return false

    sort(names(df1)) != sort(names(df2)) && return false

    try
        cols = sort(names(df1))
        s1 = sort(string.(eachrow(df1[:, cols])))
        s2 = sort(string.(eachrow(df2[:, cols])))
        return s1 == s2
    catch
        return false
    end
end


struct EvalResult
    question         :: String
    description      :: String
    model            :: String
    generated_code   :: String
    golden_code      :: String
    parse_valid      :: Bool
    execution_ok     :: Bool
    execution_accurate :: Bool
    latency_ms       :: Float64
    token_count      :: Int
    error_message    :: String
end


"""
    run_evaluation(backend, conn; models, verbose) -> DataFrame

Runs the full golden dataset through one or more LLMs and returns a
summary DataFrame with per-question metrics.

# Arguments
- `backend` : InMemoryBackend from `build_schema_index()`
- `conn`    : FunSQL database connection from `connect_database()`
- `models`  : Vector of model name strings to evaluate. Each model is
              run against every question in the golden dataset.
- `verbose` : Print progress as evaluation runs

# Returns
A DataFrame with columns:
  model | question | description | parse_valid | execution_ok |
  execution_accurate | latency_ms | token_count | error

# Example
```julia
results = run_evaluation(backend, conn; models=["qwen3.5:4b"])
println(summarize_evaluation(results))
```
"""
function run_evaluation(
    backend :: InMemoryBackend,
    conn;
    models  :: Vector{String} = ["qwen3.5:4b"],
    verbose :: Bool = true
) :: DataFrame

    all_results = EvalResult[]

    for model in models
        verbose && println("\n" * "="^60)
        verbose && println("Evaluating model: $model")
        verbose && println("="^60)

        for (i, entry) in enumerate(GOLDEN_DATASET)
            verbose && print("  [$i/$(length(GOLDEN_DATASET))] $(entry.description)... ")

            t_start = time()
            generated_code = ""
            parse_valid    = false
            execution_ok   = false
            accurate       = false
            token_count    = 0
            err_msg        = ""

            try
                ctx = retrieve_context(backend, entry.question; verbose=false)

                raw = if occursin("gemini", lowercase(model))
                    generate_funsql_gemini(entry.question, ctx; verbose=false)
                else
                    generate_funsql(entry.question, ctx; model=model, verbose=false)
                end

                latency_ms = (time() - t_start) * 1000

                code, valid, parse_msg = parse_funsql_code(raw)
                generated_code = code
                parse_valid    = valid

                if !valid
                    err_msg = parse_msg
                    verbose && println("PARSE FAIL")
                    push!(all_results, EvalResult(
                        entry.question, entry.description, model,
                        generated_code, entry.golden_code,
                        false, false, false,
                        latency_ms, 0, err_msg))
                    continue
                end

                generated_df = try
                    execute_funsql(code, conn; verbose=false)
                catch e
                    err_msg = sprint(showerror, e)
                    verbose && println("EXEC FAIL")
                    push!(all_results, EvalResult(
                        entry.question, entry.description, model,
                        generated_code, entry.golden_code,
                        true, false, false,
                        latency_ms, 0, err_msg))
                    continue
                end
                execution_ok = true

                golden_df = execute_funsql(entry.golden_code, conn; verbose=false)

                accurate = dataframes_equal(generated_df, golden_df)

                verbose && println(accurate ? "✓ PASS" : "✗ WRONG RESULT")

                push!(all_results, EvalResult(
                    entry.question, entry.description, model,
                    generated_code, entry.golden_code,
                    true, true, accurate,
                    latency_ms, 0, ""))

            catch e
                latency_ms = (time() - t_start) * 1000
                err_msg = sprint(showerror, e)
                verbose && println("ERROR: $err_msg")
                push!(all_results, EvalResult(
                    entry.question, entry.description, model,
                    generated_code, entry.golden_code,
                    false, false, false,
                    latency_ms, 0, err_msg))
            end
        end
    end

    return DataFrame(
        model               = [r.model               for r in all_results],
        description         = [r.description         for r in all_results],
        parse_valid         = [r.parse_valid         for r in all_results],
        execution_ok        = [r.execution_ok        for r in all_results],
        execution_accurate  = [r.execution_accurate  for r in all_results],
        latency_ms          = [r.latency_ms          for r in all_results],
        error               = [r.error_message       for r in all_results],
        generated_code      = [r.generated_code      for r in all_results],
    )
end

"""
    summarize_evaluation(results::DataFrame) -> String

Prints a clean summary table of evaluation results grouped by model.
"""
function summarize_evaluation(results::DataFrame) :: String
    io = IOBuffer()

    for model in unique(results.model)
        df = filter(r -> r.model == model, results)
        n  = nrow(df)

        parse_rate = round(100 * sum(df.parse_valid)        / n; digits=1)
        exec_rate  = round(100 * sum(df.execution_ok)       / n; digits=1)
        ea         = round(100 * sum(df.execution_accurate) / n; digits=1)
        avg_ms     = round(mean(df.latency_ms);               digits=0)

        println(io, "\n Model: $model")
        println(io, "  Questions evaluated : $n")
        println(io, "  Parse success rate  : $parse_rate%")
        println(io, "  Execution success   : $exec_rate%")
        println(io, "  Execution Accuracy  : $ea%  ← primary metric")
        println(io, "  Avg latency         : $(avg_ms) ms")
        println(io, "\n  Per-question breakdown:")
        for row in eachrow(df)
            status = row.execution_accurate ? "✓" :
                     row.execution_ok       ? "~" :
                     row.parse_valid        ? "!" : "✗"
            println(io, "    $status $(row.description)")
        end
    end

    return String(take!(io))
end