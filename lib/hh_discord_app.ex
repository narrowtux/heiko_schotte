defmodule HhDiscordApp do
  def commands do
    [
      ping_scheduled_event_command_map(),
      purge_channel_command_map()
    ]
  end

  def ping_scheduled_event_command_map() do
    %{
      name: "ping_event",
      description: "nervt alle Nutzer, die sich für ein Event interessieren mit einem Ping. Bitte verwende das nicht zu oft!",
      default_permission: true,
      options: [
        %{
          name: "event",
          description: "Teil des Namens oder die Nummer des Events",
          type: 3,
          required: true
        }
      ]
    }
  end

  def purge_channel_command_map() do
    %{
      name: "purge_channel",
      description: "Schick mich zum Tatort, ich werde alle Nachrichten vor 5 Tagen löschen",
      default_permission: false,
      options: [
        %{
          name: "limit",
          description: "Wie viele Nachrichten sollen es maximal sein?",
          type: 4
        },
        %{
          name: "to",
          description: "Bis wann darf ich löschen (in Tagen vor heute)",
          type: 4
        },
        %{
          name: "starboard_threshold",
          description: "wie viele sterne braucht eine Nachricht für die Sternschanze?",
          type: 4
        }
      ]
    }
  end
end
