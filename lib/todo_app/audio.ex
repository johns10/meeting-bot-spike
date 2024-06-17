defmodule TodoApp.Audio do
  def list_devices() do
    Membrane.PortAudio.Devices.list()
  end
end
