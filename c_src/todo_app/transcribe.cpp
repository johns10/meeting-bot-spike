#include "whisper.cpp/whisper.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <thread>
#include <sstream>

struct whisper_params
{
  int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());
  int32_t n_processors = 1;
  int32_t offset_t_ms = 0;
  int32_t offset_n = 0;
  int32_t duration_ms = 0;
  int32_t progress_step = 5;
  int32_t max_context = -1;
  int32_t max_len = 0;
  int32_t best_of = whisper_full_default_params(WHISPER_SAMPLING_GREEDY).greedy.best_of;
  int32_t beam_size = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH).beam_search.beam_size;
  int32_t audio_ctx = 0;

  float word_thold = 0.01f;
  float entropy_thold = 2.40f;
  float logprob_thold = -1.00f;
  float grammar_penalty = 100.0f;
  float temperature = 0.0f;
  float temperature_inc = 0.2f;

  bool debug_mode = false;
  bool translate = false;
  bool detect_language = false;
  bool diarize = false;
  bool tinydiarize = false;
  bool split_on_word = false;
  bool no_fallback = false;
  bool output_txt = false;
  bool output_vtt = false;
  bool output_srt = false;
  bool output_wts = false;
  bool output_csv = false;
  bool output_jsn = false;
  bool output_jsn_full = true;
  bool output_lrc = false;
  bool no_prints = false;
  bool print_special = false;
  bool print_colors = false;
  bool print_progress = false;
  bool no_timestamps = false;
  bool log_score = false;
  bool use_gpu = true;
  bool flash_attn = false;

  std::string language = "en";
  std::string prompt;
  std::string font_path = "/System/Library/Fonts/Supplemental/Courier New Bold.ttf";
  std::string model = "models/ggml-base.en.bin";
  std::string grammar;
  std::string grammar_rule;
  std::string tdrz_speaker_turn = " [SPEAKER_TURN]"; // TODO: set from command line
  std::string suppress_regex;
  std::string openvino_encode_device = "CPU";
  std::string dtw = "";

  std::vector<std::string> fname_inp = {};
  std::vector<std::string> fname_out = {};
};

static std::string to_timestamp(int64_t t, bool comma = false)
{
  int64_t msec = t * 10;
  int64_t hr = msec / (1000 * 60 * 60);
  msec = msec - hr * (1000 * 60 * 60);
  int64_t min = msec / (1000 * 60);
  msec = msec - min * (1000 * 60);
  int64_t sec = msec / 1000;
  msec = msec - sec * 1000;

  char buf[32];
  snprintf(buf, sizeof(buf), "%02d:%02d:%02d%s%03d", (int)hr, (int)min, (int)sec, comma ? "," : ".", (int)msec);

  return std::string(buf);
}

int timestamp_to_sample(int64_t t, int n_samples, int whisper_sample_rate)
{
  return std::max(0, std::min((int)n_samples - 1, (int)((t * whisper_sample_rate) / 100)));
}

char *escape_double_quotes_and_backslashes(const char *str)
{
  if (str == NULL)
  {
    return NULL;
  }

  size_t escaped_length = strlen(str) + 1;

  for (size_t i = 0; str[i] != '\0'; i++)
  {
    if (str[i] == '"' || str[i] == '\\')
    {
      escaped_length++;
    }
  }

  char *escaped = (char *)calloc(escaped_length, 1); // pre-zeroed
  if (escaped == NULL)
  {
    return NULL;
  }

  size_t pos = 0;
  for (size_t i = 0; str[i] != '\0'; i++)
  {
    if (str[i] == '"' || str[i] == '\\')
    {
      escaped[pos++] = '\\';
    }
    escaped[pos++] = str[i];
  }

  // no need to set zero due to calloc() being used prior

  return escaped;
}

