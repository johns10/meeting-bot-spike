defmodule TodoWeb.TodoLive do
  @moduledoc """
    Main live view of our TodoApp. Just allows adding, removing and checking off
    todo items
  """
  use TodoWeb, :live_view
  alias TodoApp.LocalSettings
  alias TodoApp.Transcription.Server

  @impl true

  def mount(_args, _session, socket) do
    LocalSettings.subscribe()
    Server.subscribe()

    devices = TodoApp.Audio.list_devices()
    input_devices = Enum.filter(devices, &(&1.max_input_channels > 0))
    output_devices = Enum.filter(devices, &(&1.max_output_channels > 0))
    input_options = Enum.map(input_devices, &{&1.name, &1.id})
    output_options = Enum.map(output_devices, &{&1.name, &1.id})
    %{input: input, output: output} = LocalSettings.get_local_settings()

    {:ok,
     assign(socket,
       devices: devices,
       input_options: input_options,
       output_options: output_options,
       selected_input: input,
       selected_output: output,
       recording: false,
       pipeline_pid: nil,
       recordings: get_recordings()
     )}
  end

  @impl true
  def handle_event("select_input", %{"input" => input}, socket) do
    LocalSettings.update_local_settings(%{input: input})

    {:noreply, socket}
  end

  def handle_event("select_output", %{"output" => output}, socket) do
    LocalSettings.update_local_settings(%{output: output})

    {:noreply, socket}
  end

  def handle_event("record", %{"output" => output, "input" => input}, socket) do
    {now, _microseconds} = NaiveDateTime.utc_now() |> NaiveDateTime.to_gregorian_seconds()
    file_name = "#{now}.raw"
    path = Path.join(TodoApp.recordings_dir(), file_name)

    %{max_input_channels: output_channels, default_sample_rate: output_sample_rate} =
      socket.assigns.devices |> Enum.find(&(&1.id == output))

    %{max_input_channels: input_channels, default_sample_rate: input_sample_rate} =
      socket.assigns.devices |> Enum.find(&(&1.id == input))

    {:ok, _supervision_pid, pipeline_pid} =
      Membrane.Pipeline.start_link(TodoApp.Audio.RecordingPipeline,
        input_id: input,
        input_channels: input_channels,
        input_sample_rate: input_sample_rate,
        output_id: output,
        output_channels: output_channels,
        output_sample_rate: output_sample_rate,
        path: path
      )

    {:noreply,
     assign(socket,
       selected_output: output,
       pipeline_pid: pipeline_pid,
       recordings: [file_name | socket.assigns.recordings]
     )}
  end

  def handle_event("stop", _, %{assigns: %{pipeline_pid: pipeline_pid}} = socket) do
    Membrane.Pipeline.terminate(pipeline_pid)

    {:noreply, assign(socket, :pipeline_pid, nil)}
  end

  def handle_event("transcribe", %{"recording" => recording}, socket) do
    TodoApp.Transcription.Server.transcribe(recording)

    {:noreply, socket}
  end

  @impl true
  def handle_info(%LocalSettings{input: input, output: output}, socket) do
    {:noreply,
     assign(socket,
       selected_input: input,
       selected_output: output
     )}
  end

  def handle_info(:deleted, socket),
    do: {:noreply, assign(socket, :recordings, get_recordings())}

  def handle_info(:transcribed, %{assigns: %{recordings: [recording | _]}} = socket) do
    TodoApp.Transcription.Server.transcribe(recording)
    {:noreply, assign(socket, :recordings, get_recordings())}
  end

  def handle_info(:transcribed, %{assigns: %{recordings: []}} = socket) do
    {:noreply, assign(socket, :recordings, get_recordings())}
  end

  def notification_event(action) do
    Desktop.Window.show_notification(TodoWindow, "You did '#{inspect(action)}' me!",
      id: :click,
      type: :warning
    )
  end

  def get_recordings(), do: TodoApp.recordings_dir() |> File.ls!()
end
