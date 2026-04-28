using Pkg; Pkg.activate(".")
using Revise
using HealthQuery

backend = build_schema_index(verbose=false)

conn = connect_database("test/data/omop_test.sqlite")

question = "How many patients are in the database?"

ctx      = retrieve_context(backend, question; verbose=false)
raw      = generate_funsql(question, ctx; verbose=true)

println("\n=== Raw LLM output ===")
println(raw)

code, valid, msg = parse_funsql_code(raw)
println("\n=== PostProcessing ===")
println("Valid: $valid")
println("Message: $msg")
println("Extracted code:\n$code")

if valid
    println("\n=== Executing query ===")
    df = execute_funsql(code, conn)
    println("\n=== Result ===")
    println(df)
end