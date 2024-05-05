defmodule HhDiscordApp.Supervisor do
  use Supervisor

  def start(:normal, args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [HhDiscordApp.Consumer, HhDiscordApp.EventStore]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
