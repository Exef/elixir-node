defmodule Memory do
  use Bitwise

  def load(address, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    prev_saved_value = Map.get(memory, memory_index, 0)
    next_saved_value = Map.get(memory, memory_index + 32, 0)

    <<_::size(bit_position), prev::binary>> = <<prev_saved_value::256>>
    <<next::size(bit_position), _::binary>> = <<next_saved_value::256>>

    value_binary = prev <> <<next::size(bit_position)>>

    memory1 = update_memory_size(address + 32, memory)
    {binary_word_to_integer(value_binary), State.set_memory(memory1, state)}
  end

  def store(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)
    remaining_bits = 256 - bit_position

    <<prev_bits::size(remaining_bits), next_bits::binary>> = <<value::256>>

    prev_saved_value = Map.get(memory, memory_index, 0)

    new_prev_value =
      write_part(
        bit_position,
        <<prev_bits::size(remaining_bits)>>,
        remaining_bits,
        <<prev_saved_value::256>>
      )

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_prev_value))

    memory2 =
      if rem(address, 32) != 0 do
        next_saved_value = Map.get(memory, memory_index + 32, 0)
        new_next_value = write_part(0, next_bits, bit_position, <<next_saved_value::256>>)
        Map.put(memory1, memory_index + 32, binary_word_to_integer(new_next_value))
      else
        memory1
      end

    memory3 = update_memory_size(address + 32, memory2)
    State.set_memory(memory3, state)
  end

  def store8(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    saved_value = Map.get(memory, memory_index, 0)

    new_value = write_part(bit_position, <<value::size(8)>>, 8, <<saved_value::256>>)

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_value))

    memory2 = update_memory_size(address + 8, memory1)
    State.set_memory(memory2, state)
  end

  def memory_size_words(state) do
    memory = State.memory(state)
    Map.get(memory, :size)
  end

  def memory_size_bytes(state) do
    memory_size_words = memory_size_words(state)
    memory_size_words * 32
  end

  def get_area(from, bytes, state) do
    memory = State.memory(state)
    memory_indexes = trunc(Float.ceil((from + bytes) / 32))
    start_index = trunc(Float.ceil(from / 32))

    total_data =
      Enum.reduce(0..(memory_indexes - 1), <<>>, fn i, data_acc ->
        data = Map.get(memory, (start_index + i) * 32, 0)
        data_acc <> <<data::size(256)>>
      end)

    unneeded_bits = rem(from, 32) * 8
    area_bits = bytes * 8
    <<_::size(unneeded_bits), area::size(area_bits), _::binary>> = total_data

    memory1 = update_memory_size(from + bytes, memory)
    {<<area::size(area_bits)>>, State.set_memory(memory1, state)}
  end

  def write_area(from, bytes, state) do
    memory = State.memory(state)

    {memory_index, bit_position} = get_index_in_memory(from)
    memory1 = write(bytes, bit_position, memory_index, memory)

    memory2 = update_memory_size(from + byte_size(bytes), memory1)
    State.set_memory(memory2, state)
  end

  defp write(<<>>, _byte_position, _memory_index, memory) do
    memory
  end

  defp write(bytes, bit_position, memory_index, memory) do
    memory_index_bits_left =
      if bit_position == 0 do
        256
      else
        256 - bit_position
      end

    size_bits = byte_size(bytes) * 8

    bits_to_write =
      if memory_index_bits_left <= size_bits do
        memory_index_bits_left
      else
        size_bits
      end

    saved_value = Map.get(memory, memory_index, 0)

    <<new_bytes::size(bits_to_write), bytes_left::binary>> = bytes

    new_value_binary =
      write_part(
        bit_position,
        <<new_bytes::size(bits_to_write)>>,
        bits_to_write,
        <<saved_value::256>>
      )

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_value_binary))

    write(bytes_left, 0, memory_index + 32, memory1)
  end

  defp get_index_in_memory(address) do
    memory_index = trunc(Float.floor(address / 32) * 32)
    bit_position = rem(address, 32) * 8

    {memory_index, bit_position}
  end

  defp write_part(bit_position, value_binary, size_bits, chunk_binary) do
    <<prev::size(bit_position), _::size(size_bits), next::binary>> = chunk_binary
    <<prev::size(bit_position)>> <> value_binary <> next
  end

  defp binary_word_to_integer(word) do
    <<word_integer::size(256), _::binary>> = word

    word_integer
  end

  defp update_memory_size(address, memory) do
    {memory_index, _} = get_index_in_memory(address)
    current_mem_size_words = Map.get(memory, :size)

    if memory_index / 32 > current_mem_size_words do
      Map.put(memory, :size, round(memory_index / 32))
    else
      memory
    end
  end
end