defmodule HhDiscordAppTest do
  use ExUnit.Case
  doctest HhDiscordApp

  test "greets the world" do
    assert HhDiscordApp.hello() == :world
  end
end
