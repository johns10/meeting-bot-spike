defmodule TodoApp.Audio.Timestamper do
  use Membrane.Filter
  alias Membrane.{RawAudio, Buffer}

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    {[buffer: {:output, Map.put(buffer, :dts, Membrane.Time.os_time())}], state}
  end
end
