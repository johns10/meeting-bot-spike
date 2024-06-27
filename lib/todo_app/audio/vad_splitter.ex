defmodule TodoApp.Audio.VADSplitter do
  use Membrane.Filter

  alias Membrane.{RawAudio, Buffer}
  alias Membrane.File.SplitEvent

  @chunk_duration Membrane.Time.milliseconds(30)
  @sample_rate 16_000
  @threshold 0.50

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  @impl true
  def handle_init(_ctx, _opts) do
    model = Ortex.load(Path.join([:code.priv_dir(:todo_app), "models", "silero_vad.onnx"]))

    {[],
     %{
       model: model,
       h: Nx.broadcast(0.0, {2, 1, 64}),
       c: Nx.broadcast(0.0, {2, 1, 64}),
       chunk_size: nil,
       last: 0.0,
       queue: <<>>
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    chunk_size = RawAudio.time_to_bytes(@chunk_duration, stream_format)
    state = Map.put(state, :chunk_size, chunk_size)

    {[stream_format: {:output, stream_format}], state}
  end

  @impl true

  def handle_buffer(:input, %Buffer{payload: payload} = buffer, _ctx, state) do
    %{model: model, h: h, c: c, queue: queue, chunk_size: chunk_size} = state
    dts = Buffer.get_dts_or_pts(buffer)

    {actions, state} =
      (queue <> payload)
      |> generate_chunks(chunk_size)
      |> Enum.reduce({[], state}, fn chunk, {actions, %{last: last} = state} ->
        if byte_size(chunk) == chunk_size do
          {prob, new_h, new_c} = do_predict(model, h, c, chunk)

          new_actions =
            case {last >= @threshold, prob >= @threshold} do
              {false, true} -> [:split, chunk]
              {false, false} -> []
              {true, false} -> [chunk, :split]
              {true, true} -> [chunk]
            end

          {actions ++ new_actions, %{state | h: new_h, c: new_c, last: prob, queue: <<>>}}
        else
          {actions, %{state | queue: chunk}}
        end
      end)

    membrane_actions =
      Enum.reduce(actions, {[], nil}, fn
        :split, {actions, nil} ->
          {[event: {:output, %SplitEvent{}}] ++ actions, nil}

        :split, {actions, %Buffer{} = buffer} ->
          {[buffer: {:output, buffer}, event: {:output, %SplitEvent{}}] ++ actions, nil}

        bin, {actions, nil} when is_binary(bin) ->
          {actions, %Buffer{payload: bin, dts: dts}}

        bin, {actions, %Buffer{payload: acc_bin}} when is_binary(bin) ->
          {actions, %Buffer{payload: acc_bin <> bin, dts: dts}}
      end)
      |> case do
        {actions, nil} -> actions
        {actions, %Buffer{} = buffer} -> [buffer: {:output, buffer}] ++ actions
      end

    {membrane_actions, state}
  end

  defp do_predict(model, h, c, audio) do
    input = Nx.from_binary(audio, :f32) |> Nx.new_axis(0)
    sr = Nx.tensor(@sample_rate)
    {output, new_h, new_c} = Ortex.run(model, {input, sr, h, c})
    prob = output |> Nx.squeeze() |> Nx.to_number()

    {prob, new_h, new_c}
  end

  defp generate_chunks(samples, chunk_size) when byte_size(samples) >= chunk_size do
    <<chunk::binary-size(chunk_size), rest::binary>> = samples
    [chunk | generate_chunks(rest, chunk_size)]
  end

  defp generate_chunks(samples, _chunk_size) do
    [samples]
  end
end
