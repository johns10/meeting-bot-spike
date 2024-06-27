defmodule TodoApp.TranscribeTest do
  use ExUnit.Case
  doctest TodoApp.Transcribe
  alias TodoApp.Transcribe

  describe "TEst Nif" do
    test "works" do
      assert [
               %{
                 "transcription" => [
                   %{"text" => " Testing " <> _},
                   %{"text" => " 1, 2, 3." <> _}
                 ]
               }
             ] =
               Transcribe.transcribe_files(["test/fixtures/vad-f32.raw"])
               |> Jason.decode!()
    end
  end
end
