import Config

config :logger, :console,
  metadata: [:shard, :guild, :channel]


config :nostrum,
  gateway_intents: [
    # :direct_messages,
    # :guild_bans,
    # :guild_members,
    # :guild_message_reactions,
    :guild_messages,
    :guilds,
    :guild_scheduled_events,
    # :message_content
  ]
