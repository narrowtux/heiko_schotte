defmodule HhDiscordApp.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Struct.Interaction
  alias HhDiscordApp.EventStore

  @event_store_delegate ~w[
    GUILD_SCHEDULED_EVENT_CREATE
    GUILD_SCHEDULED_EVENT_DELETE
    GUILD_SCHEDULED_EVENT_UPDATE
    GUILD_SCHEDULED_EVENT_USER_ADD
    GUILD_SCHEDULED_EVENT_USER_REMOVE
  ]a

  def handle_event({scheduled_event, msg, _ws_state})
      when scheduled_event in @event_store_delegate do
    IO.inspect({scheduled_event, msg})
    HhDiscordApp.EventStore.handle_event({scheduled_event, msg})
  end

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "ping_event"}} = msg, _ws_state}
      ) do
    event_id =
      Enum.find_value(msg.data.options, fn
        %{name: "event", value: value} -> value
        _ -> nil
      end)

    with {:ok, event_id} <- parse_event_id(msg.guild_id, event_id),
         event_name when not is_nil(event_name) <- EventStore.get_event_name_by_id(event_id),
         user_ids <- EventStore.get_user_ids_by_event_id(event_id) do
      pings =
        user_ids
        |> Enum.map(&"<@#{&1}>")
        |> Enum.intersperse(" ")

      response = %{
        type: 4,
        data: %{
          content: "#{event_name} :bell: #{pings}"
        }
      }

      {:ok} = Nostrum.Api.create_interaction_response(msg, response)
    else
      {:error, error} when is_binary(error) ->
        response = %{
          type: 4,
          data: %{
            content: error
          }
        }

        {:ok, _} = Nostrum.Api.create_interaction_response(msg, response)
    end
  end

  def handle_event(_rest) do
    :ignore
  end

  @spec parse_event_id(binary(), binary()) :: {:ok, binary()} | {:error, binary()}
  def parse_event_id(guild_id, event_id) do
    cond do
      String.match?(event_id, ~r/^[0-9]+$/) ->
        {:ok, event_id}

      not is_nil(
        matches = Regex.run(~r/^https:\/\/discord.gg\/[a-zA-Z0-9]+\?event=([0-9]+)$/, event_id)
      ) ->
        {:ok, Enum.at(matches, 1)}

      true ->
        scheduled_event_ids = EventStore.find_event_ids_by_name(guild_id, event_id)

        case length(scheduled_event_ids) do
          0 ->
            {:error, "Wa? '#{event_id}' gibt's doch gar nicht."}

          1 ->
            {:ok, List.first(scheduled_event_ids)}

          more ->
            {:error,
             "Hä? Es gibt #{more} meetups, die '#{event_id}' enthalten. Mach mal ne klare Ansage"}
        end
    end
  end
end
