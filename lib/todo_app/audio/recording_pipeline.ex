defmodule TodoApp.Audio.RecordingPipeline do
  use Membrane.Pipeline
  alias Membrane.PortAudio
  alias TodoApp.Audio.VADSplitter

  @impl true
  def handle_init(_ctx, opts) do
    input_id = opts[:input_id]
    _output_id = opts[:output_id]
    path = opts[:path]

    spec = [
      child(:pa_src_in, %PortAudio.Source{
        device_id: input_id,
        sample_rate: 16_000,
        sample_format: :f32le,
        channels: 1
      })
      |> child(:filter, VADSplitter)
      |> child(:pa_sink, %Membrane.File.Sink{location: path})
    ]

    {[spec: spec], %{}}
  end
end
