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

    cleaned = strip(raw_output)

    # ── Strategy 1: Already has @funsql — just extract it ─────────────────
    # Handles Qwen's clean output and Gemini's Q8 output
    block_match = match(r"(@funsql\s+begin.*?^end)"ms, cleaned)
    if block_match !== nothing
        extracted = strip(block_match.match)
        return _validate(extracted)
    end

    # ── Strategy 2: Fenced block WITH @funsql inside ───────────────────────
    # ```julia\n@funsql begin...end\n```
    fenced_with_macro = match(r"```(?:julia|funsql|sql)?\s*\n(@funsql\s+begin.*?^end)\s*\n```"ms, cleaned)
    if fenced_with_macro !== nothing
        extracted = strip(fenced_with_macro.captures[1])
        return _validate(extracted)
    end

    # ── Strategy 3: Fenced block WITHOUT @funsql (Gemini's style) ─────────
    # Gemini outputs ```funsql\nbegin...end\n``` — we prepend @funsql
    fenced_bare = match(r"```(?:funsql|julia|sql)\s*\n(begin.*?^end)\s*\n```"ms, cleaned)
    if fenced_bare !== nothing
        extracted = "@funsql " * strip(fenced_bare.captures[1])
        return _validate(extracted)
    end

    # ── Strategy 4: Bare begin...end with no fence and no @funsql ──────────
    bare_begin = match(r"^(begin\s+from\(.*?^end)"ms, cleaned)
    if bare_begin !== nothing
        extracted = "@funsql " * strip(bare_begin.captures[1])
        return _validate(extracted)
    end

    return ("", false, "No @funsql block found in LLM output.\nRaw: $raw_output")
end

# Internal helper — validates extracted code as Julia AST
function _validate(code::AbstractString) :: Tuple{String, Bool, String}
    code_str = String(code)
    parsed = try
        Meta.parse(code_str)
    catch e
        return (code_str, false, "Syntax error: $(sprint(showerror, e))")
    end

    if parsed isa Expr && parsed.head == :incomplete
        return (code_str, false, "Incomplete expression — likely truncated.")
    end

    return (code_str, true, "ok")
end