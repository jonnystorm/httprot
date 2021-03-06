#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.

defmodule HTTProt.Headers do
  defstruct list: []

  alias __MODULE__, as: H
  alias HTTProt.Cookie

  use Dict

  def new do
    %H{}
  end

  def parse(string) when string |> is_binary do
    for line <- string |> String.split(~r/\r?\n/), line != "" do
      [name, value] = line |> String.split(~r/\s*:\s*/, parts: 2)

      { name, value }
    end |> parse
  end

  def parse(enum) do
    Enum.reduce(enum, %{}, fn { name, value }, headers ->
      name = to_string(name)
      key  = String.downcase(name)

      Dict.update headers, key, { name, from_string(key, value) }, fn
        { name, old } when old |> is_list ->
          { name, old ++ from_string(key, value) }

        { name, old } ->
          case from_string(key, value) do
            value when value |> is_list ->
              { name, [old | value] }

            value ->
              { name, value }
          end
      end
    end) |> Enum.into(new, fn { _, { name, value } } ->
      { name, value }
    end)
  end

  def fetch(self, name) do
    name = name |> to_string
    key  = String.downcase(name)

    case self.list |> List.keyfind(key, 0) do
      { _, _, value } ->
        { :ok, value }

      nil ->
        :error
    end
  end

  def put(self, name, value) do
    name = name |> to_string
    key  = String.downcase(name)

    if value |> is_binary do
      value = from_string(key, value)
    end

    %H{self | list: self.list |> List.keystore(key, 0, { key, name, value })}
  end

  def delete(self, name) do
    name = name |> to_string
    key  = String.downcase(name)

    %H{self | list: self.list |> List.keydelete(key, 0)}
  end

  def size(self) do
    self.list |> length
  end

  def to_iodata(self) do
    for { name, value } <- self, into: [] do
      [name, ": ", to_string(String.downcase(name), value), "\r\n"]
    end
  end

  defp to_string("accept", value) when value |> is_list do
    for { name, quality } <- value do
      if quality == 1.0 do
        name
      else
        "#{name};q=#{quality}"
      end
    end |> Enum.join ","
  end

  defp to_string("content-length", value) do
    value |> to_string
  end

  defp to_string("cookie", value) do
    Enum.map(value, &URI.encode_query([{ &1.name, &1.value }]))
      |> Enum.join("; ")
  end

  defp to_string(_, value) when value |> is_list do
    Enum.join value, ", "
  end

  defp to_string(_, value) when value |> is_binary do
    value
  end

  defp from_string("accept", value) do
    for part <- value |> String.split(~r/\s*,\s*/) do
      case part |> String.split(~r/\s*;\s*/) do
        [type] ->
          { type, 1.0 }

        [type, "q=" <> quality] ->
          { type, Float.parse(quality) |> elem(0) }
      end
    end
  end

  defp from_string("cache-control", value) do
    value |> String.split(~r/\s*,\s*/)
  end

  defp from_string("content-length", value) do
    String.to_integer(value)
  end

  defp from_string("cookie", value) do
    for cookie <- value |> String.split(~r/\s*;\s*/) do
      [name, value] = String.split(cookie, ~r/=/, parts: 2)

      %Cookie{name: name, value: value}
    end
  end

  defp from_string(_, value) do
    value
  end

  @doc false
  def reduce(%H{list: list}, acc, fun) do
    reduce(list, acc, fun)
  end

  def reduce(_list, { :halt, acc }, _fun) do
    { :halted, acc }
  end

  def reduce(list, { :suspend, acc }, fun) do
    { :suspended, acc, &reduce(list, &1, fun) }
  end

  def reduce([], { :cont, acc }, _fun) do
    { :done, acc }
  end

  def reduce([{ _key, name, value } | rest], { :cont, acc }, fun) do
    reduce(rest, fun.({ name, value }, acc), fun)
  end

  defimpl String.Chars do
    def to_string(self) do
      H.to_iodata(self) |> IO.iodata_to_binary
    end
  end

  defimpl Access do
    def get(headers, key) do
      Dict.get(headers, key)
    end

    def get_and_update(table, key, fun) do
      { get, update } = fun.(Dict.get(table, key))
      { get, Dict.put(table, key, update) }
    end
  end

  defimpl Enumerable do
    def reduce(headers, acc, fun) do
      H.reduce(headers, acc, fun)
    end

    def member?(headers, { key, value }) do
      { :ok, match?({ :ok, ^value }, H.fetch(headers, key)) }
    end

    def member?(_, _) do
      { :ok, false }
    end

    def count(headers) do
      { :ok, H.size(headers) }
    end
  end

  defimpl Collectable do
    def empty(_) do
      H.new
    end

    def into(original) do
      { original, fn
          headers, { :cont, { k, v } } ->
            headers |> Dict.put(k, v)

          headers, :done ->
            headers

          _, :halt ->
            :ok
      end }
    end
  end
end
