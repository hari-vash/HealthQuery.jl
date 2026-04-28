using DotEnv
DotEnv.load!()

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using GoogleGenAI, PromptingTools
const PT = PromptingTools

println("API key loaded: ", haskey(ENV, "GOOGLE_API_KEY"))
println("Key length: ", length(get(ENV, "GOOGLE_API_KEY", "")))

msg = PT.aigenerate(
    PT.GoogleSchema(),
    "Reply with the single word: hello";
    model      = "gemini-2.5-flash-lite",
    api_kwargs = (; temperature = 0.1)
)
println("Response: ", msg.content)