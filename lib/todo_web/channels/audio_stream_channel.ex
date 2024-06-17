defmodule TodoWeb.AudioStreamChannel do
  use Phoenix.Channel

  def join("audio_channel:lobby", _message, socket) do
    {:ok, socket}
  end

  def handle_in("new_audio", %{"audio_data" => audio_data}, socket) do
    # Here, audio_data is base64 encoded. You might want to decode and process it if needed.
    broadcast!(socket, "new_audio", %{"audio_data" => audio_data})
    {:noreply, socket}
  end

  def handle_in("ping", _payload, socket) do
    push(socket, "pong", %{})
    {:noreply, socket}
  end

  def handle_info(:some_event, socket) do
    push(socket, "new_msg", %{"info" => "This is a test message"})
    {:noreply, socket}
  end

  def terminate(_reason, _socket) do
    :ok
  end
end
