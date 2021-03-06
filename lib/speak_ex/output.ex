defmodule SpeakEx.Output do
  alias SpeakEx.CallController, as: Api
  alias SpeakEx.Output.Swift

  require Logger

  def render(call, phrase, opts \\ [])
  def render(call, phrase, opts) do
    {timeout, digits} =
      if Keyword.get opts, :interrupt, :false do
        {1, '#'}
      else
        {Keyword.get(opts, :timeout, nil), Keyword.get(opts, :digits, nil)}
      end

    voice =  Keyword.get opts, :voice, nil

    num_digits = if digits, do: 1, else: Keyword.get(opts, :num_digits, nil)

    case Application.get_env(:speak_ex, :renderer, :asterisk) do
      :asterisk ->
        asterisk_stream_file(call, phrase, timeout, digits, voice)
      :swift ->
        case phrase do
          'file://' ++ filename ->
            asterisk_stream_file(call, filename, timeout, digits, voice)
          _ ->
            swift_stream_file(call, phrase, timeout, num_digits, voice)
        end
      other ->
        throw "Unknown speak_ex renderer #{other}"
    end
  end

  defp swift_stream_file(call, [phrase | _] = list, timeout, digits, voice)
    when not is_integer(phrase) do

    text =
      Enum.reduce(list, "", fn(item, acc) ->
        separator = if acc == "", do: "", else: Swift.ssml[:break][:sentence]
        acc <> separator <> "#{item}"
      end)
      |> String.to_charlist

    swift_stream_file(call, text, timeout, digits, voice)
  end

  defp swift_stream_file(call, phrase, timeout, digits, voice) when is_binary(phrase),
    do: swift_stream_file(call, String.to_charlist(phrase), timeout, digits, voice)

  defp swift_stream_file(call, phrase, timeout, digits, voice) when is_binary(voice),
    do: swift_stream_file(call, phrase, timeout, digits, String.to_charlist(voice))

  defp swift_stream_file(call, phrase, timeout, digits, voice) when is_binary(digits),
    do: swift_stream_file(call, phrase, timeout, String.to_charlist(digits), voice)

  defp swift_stream_file(call, phrase, timeout, digits, voice) do
    append = unless is_nil(digits) do
      timeout = if timeout, do: timeout, else: 2000
      String.to_charlist "|#{timeout}|#{digits}"
    else
      ''
    end

    prepend = unless is_nil(voice), do: '#{voice}^', else: ''
    text = prepend ++ phrase ++ append

    result =
      call
      |> Api.swift_send(text)
      |> SpeakEx.AgiResult.new

    if append != '' do
      case Api.get_variable(call, 'SWIFT_DTMF') do
        '' ->
          %SpeakEx.AgiResult{result | timeout: true}
        resp when is_list(resp) ->
          data = List.to_string resp
          %SpeakEx.AgiResult{result | timeout: false, data: data}
        other ->
          %SpeakEx.AgiResult{result | result: other, timeout: true}
      end
    else
      call
    end
  end

  defp asterisk_stream_file(call, prompt, _timeout, digits, voice) do

    if voice, do: raise("voice not valid for asterisk")

    args = if digits, do: [digits], else: []

    Api.stream_file(call, [prompt | args])
  end

end
