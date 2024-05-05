defmodule HhDiscordApp do
  def ping_scheduled_event_command_map() do
    %{
      name: "ping_event",
      description: "pings all users (up to 30) of a given scheduled event",
      options: [
        %{
          name: "event",
          description: "Which event to notify edit",
          type: 3,
          required: true
        }
      ]
    }
  end
end
