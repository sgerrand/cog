use Mix.Config

config :logger, :console,
  level: :debug

config :cog,
  adapter: System.get_env("COG_ADAPTER") || Cog.Adapters.Slack

config :cog, :enable_spoken_commands, false

config :cog, Cog.Adapters.Slack,
  rtm_token: System.get_env("SLACK_RTM_TOKEN"),
  api_token: System.get_env("SLACK_API_TOKEN"),
  api_cache_ttl: System.get_env("SLACK_API_CACHE_TTL") || 900

config :cog, Cog.Adapters.HipChat,
  xmpp_jid: System.get_env("HIPCHAT_XMPP_JID"),
  xmpp_password: System.get_env("HIPCHAT_XMPP_PASSWORD"),
  xmpp_nickname: System.get_env("HIPCHAT_XMPP_NICKNAME") || "Cog",
  xmpp_server: System.get_env("HIPCHAT_XMPP_SERVER"),
  xmpp_port: System.get_env("HIPCHAT_XMPP_PORT") || 5222,
  xmpp_resource: "bot",
  xmpp_rooms: System.get_env("HIPCHAT_XMPP_ROOMS"),
  api_token: System.get_env("HIPCHAT_API_TOKEN"),
  mention_name: System.get_env("HIPCHAT_MENTION_NAME")

config :carrier, Carrier.Messaging.Connection,
  host: "127.0.0.1",
  port: 1883

config :cog, Cog.Adapters.SSH,
  host_key_dir: System.get_env("SSH_HOST_KEY_DIR"),
  port: System.get_env("SSH_PORT"),
  bot_username: System.get_env("SSH_USERNAME") || "cog"

config :cog, Cog.Adapters.WebSocket,
  websocket_uri: "ws://localhost:4000/sockets/websocket",
  bot_username: System.get_env("SSH_USERNAME") || "cog"

config :cog,
  :template_cache_ttl, {1, :sec}

config :emqttd, :listeners,
  [{:mqtt, 1883, [acceptors: 16,
                  max_clients: 64,
                  access: [allow: :all],
                  sockopts: [backlog: 8,
                             ip: "127.0.0.1",
                             recbuf: 4096,
                             sndbuf: 4096,
                             buffer: 4096]]}]

config :cog, Cog.Repo,
  adapter: Ecto.Adapters.Postgres,
  pool_size: 10

config :cog, Cog.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  cache_static_lookup: false,
  check_origin: false,
  render_errors: [view: Cog.ErrorView, accepts: ~w(json)]

config :cog, Cog.Endpoint,
  live_reload: [
    patterns: [
      ~r{lib/cog/models/.*(ex)$},
      ~r{web/.*(ex)$}
    ]
  ]

config :cog, Cog.Passwords,
  # 4-round hashing for dev only
  salt: "$2b$04$me8.bWW9urIiJbTLCCDt1."