bool output_json(
    struct whisper_context *ctx,
    std::ostringstream &out,
    const whisper_params &params,
    bool full)
{
  int indent = 0;

  auto doindent = [&]()
  {
    for (int i = 0; i < indent; i++)
      out << "\t";
  };

  auto start_arr = [&](const char *name)
  {
    doindent();
    out << "\"" << name << "\": [\n";
    indent++;
  };

  auto end_arr = [&](bool end)
  {
    indent--;
    doindent();
    out << (end ? "]\n" : "],\n");
  };

  auto start_obj = [&](const char *name)
  {
    doindent();
    if (name)
    {
      out << "\"" << name << "\": {\n";
    }
    else
    {
      out << "{\n";
    }
    indent++;
  };

  auto end_obj = [&](bool end)
  {
    indent--;
    doindent();
    out << (end ? "}\n" : "},\n");
  };

  auto start_value = [&](const char *name)
  {
    doindent();
    out << "\"" << name << "\": ";
  };

  auto value_s = [&](const char *name, const char *val, bool end)
  {
    start_value(name);
    char *val_escaped = escape_double_quotes_and_backslashes(val);
    out << "\"" << val_escaped << (end ? "\"\n" : "\",\n");
    free(val_escaped);
  };

  auto end_value = [&](bool end)
  {
    out << (end ? "\n" : ",\n");
  };

  auto value_i = [&](const char *name, const int64_t val, bool end)
  {
    start_value(name);
    out << val;
    end_value(end);
  };

  auto value_f = [&](const char *name, const float val, bool end)
  {
    start_value(name);
    out << val;
    end_value(end);
  };

  auto value_b = [&](const char *name, const bool val, bool end)
  {
    start_value(name);
    out << (val ? "true" : "false");
    end_value(end);
  };

  auto times_o = [&](int64_t t0, int64_t t1, bool end)
  {
    start_obj("timestamps");
    value_s("from", to_timestamp(t0, true).c_str(), false);
    value_s("to", to_timestamp(t1, true).c_str(), true);
    end_obj(false);
    start_obj("offsets");
    value_i("from", t0 * 10, false);
    value_i("to", t1 * 10, true);
    end_obj(end);
  };

  fprintf(stderr, "%s: writing output to stream\n", __func__);

  start_obj(nullptr);
  value_s("systeminfo", whisper_print_system_info(), false);
  start_obj("model");
  value_s("type", whisper_model_type_readable(ctx), false);
  value_b("multilingual", whisper_is_multilingual(ctx), false);
  value_i("vocab", whisper_model_n_vocab(ctx), false);
  start_obj("audio");
  value_i("ctx", whisper_model_n_audio_ctx(ctx), false);
  value_i("state", whisper_model_n_audio_state(ctx), false);
  value_i("head", whisper_model_n_audio_head(ctx), false);
  value_i("layer", whisper_model_n_audio_layer(ctx), true);
  end_obj(false);
  start_obj("text");
  value_i("ctx", whisper_model_n_text_ctx(ctx), false);
  value_i("state", whisper_model_n_text_state(ctx), false);
  value_i("head", whisper_model_n_text_head(ctx), false);
  value_i("layer", whisper_model_n_text_layer(ctx), true);
  end_obj(false);
  value_i("mels", whisper_model_n_mels(ctx), false);
  value_i("ftype", whisper_model_ftype(ctx), true);
  end_obj(false);
  start_obj("params");
  value_s("model", params.model.c_str(), false);
  value_s("language", params.language.c_str(), false);
  value_b("translate", params.translate, true);
  end_obj(false);
  start_obj("result");
  value_s("language", whisper_lang_str(whisper_full_lang_id(ctx)), true);
  end_obj(false);
  start_arr("transcription");

  const int n_segments = whisper_full_n_segments(ctx);
  for (int i = 0; i < n_segments; ++i)
  {
    const char *text = whisper_full_get_segment_text(ctx, i);

    const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
    const int64_t t1 = whisper_full_get_segment_t1(ctx, i);

    start_obj(nullptr);
    times_o(t0, t1, false);
    value_s("text", text, !params.diarize && !params.tinydiarize && !full);

    if (full)
    {
      start_arr("tokens");
      const int n = whisper_full_n_tokens(ctx, i);
      for (int j = 0; j < n; ++j)
      {
        auto token = whisper_full_get_token_data(ctx, i, j);
        start_obj(nullptr);
        value_s("text", whisper_token_to_str(ctx, token.id), false);
        if (token.t0 > -1 && token.t1 > -1)
        {
          // If we have per-token timestamps, write them out
          times_o(token.t0, token.t1, false);
        }
        value_i("id", token.id, false);
        value_f("p", token.p, false);
        value_f("t_dtw", token.t_dtw, true);
        end_obj(j == (n - 1));
      }
      end_arr(!params.diarize && !params.tinydiarize);
    }

    if (params.tinydiarize)
    {
      value_b("speaker_turn_next", whisper_full_get_segment_speaker_turn_next(ctx, i), true);
    }
    end_obj(i == (n_segments - 1));
  }

  end_arr(true);
  end_obj(true);
  return true;
}

