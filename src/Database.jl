using FunSQL
using FunSQL: render, @funsql  # explicit imports needed for eval() scope
using SQLite
using DBInterface
using DataFrames

const _DB_CONNECTION = Ref{Any}(nothing)

"""
    connect_database(db_path::String) -> FunSQL.SQLiteConnection

Opens a FunSQL-wrapped SQLite connection to the OMOP database at `db_path`.
Caches the connection — calling this multiple times with the same path
returns the cached connection without reopening the file.

# Example
```julia
conn = connect_database("test/data/omop_test.sqlite")
```
"""
function connect_database(db_path::String)
    if _DB_CONNECTION[] === nothing
        @info "Opening OMOP database: $db_path"
        _DB_CONNECTION[] = DBInterface.connect(FunSQL.DB{SQLite.DB}, db_path)

        @info "Database connected. FunSQL catalog loaded."
    end
    return _DB_CONNECTION[]
end

"""
    execute_funsql(code::String, conn; verbose=true) -> DataFrame

Takes a validated @funsql code string, evaluates it to get a FunSQL query
object, renders it to SQL, executes against `conn`, and returns a DataFrame.

IMPORTANT: Only call this with code that has passed `parse_funsql_code()`.
Never call with unvalidated LLM output.

# Returns
A `DataFrame` with the query results.

# Throws
- `ErrorException` if eval or rendering fails (malformed FunSQL logic)
- `SQLiteException` if the rendered SQL fails at database level
"""
function execute_funsql(code::String, conn; verbose::Bool = true) :: DataFrame

    expr = Meta.parse(code)

    funsql_query = try
        eval(expr)
    catch e
        error("FunSQL eval failed — likely invalid column/table name.\n" *
              "Code: $code\nError: $(sprint(showerror, e))")
    end

    sql_string = try
        sql = render(conn, funsql_query)
        sql
    catch e
        err_msg = sprint(showerror, e)

        if occursin("aggregate expression requires Group", err_msg)
            @warn "LLM omitted group() before aggregate. Attempting auto-fix..."

            fixed_code = replace(code,
                r"(\n[ \t]+)(select\((?:[a-zA-Z_]\w*\s*=>\s*)?(?:count|min|max|sum|avg)\b)"s =>
                s"\1group()\2"
            )

            verbose && @info "Auto-fixed code:\n$fixed_code"

            fixed_query = eval(Meta.parse(fixed_code))
            sql = render(conn, fixed_query)
            sql
        else
            error("FunSQL render failed.\nCode: $code\nError: $err_msg")
        end
    end

    verbose && @info "Rendered SQL:\n$sql_string"

    result = DBInterface.execute(conn, sql_string) |> DataFrame
    verbose && @info "Query returned $(nrow(result)) rows × $(ncol(result)) columns"

    return result
end

"""
    get_rendered_sql(code::String, conn) -> String

Returns the SQL string that would be generated from a @funsql code block,
without executing it. Useful for auditing and debugging.
"""
function get_rendered_sql(code::String, conn) :: String
    expr  = Meta.parse(code)
    query = eval(expr)
    sql = render(conn, query)
    return sql
end