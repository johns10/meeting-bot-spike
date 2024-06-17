defmodule TodoApp.Transcription.Server do
  use GenServer
  require Logger

  defstruct [:python_pid, :working?]
  @topic "transcription"

  def subscribe() do
    Phoenix.PubSub.subscribe(TodoApp.PubSub, @topic)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  def transcribe(file_name) do
    GenServer.cast(__MODULE__, {:transcribe, file_name})
  end

  def init(state) do
    path = [:code.priv_dir(:todo_app), "python"] |> Path.join()
    {:ok, pid} = :python.start([{:python_path, to_charlist(path)}, {:python, ~c"python3"}])
    :python.call(pid, :transcribe, :register_handler, [self()])
    {:ok, Map.put(state, :python_pid, pid)}
  end

  def handle_cast({:transcribe, _file_name}, %{working?: true} = state) do
    IO.puts("bloop")
    {:noreply, state}
  end

  def handle_cast({:transcribe, file_name}, %{python_pid: pid, working?: _} = state) do
    file_path = Path.join([TodoApp.recordings_dir(), file_name])

    case File.stat!(file_path) do
      %{size: size} when size < 10_000 ->
        File.rm!(file_path)
        Phoenix.PubSub.broadcast(TodoApp.PubSub, @topic, :deleted)
        {:noreply, state}

      _ ->
        :python.cast(pid, file_path)
        {:noreply, state |> Map.put(:working?, true)}
    end
  end

  def handle_cast(state, :stop) do
    Logger.error("Transcription server crashed")
    {:noreply, state}
  end

  def handle_info({file_path, results}, state) do
    Logger.info("Done Transcribing File")

    text_file_path =
      file_path
      |> to_string()
      |> String.replace(".raw", ".txt")
      |> String.replace("recordings", "transcripts")

    text =
      results
      |> to_string()
      |> Jason.decode!()
      |> Map.get("segments")
      |> Enum.reduce("", fn
        %{"speaker" => speaker, "text" => text}, acc ->
          acc <> "# #{speaker}\n\n#{text}\n\n"

        %{"text" => text}, acc ->
          acc <> "#{text}\n\n"
      end)

    File.write!(text_file_path, text)
    File.rm!(file_path)
    Phoenix.PubSub.broadcast(TodoApp.PubSub, @topic, :transcribed)

    {:noreply, state |> Map.put(:working?, false)}
  end

  def terminate(_reason, %{python_pid: pid}) do
    :python.stop(pid)
    nil
  end
end
