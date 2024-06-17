defmodule TodoApp.Audio.VADPipelineTest do
  use Membrane.Pipeline
  use ExUnit.Case
  alias TodoApp.Audio.VADSplitter

  describe "VAD" do
    test "Base Case" do
      path = "test/fixtures/vad.raw"

      spec = [
        child(:file_source, %Membrane.File.Source{location: path})
        |> child(:parser, %Membrane.RawAudioParser{
          stream_format: %Membrane.RawAudio{
            channels: 1,
            sample_format: :s16le,
            sample_rate: 16_000
          }
        })
        |> child(:filter, VADSplitter)
        |> child(:file_sink, %Membrane.File.Sink{location: "test/fixtures/vad_out.raw"})
      ]

      Membrane.Testing.Pipeline.start_link_supervised!(module: :default, spec: spec)
      Process.sleep(1000)
    end
  end
end
