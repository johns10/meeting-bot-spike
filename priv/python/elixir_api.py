from transcribe import transcribe
from erlport.erlang import set_message_handler, cast
from erlport.erlterms import Atom

message_handler = None

def cast_message(pid, message):
    cast(pid, message)

def register_handler(pid):
    print("registering handler")
    global message_handler
    message_handler = pid

def handle_message(path):
    try:
        result = transcribe(path.decode("utf-8"))
        if message_handler:
           cast_message(message_handler, (path.decode("utf-8"), result))
    except Exception as e:
      print("Exception")
      print(e)
      pass

def erl_transcribe(file_path):
    transcribe(file_path.decode("utf-8"))

set_message_handler(handle_message)