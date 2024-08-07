import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :todo_app, TodoWeb.Endpoint,
  http: [port: 4002],
  server: false

config :todo_app, Oban, testing: :inline

# Print only warnings and errors during test
config :logger, level: :warning
