using PromptingTools
const PT = PromptingTools

function _register_gemini_model!()
    if !haskey(PT.MODEL_REGISTRY, "gemini-2.5-flash-lite")
        PT.register_model!(;
            name        = "gemini-2.5-flash-lite",
            schema      = PT.GoogleSchema(),
            description = "Gemini 2.5 Flash Lite — free tier friendly, fast")
        @info "Registered gemini-2.5-flash-lite with GoogleSchema"
    end
end
_register_gemini_model!()


include(joinpath(@__DIR__, "..", "templates", "funsql_generation.jl"))

const OLLAMA = PT.OllamaSchema()

"""
    generate_funsql(question, context_chunks; model, verbose, temperature) -> String

Calls a local Ollama model to generate a @funsql query from a plain-English
question and retrieved OMOP schema chunks.
"""

function generate_funsql(
    question       :: String,
    context_chunks :: Vector{<:AbstractString};
    model          :: String  = "qwen3.5:4b",
    verbose        :: Bool    = true,
    temperature    :: Float64 = 0.1
) :: String

    schema_context = join(context_chunks, "\n---\n")

    full_prompt = """
    You are an expert clinical data engineer specializing in OMOP CDM and FunSQL.jl.
    Translate the health question into a valid @funsql begin...end block.
    Output ONLY the @funsql block. No explanation, no markdown, no raw SQL.

    ## CRITICAL FunSQL RULES — follow all of these without exception:

    1. NEVER use count(), sum(), avg(), min(), max() in select() without first
       calling group(). Violating this causes a ReferenceError at render time.

    2. group() with NO arguments means "treat entire table as one group".
       Only aggregate expressions are valid in the select() that follows.
       Regular columns like person_id are NOT accessible after bare group().
       Use this only when you want a single aggregate result for the whole table.
       CORRECT: group() → select(count())
       WRONG:   group() → select(person_id, count())

    3. group(column) means "distinct values of that column".
       Use this when you want one row per unique value of a column.
       CORRECT: group(person_id) → select(person_id, count())
       WRONG:   group() → select(person_id)

    4. The grouping key MUST appear in the final select() for per-group results.
       If you group by person_id and want one row per patient, person_id must
       be in select(). Without it you get a single total row, not per-patient rows.
       CORRECT: group(person_id) → select(person_id, count())
       WRONG:   group(person_id) → select(count())

    5. After join(alias => from(table), ...), you MUST project joined columns
       with select() before calling group(). The alias does not survive group().
       CORRECT:
         join(loc => from(location), on = location_id == loc.location_id)
         select(state => loc.state)
         group(state)
         select(state)
       WRONG:
         join(loc => from(location), on = location_id == loc.location_id)
         group(loc.state)
         select(loc.state)

    6. Alias syntax is ALWAYS: new_name => expression (name LEFT, expression RIGHT).
       CORRECT: select(earliest => min(visit_start_date))
       WRONG:   select(min(visit_start_date) => earliest)

    7. In join() conditions, do NOT qualify the left-hand column with its table name.
       CORRECT: on = location_id == loc.location_id
       WRONG:   on = person.location_id == loc.location_id

    ## FunSQL SYNTAX EXAMPLES:

    Question: "How many patients are in the database?"
    @funsql begin
        from(person)
        group()
        select(count())
    end

    Question: "Find patients diagnosed with type 2 diabetes."
    @funsql begin
        from(condition_occurrence)
        filter(condition_concept_id == 201826)
        select(person_id, condition_start_date)
    end

    Question: "How many unique patients have hypertension?"
    @funsql begin
        from(condition_occurrence)
        filter(condition_concept_id == 320128)
        group(person_id)
        select(count())
    end

    Question: "Count patients living in Illinois."
    @funsql begin
        from(person)
        join(loc => from(location), on = location_id == loc.location_id)
        filter(loc.state == "IL")
        group()
        select(count())
    end

    Question: "Find patients with HbA1c above 7%."
    @funsql begin
        from(measurement)
        filter(measurement_concept_id == 3004410 && value_as_number > 7.0)
        select(person_id, measurement_date, value_as_number)
    end

    Question: "Count diagnoses grouped by condition."
    @funsql begin
        from(condition_occurrence)
        group(condition_concept_id)
        select(condition_concept_id, count())
    end

    Question: "For each patient, count how many visits they had."
    @funsql begin
        from(visit_occurrence)
        group(person_id)
        select(person_id, count())
    end

    Question: "Which distinct states appear in the location table?"
    @funsql begin
        from(person)
        join(loc => from(location), on = location_id == loc.location_id)
        select(state => loc.state)
        group(state)
        select(state)
    end 
    
    Question: "What is the earliest and latest visit date in the database?"
    @funsql begin
        from(visit_occurrence)
        group()
        select(min(visit_start_date), max(visit_start_date))
    end

    Question: "List the distinct person_ids who have a measurement recorded."
    @funsql begin
        from(measurement)
        group(person_id)
        select(person_id)
    end

    ## SCHEMA CONTEXT (use ONLY tables and columns listed here):
    $schema_context

    ## QUESTION:
    $question

    ## OUTPUT (only the @funsql block):
    /no_think
    """ 

    verbose && @info "Calling $model via OllamaSchema | prompt=$(length(full_prompt)) chars"

    t_start = time()

    msg = aigenerate(
        PT.OllamaSchema(),
        full_prompt;
        model      = model,
        api_kwargs = (;
            think = false,
            options = (;
                temperature = temperature,
                num_predict = 400
            )
        )
    )

    elapsed_ms = (time() - t_start) * 1000
    verbose && @info "Done in $(round(elapsed_ms; digits=1)) ms"

    return msg.content
end

"""
    generate_funsql_gemini(question, context_chunks; verbose) -> String

Calls Gemini 2.5 Flash Lite for FunSQL generation. Requires GOOGLE_API_KEY in ENV.
"""
function generate_funsql_gemini(
    question       :: String,
    context_chunks :: Vector{<:AbstractString};
    verbose        :: Bool = true
) :: String

    !haskey(ENV, "GOOGLE_API_KEY") && error(
        "GOOGLE_API_KEY not set. Run: ENV[\"GOOGLE_API_KEY\"] = \"your-api-key\""
    )

    schema_context = join(context_chunks, "\n---\n")
    filled_prompt  = replace(
        replace(FUNSQL_SYSTEM_PROMPT, "{{schema_context}}" => schema_context),
        "{{question}}" => question
    )

    verbose && @info "Calling Gemini 2.5 Flash Lite..."
    t_start = time()

    msg = aigenerate(
        PT.GoogleSchema(),
        filled_prompt;
        model      = "gemini-2.5-flash-lite",
        api_kwargs = (; temperature = 0.1)
    )

    elapsed_ms = (time() - t_start) * 1000
    verbose && @info "Gemini done in $(round(elapsed_ms; digits=1)) ms | cost=\$$(msg.cost)"

    return msg.content
end