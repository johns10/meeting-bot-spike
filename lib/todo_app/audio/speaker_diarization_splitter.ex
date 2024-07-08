defmodule TodoApp.Audio.SpeakerDiarizationSplitter do
  use Membrane.Filter

  alias Membrane.{RawAudio, Buffer}

  @sample_rate 16_000
  @window_duration_milliseconds 10013
  @window_duration Membrane.Time.milliseconds(@window_duration_milliseconds)
  @chunk_duration_milliseconds 17
  @chunk_duration Membrane.Time.milliseconds(@chunk_duration_milliseconds)
  @window_samples trunc(@window_duration_milliseconds / @chunk_duration_milliseconds)
  @frame_samples trunc(@window_samples / 2)

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :f32le, channels: 1, sample_rate: 16_000}
  )

  @impl true
  def handle_init(_ctx, _opts) do
    model =
      Ortex.load(Path.join([:code.priv_dir(:todo_app), "models", "segmentation-3.0.onnx"]))

    {[],
     %{
       model: model,
       buffers: [],
       binaries: [<<>>],
       speaker_data: [],
       byte_index: 0,
       frame_index: 0
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    window_size = RawAudio.time_to_bytes(@window_duration, stream_format)
    chunk_size = RawAudio.time_to_bytes(@chunk_duration, stream_format)

    state =
      state
      |> Map.put(:window_size, window_size)
      |> Map.put(:chunk_size, chunk_size)
      |> Map.put(:frame_size, trunc(window_size / 2))

    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{payload: payload} = buffer, _ctx, state) do
    # IO.puts("buffer")

    state = accumulate_windows(buffer, state)
    {[buffer: {:output, buffer}], state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    IO.puts("End of stream")
    {[], Map.put(state, :windows, [[], [], []])}
  end

  def accumulate_windows(%Buffer{payload: payload} = buffer, state) do
    %{
      frame_size: frame_size,
      byte_index: byte_index,
      frame_index: frame_index,
      window_size: window_size,
      buffers: buffers,
      binaries: binaries,
      speaker_data: speaker_data
    } = state

    payload_size = byte_size(payload)
    new_byte_index = byte_index + payload_size
    new_frame_index = trunc(new_byte_index / frame_size)

    new_binaries =
      if new_frame_index > frame_index do
        [head | tail] = binaries
        end_of_frame = new_frame_index * frame_size
        remainder = payload_size - (new_byte_index - end_of_frame)

        IO.puts(
          "Byte index #{new_byte_index} with size #{payload_size} exceeded frame #{end_of_frame}, appending #{remainder} bytes"
        )

        <<payload_head::binary-size(remainder), payload_tail::binary>> = payload
        [payload_tail, head <> payload_head | tail]
      else
        [head | tail] = binaries
        [head <> payload | tail]
      end

    new_speaker_data =
      if new_frame_index > frame_index && Enum.count(new_binaries) == 3 do
        [_current, first, second] = new_binaries

        IO.puts(
          "Generating speaker data for start_index #{(frame_index - 1) * frame_size}, end_index #{new_frame_index * frame_size}. There are #{byte_size(first <> second)} bytes"
        )

        [
          %{
            data: get_speaker_data(first <> second, state),
            start_index: (frame_index - 1) * frame_size,
            end_index: new_frame_index * frame_size
          }
          | speaker_data
        ]
      else
        speaker_data
      end

    trimmed_binaries =
      case new_binaries do
        [_first] = binaries -> binaries
        [_first, _second] = binaries -> binaries
        [first, second | _tail] -> [first, second]
      end

    if new_frame_index > frame_index && Enum.count(new_binaries) == 3 do
      overlap_chunk = Nx.broadcast(0, {1, @frame_samples, 7})
      index_to_run = (new_frame_index - 2) * frame_size
      index_before = (new_frame_index - 3) * frame_size

      first_window =
        (Enum.find(new_speaker_data, &(&1.start_index == index_before)) || %{data: overlap_chunk})
        |> Map.get(:data)

      second_window =
        Enum.find(new_speaker_data, &(&1.start_index == index_to_run))
        |> Map.get(:data)

      first_window_values =
        Nx.slice(first_window, [0, 0, 0], [1, @frame_samples, 7])

      first_window_values =
        Nx.slice(second_window, [0, 0, 0], [1, @frame_samples, 7])

      IO.puts("On #{new_frame_index * frame_size}. Can run #{index_to_run}")

      aggregate_windows(first_window, second_window)
    end

    state
    |> Map.put(:byte_index, new_byte_index)
    |> Map.put(:frame_index, new_frame_index)
    |> Map.put(:buffers, [buffer | buffers])
    |> Map.put(:binaries, trimmed_binaries)
    |> Map.put(:speaker_data, new_speaker_data)
  end

  def increment_sampling_windows([0]), do: [0, 1]
  def increment_sampling_windows([0, 1]), do: [1, 2]
  def increment_sampling_windows([1, 2]), do: [2, 0]
  def increment_sampling_windows([2, 0]), do: [0, 1]

  def aggregate_windows(first_window, second_window, opts \\ []) do
    epsilon = Keyword.get(opts, :epsilon, 1.0e-12)
    missing = Keyword.get(opts, :missing, :nan)

    {1, frames_per_window, num_classes} = Nx.shape(first_window)
    num_frames_per_chunk = div(frames_per_window, 2)

    hamming_window = hamming_window(frames_per_window)
    # hamming_window = Nx.broadcast(1.0, {num_frames_per_chunk, 1})

    first_half = Nx.slice(second_window, [0, 0, 0], [1, num_frames_per_chunk, num_classes])

    second_half =
      Nx.slice(first_half, [0, num_frames_per_chunk, 0], [1, num_frames_per_chunk, num_classes])

    combined = Nx.concatenate([first_half, second_half], axis: 1)

    IO.inspect(combined)

    # mask = Nx.is_nan(combined)
    # combined = Nx.replace(combined, mask, 0.0)

    # aggregated_output = Nx.broadcast(0.0, {num_frames_per_chunk, num_classes})
    # overlapping_chunk_count = Nx.broadcast(0.0, {num_frames_per_chunk, num_classes})
    # aggregated_mask = Nx.broadcast(0.0, {num_frames_per_chunk, num_classes})

    # Enum.each(0..(num_frames_per_chunk - 1), fn index ->
    #   aggregated_output = Nx.add(aggregated_output,
    #     Nx.multiply(Nx.multiply(Nx.multiply(Nx.slice(combined, [index, 0], [1, num_classes]), Nx.slice(mask, [index, 0], [1, num_classes])),
    #     Nx.slice(hamming_window, [index, 0], [1, 1])),
    #     Nx.slice(warm_up_window, [index, 0], [1, 1]))
    #   )

    #   overlapping_chunk_count = Nx.add(overlapping_chunk_count,
    #     Nx.multiply(Nx.multiply(Nx.slice(mask, [index, 0], [1, num_classes]),
    #     Nx.slice(hamming_window, [index, 0], [1, 1])),
    #     Nx.slice(warm_up_window, [index, 0], [1, 1]))
    #   )

    #   aggregated_mask = Nx.max(aggregated_mask, Nx.slice(mask, [index, 0], [1, num_classes]))
    # end)

    # average =  Nx.divide(aggregated_output, Nx.max(overlapping_chunk_count, epsilon))

    # average = Nx.map(average, fn x -> if x == 0.0, do: missing, else: x end)

    # %SlidingWindowFeature{data: average}
  end

  def hamming_window(m) when is_integer(m) and m > 1 do
    0..(m - 1)
    |> Enum.map(&calculate_value(&1, m))
    |> Nx.tensor()
  end

  defp calculate_value(n, m) do
    0.54 - 0.46 * :math.cos(2 * :math.pi() * n / (m - 1))
  end

  defp get_speaker_data(binary, %{model: model, chunk_size: chunk_size}) do
    tensor = Nx.from_binary(binary, :f32)
    input = Nx.reshape(tensor, {1, 1, div(byte_size(binary), 4)})
    {result} = Ortex.run(model, {input})
    result
  end
end