defmodule HhDiscordApp.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Struct.Interaction
  alias HhDiscordApp.EventStore
  require Logger

  @event_store_delegate ~w[
    GUILD_SCHEDULED_EVENT_CREATE
    GUILD_SCHEDULED_EVENT_DELETE
    GUILD_SCHEDULED_EVENT_UPDATE
    GUILD_SCHEDULED_EVENT_USER_ADD
    GUILD_SCHEDULED_EVENT_USER_REMOVE
  ]a

  def handle_event({scheduled_event, msg, _ws_state})
      when scheduled_event in @event_store_delegate do
    HhDiscordApp.EventStore.handle_event({scheduled_event, msg})
  end

  def handle_event({:READY, %Nostrum.Struct.Event.Ready{} = ready, _ws_state}) do
    for %{id: guild_id} <- ready.guilds, command <- HhDiscordApp.commands() do
      Nostrum.Api.ApplicationCommand.create_guild_command(guild_id, command)
    end
  end

  @purge_member_ids [
    # narrowtux
    91995529558396928,
    # mia
    494586788392730639,
    #sponge
    244851781975277570,
    #agathe
    266899016065744896,
    #laurenz
    140252855373135873
  ]
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "purge_channel"}} = interaction,
         _ws_state}
      ) do


    if not interaction.member.user_id in @purge_member_ids do
      response = %{
        type: 4,
        data: %{
          content: "was willst du denn? von dir lass ich mir ja mal gar nichts sagen!"
        }
      }
      Nostrum.Api.Interaction.create_response(interaction, response)
    else
      response = %{
        type: 4,
        data: %{
          content: start_message()
        }
      }

      Nostrum.Api.Interaction.create_response(interaction, response)

      opts = interaction.data.options || []

      to = Enum.find_value(opts, fn
        %{name: "to", value: value} when is_integer(value) -> value
        _ -> nil
      end)

      limit = Enum.find_value(opts, fn
        %{name: "limit", value: value} when is_integer(value) -> value
        _ -> nil
      end)

      starboard_threshold = Enum.find_value(opts, fn
        %{name: "starboard_threshold", value: value} when is_integer(value) -> value
        _ -> nil
      end)

      before =
        DateTime.utc_now()
        |> DateTime.add(-(to || 5), :day)

      Task.start_link(fn ->
        purge_messages(interaction.channel_id, before, limit || 100, starboard_threshold || 7)
      end)
    end
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

      {:ok} = Nostrum.Api.Interaction.create_response(msg, response)
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

  def purge_messages(channel_id, before, limit, starboard_threshold) do
    cutoff = DateTime.utc_now() |> DateTime.add(-13, :day)
    tc_begin = DateTime.utc_now()

    with {:ok, raw_messages} <-
           Nostrum.Api.Channel.messages(
             channel_id,
             limit,
             {:before, Nostrum.Snowflake.from_datetime!(before)}
           ) do
      messages = Enum.reject(raw_messages, &is_on_starboard?(&1, starboard_threshold))

      batchable = Enum.filter(messages, &(DateTime.compare(&1.timestamp, cutoff) == :gt))
      not_batchable = Enum.filter(messages, &(DateTime.compare(&1.timestamp, cutoff) != :gt))

      {batchable, not_batchable} = case batchable do
        [one] -> {[], [one | not_batchable]}
        other -> {other, not_batchable}
      end

      Logger.info("batch-deleting #{length(batchable)} messages")
      {:ok} = Nostrum.Api.Channel.bulk_delete_messages(channel_id, Enum.map(batchable, & &1.id))

      for msg <- not_batchable do
        Logger.info("deleting single message from #{msg.timestamp}")
        {:ok} = Nostrum.Api.Message.delete(msg)
      end

      tc_end = DateTime.utc_now()

      diff = DateTime.diff(tc_end, tc_begin, :second)

      message =
        success_message(
          length(batchable),
          length(not_batchable),
          length(raw_messages) - length(messages),
          diff
        )

      Nostrum.Api.Message.create(channel_id, content: message)
    end
  end

  @star_emoji ~w[⭐ 💫 ✨ 🌟]

  def is_on_starboard?(message, threshold \\ 1) do
    (message.reactions || [])
    |> Enum.filter(fn %{emoji: emoji} ->
      is_nil(emoji.managed) && emoji.name in @star_emoji
    end)
    |> Enum.map(& &1.count)
    |> Enum.sum()
    |> Kernel.>=(threshold)
  end

  def success_message(batchable, non_batchable, starboard, duration)

  def success_message(0, 0, _, _) do
    """
    Aber mal ehrlich – warum hat man mich hierher bestellt? Ich steh’ mitten im Raum,
    Gummihandschuhe an, Schrubber in der Hand… und nix zu tun! Kein Fleck, keine Schmiererei,
    gar nix. Ein Tatort, der schon glänzt – da fühl ich mich ja fast überflüssig.

    Na gut, dann pack ich meine Sachen wieder ein. Auftrag (naja, mehr oder weniger) erledigt.
    """
  end

  def success_message(batchable, 0, starboard, duration) do
    """
    Habe mich durch den Discord-Schauplatz gewischt und ganze #{batchable} Nachrichten entfernt –
    lief wie 'ne frische Blutlache auf Linoleum, ein sauberer Wisch und weg.
    Kein hartnäckiger Dreck, nix Eingetrocknetes, einfach schnelles, effizientes Aufräumen.

    #{starboard_message(starboard)}

    Einsatz in #{duration} Sekunden beendet, alles wieder tipptopp.
    """
  end

  def success_message(0, non_batchable, starboard, duration) do
    """
    Heute war’s mühsam – keine glatten Fliesen, nur tief eingezogene Flecken im Teppich.
    Jede einzelne der #{non_batchable} Nachrichten musste ich manuell rauskratzen,
    wie angetrocknetes Hirn von der Tapete. Stück für Stück, Nachricht für Nachricht,
    aber jetzt is’ alles wieder sauber.

    #{starboard_message(starboard)}

    Einsatz in #{duration} Sekunden abgeschlossen, war ‘ne schmutzige Nummer.
    """
  end

  def success_message(batchable, non_batchable, starboard, duration) do
    """
    Habe mich durch den Discord-Schlachtplatz gewühlt und ordentlich klar Schiff gemacht.
    #{batchable} Nachrichten ließen sich mit einem beherzten Wisch wie Blutspritzer von glatter Fliese entfernen – zack, weg.
    Aber #{non_batchable} Nachrichten waren wie eingetrocknete Flecken im Teppich – mussten einzeln rausgekratzt werden.

    #{starboard_message(starboard)}

    Hat #{duration} Sekunden gedauert, aber nu is wieder alles blitzeblank.
    """
  end

  def starboard_message(0), do: ""

  def starboard_message(amount) do
    """
    Manche Flecken will man gar nicht wegmachen – #{amount} Nachrichten waren so beliebt, die durfte ich nicht anrühren.
    Quasi wie 'ne schön gesicherte Blutspur für die Ermittler, die bleibt.
    """
  end

  def start_message() do
    """
    Moin, ich bin Heiko Schotte, dein Tatortreiniger für digitalen Kladderadatsch.

    Ich pack die Gummihandschuhe aus, jetzt wird aufgeräumt.
    Ich mach mich ran an die Sauerei und sorge dafür, dass hier wieder alles glänzt. Gleich gibt’s 'nen sauberen Bericht.
    """
  end
end
