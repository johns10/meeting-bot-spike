defmodule TodoApp.Audio.VADPipelineTest do
  use Membrane.Pipeline
  use ExUnit.Case
  alias TodoApp.Audio.{VADSplitter, SpeakerDiarizationSplitter, Timestamper, Transcriber}

  describe "VAD" do
    test "Base Case" do
      path = "test/fixtures/diarize.raw"

      spec = [
        child(:file_source, %Membrane.File.Source{location: path})
        |> child(:parser, %Membrane.RawAudioParser{
          stream_format: %Membrane.RawAudio{
            channels: 1,
            sample_format: :f32le,
            sample_rate: 16_000
          }
        })
        |> child(:timestamper, Timestamper)
        |> child(:diarize, SpeakerDiarizationSplitter)
        |> child(:pa_sink, %Membrane.File.Sink.Multi{
          location: "~/Documents/tmp/output",
          extension: ".bin"
        })
      ]

      Membrane.Testing.Pipeline.start_link_supervised!(module: :default, spec: spec)
      Process.sleep(2000)
    end
  end
end
