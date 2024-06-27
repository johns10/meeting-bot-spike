#include <erl_nif.h>

#include <string>
#include <iostream>
#include <vector>

extern const std::string do_transcribe_files(std::vector<std::string> file_names);

static ERL_NIF_TERM transcribe_files(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[])
{
  if (argc != 1 || !enif_is_list(env, argv[0]))
  {
    return enif_make_badarg(env);
  }

  std::vector<std::string> file_names;
  ERL_NIF_TERM list = argv[0];
  ERL_NIF_TERM head, tail;

  while (enif_get_list_cell(env, list, &head, &tail))
  {
    ErlNifBinary file_name_bin;
    if (!enif_inspect_binary(env, head, &file_name_bin))
    {
      return enif_make_badarg(env);
    }

    std::string file_name((char *)file_name_bin.data, file_name_bin.size);
    file_names.push_back(file_name);

    list = tail;
  }

  const std::string response = do_transcribe_files(file_names);

  return enif_make_string(env, response.c_str(), ERL_NIF_LATIN1);
}

static ErlNifFunc nif_funcs[] = {{"transcribe_files", 1, transcribe_files}};

ERL_NIF_INIT(Elixir.TodoApp.Transcribe, nif_funcs, NULL, NULL, NULL, NULL)