defmodule Cog.Adapters.Slack.RTMConnector do

  # ping periodically so Slack knows we're still here
  @ping_interval 30000 # 30 seconds

  @send_chat_message_timeout 5000 # 5 seconds


  @typedoc """
  Custom state struct for the Slack `gen_server`-esque Websocket client.

  See [the Slack library] for more.

  ## Fields

  * `:id` - The ID of the bot user, e.g. `"U023BECGF"`
  * `:direct_name` - The bot id, wrapped in brackets and an "@",
    e.g. `"<@U023BECGF>"`. This is how mentions look in a received
    message; we'll need it to figure out when someone is talking
    directly to the bot.
  * `:name` - The name of the bot user, without the "@", e.g. `"cog"`
  * `:bus` - connection to the Cog message bus

  [the Slack library]: https://github.com/BlakeWilliams/Elixir-Slack

  """
  @type state :: %__MODULE__{id: String.t,
                             direct_name: String.t,
                             name: String.t,
                             bus: Carrier.Messaging.Connection.connection}
  defstruct [id: nil,
             direct_name: nil,
             name: nil,
             bus: nil]

  require Logger
  use Slack
  alias Cog.Adapters.Slack.API

  @adapter_name "Slack"

  ########################################################################
  # Public API

  # We don't have any initial state per se; everything we care about
  # is available in `handle_connect/2`
  @initial_state nil

  def start_link(token) do
    # `start_link/2` is generated for us by `use Slack`
    __MODULE__.start_link(token, @initial_state)
  end

  @doc """
  Send a message directly to Slack.

  We're using a bit of messaging indirection here because otherwise we
  don't have access to the `slack` object.

  Not clear that this is really used currently.
  """
  def send_chat_message(room, message) when is_binary(room) and is_binary(message) do
    ref = :erlang.make_ref()
    send(__MODULE__, {{:send_message, ref, self()}, room, message})
    receive do
      {^ref, reply} ->
        reply
    after @send_chat_message_timeout ->
        {:error, :timeout}
    end
  end

  ########################################################################
  # Slack callbacks
  #
  # Slack-Elixir defines the following overridable callback
  # implementations:
  #
  # * handle_connect/2
  # * handle_message/3
  # * handle_close/3
  # * handle_info/3

  @doc """
  Sets up our connection with our command bus and initializes our
  state.
  """
  def handle_connect(slack, @initial_state) do
    {:ok, bus} = Carrier.Messaging.Connection.connect()
    Carrier.Messaging.Connection.subscribe(bus, "/bot/adapters/slack/+")
    state = %__MODULE__{id: slack.me.id,
                        name: slack.me.name,
                        direct_name: "<@" <> slack.me.id <> ">",
                        bus: bus}
    :erlang.register(__MODULE__, self())
    Logger.info("#{__MODULE__} initialized")

    # TODO: do we want to capture the timer reference for anything?
    {:ok, _timer_ref} = :timer.send_interval(@ping_interval, :send_ping)
    {:ok, state}
  end

  def handle_message(%{type: "message", user: user_id, channel: channel, text: text}, _slack, state) do
    case invocation_type(user_id, channel, text, state) do
      :ignore ->
        {:ok, state}
      {:direct, room} ->
        # Someone's talking directly to the bot 1-on-1
        handle_direct_command(room, user_id, text, state)
      {:mention, room} ->
        # Command invocation by mention, e.g. "@bot run-command"
        handle_mention_command(room, user_id, text, state)
      {:prefix, room} ->
        # Using special prefix, e.g. "!run-command"
        handle_command(room, user_id, text, state)
    end
  end
  # Called when a user edits a previous command
  def handle_message(%{channel: channel, type: "message", message: %{edited: _info, text: text, user: user_id}}, slack, state) do
    {:ok, user} = API.lookup_user(id: user_id)
    {message, handler} = case invocation_type(user_id, channel, text, state) do
                           :ignored ->
                             {nil, fn() -> {:ok, state} end}
                           {:direct, room} ->
                             {"Executing edited command '#{text}'",
                               fn() -> handle_direct_command(room, user_id, text, state) end}
                           {:mention, room} ->
                             {"@#{user.handle} Executing edited command '#{remove_mention(text, state)}'",
                               fn() -> handle_mention_command(room, user_id, text, state) end}
                           {:prefix, room} ->
                             {"@#{user.handle} Executing edited command '#{remove_mention(text, state)}'",
                              fn() -> handle_command(room, user_id, text, state) end}
                         end
    unless message == nil do
      send_message(message, channel, slack)
    end
    handler.()
  end
  def handle_message(_message, _slack, state) do
    {:ok, state}
  end

  @doc """
  Handle raw messages sent to this process. This is how we receive
  messages from our command bus.
  """
  def handle_info(:send_ping, slack, state) do
    # We send ourselves this message periodically in order to keep the
    # connection with Slack alive
    {:ok, json} = Poison.encode(%{type: "ping"})
    send_raw(json, slack)
    {:ok, state}
  end
  def handle_info({:publish, "/bot/adapters/slack/send_message", message}, slack, state) do
    # We got a message back from one of our commands; pass it along to Slack
    case Carrier.CredentialManager.verify_signed_message(message) do
      {true, payload} ->
        send_message(payload["response"], payload["room"]["id"], slack)
      false ->
        Logger.error("Message signature not verified! #{inspect message}")
    end
    {:ok, state}
  end
  def handle_info({{:send_message, ref, sender}, room, message}, slack, state) do
    send_message(message, room, slack)
    send(sender, {ref, :ok})
    {:ok, state}
  end
  def handle_info(info, _slack, state) do
    Logger.info("#{inspect __MODULE__}: received unexpected message: #{inspect info}")
    {:ok, state}
  end

  ########################################################################
  # Helpers

  # Handle commands that are invoked with a special command prefix
  #
  # Example:
  #
  #     !do-something
  #
  # Only works if `:enable_spoken_commands` is not explicitly
  # disabled.
  defp handle_command(room, user_id, text, state) do
    case Application.get_env(:cog, :enable_spoken_commands, true) do
      false ->
        {:ok, state}
      true ->
        text = Regex.replace(~r/^#{command_prefix}/, text, "")
        forward_command(room, user_id, text, state)
    end
  end

  # One-on-one commands in direct chat
  #
  # The same as `forward_command/4`, since we shouldn't need to do any
  # stripping before putting the command on the bus
  defp handle_direct_command(room, user_id, text, state),
   do: forward_command(room, user_id, text, state)

  # Respond to commands invoked via mention. Strips off the mention to
  # get the raw command and passes it on to the command bus.
  #
  # Example:
  #
  #     @bot do-something
  defp handle_mention_command(room, user_id, text, state) do
    text = remove_mention(text, state)
    forward_command(room, user_id, text, state)
  end

  # Take a raw command text (stripped of any bot mentions or command
  # prefixes) and place it on the command bus
  defp forward_command(room, user_id, text, state) do
    {:ok, sender} = API.lookup_user(id: user_id)
    payload = %{sender: sender,
                room: room,
                text: text,
                adapter: @adapter_name,
                reply: "/bot/adapters/slack/send_message"}
    Carrier.Messaging.Connection.publish(state.bus, payload, routed_by: "/bot/commands")
    {:ok, state}
  end

  # Define the prefix used when `:enable_spoken_commands` is active.
  defp command_prefix,
    do: Application.get_env(:cog, :command_prefix, "!")

  defp remove_mention(text, state) do
    ["", text] = String.split(text, state.direct_name)
    Regex.replace(~r/^:\s*/, text, "")
  end

  defp invocation_type(user_id, channel, text, state) do
    case user_id == state.id do
      true ->
        :ignore
      false ->
        # Determine how to respond based on what kind of message it is
        {:ok, room} = API.lookup_room(id: channel)
        cond do
          room.name == "direct" ->
               {:direct, room}
          String.starts_with?(text, state.direct_name) ->
               {:mention, room}
          String.starts_with?(text, command_prefix) ->
               {:prefix, room}
          true ->
            :ignore
        end
    end
  end

end