import Config

config :nostrum,
  token: System.fetch_env!("DISCORD_API_TOKEN")
