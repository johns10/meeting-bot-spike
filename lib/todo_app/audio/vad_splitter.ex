defmodule TodoApp.Audio.VADSplitter do
  use Membrane.Filter

  alias Membrane.RawAudio
  alias Membrane.Buffer
  alias Membrane.File.SplitEvent

  @vad_chunk_duration Membrane.Time.milliseconds(30)
  @sample_rate 16_000
  @threshold 0.5

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :s16le, channels: 1, sample_rate: 16_000}
  )

  @impl true
  def handle_init(_ctx, opts) do
    model = Ortex.load(Path.join([:code.priv_dir(:todo_app), "models", "silero_vad.onnx"]))

    {[],
     %{
       model: model,
       h: Nx.broadcast(0.0, {2, 1, 64}),
       c: Nx.broadcast(0.0, {2, 1, 64}),
       vad_chunk_size: nil
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    chunk_size = RawAudio.time_to_bytes(@vad_chunk_duration, stream_format)
    IO.inspect(chunk_size)
    state = Map.put(state, :vad_chunk_size, chunk_size)
    {[stream_format: {:output, raw_audio_format()}], state}
  end

  @impl true
  def handle_buffer(:input, %{payload: payload}, _ctx, %{model: model, h: h, c: c} = state) do
    data = payload

    %{h: hn, c: cn} =
      data
      |> generate_chunks(state.vad_chunk_size)
      |> Enum.reduce(%{h: h, c: c}, fn chunk, %{h: h, c: c} ->
        input = Nx.from_binary(payload, :f32) |> Nx.new_axis(0)
        sr = Nx.tensor(16_000, type: :s64)
        {output, hn, cn} = Ortex.run(model, {input, sr, h, c})

        prob =
          output
          |> Nx.squeeze()
          |> Nx.to_number()

        %{h: hn, c: cn}
      end)

    actions = [
      buffer: {:output, %Buffer{payload: payload}},
      event: {:output, %SplitEvent{}}
    ]

    {actions, %{state | h: hn, c: cn}}
  end

  defp do_predict(model, h, c, audio) do
    input = Nx.from_binary(audio, :f32) |> Nx.new_axis(0)
    sr = Nx.tensor(@sample_rate)
    Ortex.run(model, {input, sr, h, c})
  end

  defp generate_chunks(samples, chunk_size) when byte_size(samples) >= chunk_size do
    <<chunk::binary-size(chunk_size), rest::binary>> = samples
    [chunk | generate_chunks(rest, chunk_size)]
  end

  defp generate_chunks(samples, _chunk_size) do
    [samples]
  end

  defp raw_audio_format, do: %RawAudio{channels: 1, sample_rate: 16_000, sample_format: :s16le}
end
