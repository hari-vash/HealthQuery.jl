"""
    parse_funsql_code(raw_output::String) -> (String, Bool, String)

Extracts, cleans, and validates a @funsql block from raw LLM output.

Returns a 3-tuple:
  - `code`    : The extracted @funsql code string (empty if extraction failed)
  - `valid`   : true if code parses as valid Julia AST
  - `message` : "ok" on success, error description on failure

# Example
```julia
raw = "@funsql begin\n    from(person)\n    select(count(person_id))\nend"
code, valid, msg = parse_funsql_code(raw)
# ("@funsql begin\\n    from(person)...\\nend", true, "ok")
```
"""
function parse_funsql_code(raw_output::String) :: Tuple{String, Bool, String}
    cleaned = raw_output

    fence_match = match(r"```(?:julia)?\s*\n(.*?)\n```"s, cleaned)
    if fence_match !== nothing
        cleaned = fence_match.captures[1]
    end

    cleaned = strip(cleaned)
    block_match = match(r"(@funsql\s+begin.*?^end)"ms, cleaned)

    if block_match === nothing
        inline_match = match(r"@funsql\s+\w+\(.*", cleaned)
        if inline_match === nothing
            return ("", false, "No @funsql block found in LLM output.\nRaw: $raw_output")
        end
        extracted = strip(inline_match.match)
    else
        extracted = strip(block_match.match)
    end

    parsed_expr = try
        Meta.parse(extracted)
    catch e
        return (extracted, false, "Syntax error: $(sprint(showerror, e))")
    end

    if parsed_expr isa Expr && parsed_expr.head == :incomplete
        return (extracted, false, "Incomplete expression — likely truncated by num_predict limit.")
    end

    return (extracted, true, "ok")
end