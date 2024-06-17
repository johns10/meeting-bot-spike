defmodule TodoApp.AudioTest do
  use ExUnit.Case
  doctest TodoApp.Audio
  alias TodoApp.Audio

  describe "Devices" do
    test "list devices happy path" do
      Audio.list_devices()
    end
  end
end
