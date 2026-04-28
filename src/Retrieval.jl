using RAGTools
using PromptingTools
const PT = PromptingTools

include("omop_schema_chunks.jl")

function _register_ollama_embed_model!()
    if !haskey(PT.MODEL_REGISTRY, "nomic-embed-text")
        PT.register_model!(;
            name        = "nomic-embed-text",
            schema      = PT.OllamaSchema(),
            description = "Ollama local embedding model. 768-dim vectors. " *
                          "Surpasses OpenAI ada-002 on MTEB benchmarks.")
        @info "Registered nomic-embed-text with OllamaSchema"
    end
end

_register_ollama_embed_model!()


"""
    build_schema_index(; verbose=true) -> InMemoryBackend

Embeds all OMOP schema chunks using nomic-embed-text via Ollama and returns
an InMemoryBackend wrapping a RAGTools ChunkEmbeddingsIndex.

This function is called ONCE at startup. The returned backend is then passed
to `retrieve_context` on every query. Building takes ~5-15 seconds depending
on your hardware (it makes one Ollama API call per chunk).

# Example
```julia
backend = build_schema_index()
context = retrieve_context(backend, "How many patients have diabetes?")
```
"""
function build_schema_index(; verbose::Bool = true)
    verbose && @info "Building OMOP schema index with $(length(OMOP_SCHEMA_CHUNKS)) chunks..."
    verbose && @info "Using embedder: nomic-embed-text via Ollama"

    chunk_index = build_index(
        OMOP_SCHEMA_CHUNKS;
        chunker_kwargs  = (; sources = OMOP_SCHEMA_SOURCES),
        embedder_kwargs = (; model = "nomic-embed-text"),
        verbose = verbose ? 1 : 0
    )

    verbose && @info "Schema index built successfully. $(length(OMOP_SCHEMA_CHUNKS)) chunks indexed."
    return InMemoryBackend(chunk_index)
end

"""
    retrieve_context(backend::InMemoryBackend, question::String;
                     top_k=4, verbose=true) -> Vector{String}

Given a plain-English question, returns the top-k most relevant OMOP schema
chunks from the index. These chunks are what get injected into the LLM prompt.

`top_k=4` is a deliberate choice: typically 1-2 tables are relevant to any
question. 4 chunks gives enough context without overloading the prompt.

# Example
```julia
chunks = retrieve_context(backend, "What is the average age of diabetic patients?")
# Returns chunks about: condition_occurrence, person, concept
```
"""
function retrieve_context(
    backend  :: InMemoryBackend,
    question :: String;
    top_k    :: Int = 4,
    verbose  :: Bool = true
)

    rag_result = retrieve(
        backend.index,
        question;
        top_k = top_k,
        embedder_kwargs = (; model = "nomic-embed-text")
    )

    retrieved_chunks = rag_result.context

    if verbose
        @info "Retrieved $(length(retrieved_chunks)) chunks for question: \"$question\""
        for (i, src) in enumerate(rag_result.sources)
            @info "  Chunk $i source: $src"
        end
    end

    return retrieved_chunks
end