bool is_file_exist(const std::string &filename)
{
  std::ifstream infile(filename);
  return infile.good();
}

bool read_pcm(const std::string &fname, std::vector<float> &pcmf32)
{
  std::ifstream infile(fname, std::ios::binary);
  if (!infile.is_open())
  {
    std::cerr << "error: failed to open '" << fname << "' as raw PCM file" << std::endl;
    return false;
  }

  // Read the raw PCM data
  infile.seekg(0, std::ios::end);
  size_t file_size = infile.tellg();
  infile.seekg(0, std::ios::beg);

  std::vector<uint8_t> buffer(file_size);
  infile.read(reinterpret_cast<char *>(buffer.data()), file_size);
  infile.close();

  if (file_size % 4 != 0)
  {
    std::cerr << "error: file size is not a multiple of 4 bytes, which is unexpected for 32-bit PCM data" << std::endl;
    return false;
  }

  size_t num_samples = file_size / 4;
  pcmf32.resize(num_samples);

  for (size_t i = 0; i < num_samples; ++i)
  {
    uint32_t sample = *reinterpret_cast<uint32_t *>(buffer.data() + i * 4);
    float normalized_sample = static_cast<int32_t>(sample) / 2147483648.0f; // Convert to float [-1.0, 1.0]
    pcmf32[i] = normalized_sample;
  }

  return true;
}

std::string do_transcribe_files(std::vector<std::string> file_names)
{
  whisper_params params;
  whisper_context *ctx = whisper_init_from_file_with_params(params.model.c_str(), whisper_context_default_params());

  if (ctx == nullptr)
  {
    throw std::runtime_error("Failed to initialize whisper context");
  }

  std::ostringstream results;

  for (const auto &fname_inp : file_names)
  {
    if (!is_file_exist(fname_inp))
    {
      results << "{\"file\": \"" << fname_inp << "\", \"error\": \"File not found\"},";
      continue;
    }

    std::vector<float> pcmf32; // mono-channel F32 PCM

    if (!read_pcm(fname_inp, pcmf32))
    {
      results << "{\"file\": \"" << fname_inp << "\", \"error\": \"Failed to read PCM file\"},";
      continue;
    }

    // Configure whisper parameters
    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.language = params.language.c_str();
    wparams.n_threads = params.n_threads;
    wparams.print_progress = false;

    if (whisper_full_parallel(ctx, wparams, pcmf32.data(), pcmf32.size(), params.n_processors) != 0)
    {
      results << "{\"file\": \"" << fname_inp << "\", \"error\": \"Failed to process audio\"},";
      continue;
    }

    // Collect transcription result in JSON format
    std::ostringstream json_stream;
    output_json(ctx, json_stream, params, params.output_jsn_full);
    results << json_stream.str() << ",";
  }

  // if (ctx)
  // {
  //   ggml_free(ctx->model.ctx);

  //   ggml_backend_buffer_free(ctx->model.buffer);

  //   whisper_free_state(ctx->state);

  //   delete ctx;
  // }

  std::string json_result = results.str();
  if (!json_result.empty() && json_result.back() == ',')
  {
    json_result.pop_back(); // Remove the trailing comma
  }

  json_result = "[" + json_result + "]";

  return json_result;
}