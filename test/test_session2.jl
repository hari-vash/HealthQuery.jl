questions = [
    "How many patients are in the database?",
    "Find all female patients and their birth year",
    "Which states do patients live in?",
]

for q in questions
    local ctx, raw, code, valid, msg, df
    println("\n" * "="^50)
    println("QUESTION: $q")
    ctx  = retrieve_context(backend, q; verbose=false)
    raw  = generate_funsql(q, ctx; verbose=false)
    code, valid, msg = parse_funsql_code(raw)
    if valid
        df = execute_funsql(code, conn; verbose=false)
        println("Generated:\n$code")
        println("Result: $(nrow(df)) rows × $(ncol(df)) cols")
        println(df)
    else
        println("INVALID: $msg")
        println("Raw output: $raw")
    end
end