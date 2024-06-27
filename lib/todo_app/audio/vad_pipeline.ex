defmodule TodoApp.Audio.VADPipeline do
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    path = opts[:path]

    spec = [
      child(:file_source, %Membrane.File.Source{location: path})
    ]

    {[spec: spec], %{}}
  end
end
