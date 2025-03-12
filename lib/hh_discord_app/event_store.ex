defmodule HhDiscordApp.EventStore do
  use GenServer
  alias Nostrum.Api
  require Logger

  @guild_id 518_735_458_759_475_206

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    table_opts = [
      :named_table,
      :public
    ]

    :ets.new(:guild_events, table_opts ++ [:ordered_set])
    :ets.new(:guild_event_users, table_opts ++ [:bag])

    {:ok, nil, {:continue, nil}}
  end

  def handle_continue(_, state) do
    case Api.Guild.scheduled_events(@guild_id) do
      {:ok, scheduled_events} ->
        for event <- scheduled_events do
          :ets.insert(:guild_events, {event.id, event.name, event.guild_id})

          case Api.ScheduledEvent.users(@guild_id, event.id) do
            {:ok, users} ->
              for user <- users do
                :ets.insert(:guild_event_users, {event.id, user.user.id})
              end
          end
        end
    end

    Logger.info("Loaded all events and their users")

    {:noreply, state}
  end

  def handle_event(
        {:GUILD_SCHEDULED_EVENT_CREATE, %Nostrum.Struct.Guild.ScheduledEvent{} = event}
      ) do
    :ets.insert(:guild_events, {event.id, event.name, event.guild_id})
  end

  def handle_event(
        {:GUILD_SCHEDULED_EVENT_DELETE, %Nostrum.Struct.Guild.ScheduledEvent{} = event}
      ) do
    :ets.delete_object(:guild_events, {event.id, event.name, event.guild_id})
  end

  def handle_event(
        {:GUILD_SCHEDULED_EVENT_UPDATE, %Nostrum.Struct.Guild.ScheduledEvent{} = event}
      ) do
    :ets.update_element(:guild_events, event.id, {event.id, event.name, event.guild_id})
  end

  def handle_event(
        {:GUILD_SCHEDULED_EVENT_USER_ADD,
         %Nostrum.Struct.Event.GuildScheduledEventUserAdd{} = event}
      ) do
    :ets.insert(:guild_event_users, {event.guild_scheduled_event_id, event.user_id})
  end

  def handle_event(
        {:GUILD_SCHEDULED_EVENT_USER_REMOVE,
         %Nostrum.Struct.Event.GuildScheduledEventUserRemove{} = event}
      ) do
    :ets.delete_object(:guild_event_users, {event.guild_scheduled_event_id, event.user_id})
  end

  def get_event_name_by_id(event_id) do
    case :ets.lookup(:guild_events, event_id) do
      [] -> nil
      [{_, name, _}] -> name
    end
  end

  def get_user_ids_by_event_id(event_id) do
    :ets.lookup(:guild_event_users, event_id)
    |> Enum.map(&elem(&1, 1))
  end

  def find_event_ids_by_name(guild_id, search) do
    search = String.downcase(search)

    :ets.tab2list(:guild_events)
    |> Enum.filter(fn {_, event_name, event_guild_id} ->
      event_guild_id == guild_id && String.contains?(String.downcase(event_name), search)
    end)
    |> Enum.map(&elem(&1, 0))
  end
end
