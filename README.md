# HealthQuery.jl

A Retrieval-Augmented Generation (RAG) framework for translating plain-English 
clinical questions into executable [FunSQL.jl](https://github.com/MechanicalRabbit/FunSQL.jl) 
queries against OMOP Common Data Model databases.

Built for the [JuliaHealth](https://juliahealth.org/) ecosystem as part of Google Summer of Code 2026.

## What It Does

A clinical researcher types a plain-English question:

```
"How many female patients were diagnosed with diabetes after 2010?"
```

HealthQuery returns a verified SQL query and a DataFrame result — with zero 
manual SQL writing, using only local models (no cloud API required).

## Architecture

```
Question (plain English)
    │
    ▼  [Retrieval]      nomic-embed-text via Ollama
    │  Embed question → search OMOP schema vector index → top-4 chunks
    │
    ▼  [Generation]     qwen3.5:4b via Ollama  
    │  Schema context + few-shot examples → @funsql Julia code
    │
    ▼  [PostProcessing]
    │  Extract @funsql block → Meta.parse AST validation
    │
    ▼  [Database]       FunSQL.jl + SQLite.jl
    │  render() → SQL string → DBInterface.execute() → DataFrame
    │
    ▼
DataFrame result + rendered SQL (fully auditable)
```

## Quick Start

### Prerequisites
- Julia 1.10+
- [Ollama](https://ollama.com/) running locally with:
```bash
  ollama pull qwen3.5:4b
  ollama pull nomic-embed-text
```

### Installation

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

### Usage

```julia
using HealthQuery

# One-time setup
backend = build_schema_index()
conn    = connect_database("test/data/omop_test.sqlite")

# Ask a health question
result = query_health_data(
    "How many female patients are in the database?",
    backend, conn
)

println(result.dataframe)
println(result.sql_string)   # fully auditable SQL
```

## Evaluation

Benchmarked against a golden dataset of 8 OMOP CDM queries covering:
simple counts, filters, joins, multi-aggregates, date ranges, and grouping patterns.

| Model | Parse Rate | Exec Success | Execution Accuracy | Avg Latency |
|---|---|---|---|---|
| qwen3.5:4b (local) | 100% | 100% | **100%** | ~17s |

Run the evaluation yourself:

```julia
include("test/runtests.jl")
```

## Project Structure

```
HealthQuery/
├── src/
│   ├── HealthQuery.jl       # Main module + query_health_data() entry point
│   ├── Types.jl             # Abstract types (AbstractVectorBackend, QueryResult)
│   ├── Retrieval.jl         # OMOP schema vector index (RAGTools.jl)
│   ├── Generation.jl        # LLM orchestration (PromptingTools.jl)
│   ├── PostProcessing.jl    # Code extraction + AST validation
│   ├── Database.jl          # FunSQL rendering + execution
│   ├── Evaluation.jl        # Benchmark harness + golden dataset
│   └── omop_schema_chunks.jl  # OMOP CDM knowledge base (10 tables)
├── test/
│   ├── runtests.jl          # Full evaluation run
│   └── data/
│       └── omop_test.sqlite # Synthetic 10-patient OMOP CDM database
└── README.md
```

## Key Design Decisions

**Why FunSQL instead of raw SQL strings?**  
FunSQL validates query structure before database execution. Invalid column names 
or broken joins raise Julia errors — not opaque database errors. Every query is 
fully auditable via `result.sql_string`.

**Why local models?**  
Clinical data is sensitive. A fully local pipeline (Ollama + SQLite) means 
patient data never leaves the machine. No API keys, no cloud dependency, zero cost.

**Why RAG over fine-tuning?**  
The OMOP CDM schema is the domain knowledge that changes per deployment 
(different hospitals have different table populations). RAG retrieves the 
relevant schema at query time — no retraining required when the schema changes.

## Stretch Goals (Future Work)
- Abstract vector database interface (Qdrant, PgVector backends)
- Gemini / cloud model integration for comparison benchmarking  
- Extended golden dataset (50+ queries)
- PostgreSQL support via FunSQL's dialect system

## Acknowledgements
Built on [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl), 
[RAGTools.jl](https://github.com/JuliaGenAI/RAGTools.jl), and 
[FunSQL.jl](https://github.com/MechanicalRabbit/FunSQL.jl).  
Test database: [ohdsi-synpuf-demo](https://github.com/MechanicalRabbit/ohdsi-synpuf-demo).