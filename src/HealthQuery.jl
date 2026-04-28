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

end