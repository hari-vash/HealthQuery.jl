"""
    AbstractVectorBackend

Abstract type for all vector database backends.
Concrete subtypes must implement:
  - `similarity_search(backend, query_embedding, top_k) → Vector{String}`
  - `add_documents!(backend, docs, embeddings) → nothing`
"""
abstract type AbstractVectorBackend end

"""
    InMemoryBackend <: AbstractVectorBackend

The default backend — uses RAGTools.jl's ChunkIndex, stored entirely in RAM.
Zero external dependencies, perfect for development and small schema indexes.
"""
struct InMemoryBackend <: AbstractVectorBackend
    index::Any
end

"""
    QueryResult

What we return to the user after a complete pipeline run.
"""
struct QueryResult
    question::String
    funsql_code::String       
    sql_string::String         
    dataframe::Any             
    latency_ms::Float64        
    token_cost::Float64        
    success::Bool
    error_message::Union{String, Nothing}
end