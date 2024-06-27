defmodule TodoApp.Transcribe do
  @on_load :init

  def init do
    :filename.join(:code.priv_dir(:todo_app), ~c"nif")
    |> :erlang.load_nif(0)
  end

  def transcribe_files(_file_paths) do
    exit(:nif_library_not_loaded)
  end
end
