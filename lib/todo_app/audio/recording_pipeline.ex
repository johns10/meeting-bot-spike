defmodule TodoApp.Audio.RecordingPipeline do
  use Membrane.Pipeline
  alias Membrane.PortAudio
  alias Membrane.AudioMixer
  alias Membrane.RawAudio

  # @impl true
  # def handle_init(_ctx, opts) do
  #   input_id = opts[:input_id]
  #   output_id = opts[:output_id]
  #   path = opts[:path]

  #   spec = [
  #     child(:pa_src_in, %PortAudio.Source{device_id: input_id})
  #     |> child(:pa_sink, %PortAudio.Sink{device_id: output_id})
  #   ]

  #   {[spec: spec], %{}}
  # end

  @impl true
  def handle_init(_ctx, opts) do
    input_id = opts[:input_id]
    output_id = opts[:output_id]
    path = opts[:path]

    spec = [
      child(:pa_src_in, %PortAudio.Source{
        device_id: input_id,
        sample_rate: 16_000,
        sample_format: :s16le,
        channels: 1
      })
      |> get_child(:mixer),
      child(:pa_src_out, %PortAudio.Source{
        device_id: output_id,
        sample_rate: 16_000,
        sample_format: :s16le,
        channels: 1
      })
      |> get_child(:mixer),
      child(:mixer, %AudioMixer{
        stream_format: %RawAudio{
          channels: 1,
          sample_rate: 16_000,
          sample_format: :s16le
        }
      })
      |> child(:pa_sink, %Membrane.File.Sink{location: path})
    ]

    {[spec: spec], %{}}
  end
end
