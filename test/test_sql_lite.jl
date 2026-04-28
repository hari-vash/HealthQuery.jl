using SQLite, DataFrames

raw_conn = SQLite.DB("test/data/omop_test.sqlite")

tables = DBInterface.execute(raw_conn, 
    "SELECT name FROM sqlite_master WHERE type='table'") |> DataFrame
println("Tables in database:")
println(tables)

count_df = DBInterface.execute(raw_conn,
    "SELECT COUNT(*) as n FROM person") |> DataFrame
println("\nDirect SQLite person count: $(count_df.n[1])")

println("\nDatabase file size: $(filesize("test/data/omop_test.sqlite") / 1024 / 1024) MB")