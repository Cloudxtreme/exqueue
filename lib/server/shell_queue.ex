defmodule ShellQueue.Server do
  use GenServer

  defmodule State do
    defstruct limit: 1, log: "", queue: [], running: [], done: [], cmds: %{}, data: %{}
  end

  @name {:global, :shellqueue}

  # ---- client API

  def start_link do
    GenServer.start_link(__MODULE__, %State{}, name: @name)
  end

  # args can be a single atom, like :status, or a tuple, like {:run, cmd}, etc.
  def gscall(pid, args) do
    GenServer.call(pid, args)
  end

  # ---- server (callbacks)

  def handle_call({:run, cmd}, _from, st) do
    {st, msg} = st
                |> _add_cmd_to_queue(cmd)
                |> _run_next_in_queue

    {:reply, msg, st}
  end

  def handle_call(:history, _from, st) do
    msg = Enum.into(st.cmds, [], fn {p, c} -> "#{inspect p} #{c}" end) |> Enum.join("\n")
    {:reply, msg, st}
  end

  def handle_call(:status, _from, st) do
    msg = """
      limit:    #{st.limit}
      queued:
      #{_print_list(st.queue)}
      running:
      #{_print_list(st.running)}
      done:
      #{_print_list(st.done)}
      log/messages:
      #{st.log}
      """
    # todo: number and indent the job listing
    st = struct(st, log: "")
    {:reply, msg, st}
  end

  def handle_call(:peek, from, st) do
    handle_call({:peek, "0"}, from, st)
  end
  def handle_call({:peek, id}, _from, st) do
    {:reply, _show_data(st, st.running, id), st}
  end

  def handle_call(:print, from, st) do
    handle_call({:print, "0"}, from, st)
  end
  def handle_call({:print, id}, _from, st) do
    { :reply, _show_data(st, st.done, id), _purge(st, id) }
  end

  def handle_call(x, _from, st) do
    {:reply, """
      Say what?  I can't grok this:
      #{inspect(x)}
      """,
      st
    }
  end

  def handle_cast(x, st) do
    {:noreply, st
      |> _warn("SQ SERVER: unexpected CAST message:")
      |> _warn(inspect(x))
    }
  end

  def handle_info({p, {:data, d}}, st) do
    {:noreply, _add_data(st, p, d)}
  end

  def handle_info({p, {:exit_status, es}}, st) do
    {:noreply, _done(st, p, es)}
  end

  def handle_info(x, st) do
    {:noreply, st
      |> _warn("SQ SERVER: unexpected INFO message:")
      |> _warn(inspect(x))
    }
  end

  # ---- private functions

  defp _add_cmd_to_queue(st, cmd) do
    struct(st,
      queue: st.queue ++ [cmd]
    )
  end

  defp _run_next_in_queue(st = %State{queue: []}) do
    {st, "ShellQueue: queue is empty"}
  end
  defp _run_next_in_queue(st = %State{limit: l, running: r, queue: q}) when length(r) >= l do
    {st, "ShellQueue: #{length(r)} jobs running (limit #{l}), #{length(q)} in queue"}
  end
  defp _run_next_in_queue(st = %State{queue: [h|t]}) do
    p = _port_open(h)
    st = struct(st,
      queue: t,
      running: st.running ++ [ p ],
      cmds: Map.put(st.cmds, p, _ts <> " " <> h),
    )
    {st, "started #{inspect p}: #{h}"}
  end

  # ---- service routines

  defp _port_open(cmd) do
    opts = ~w(stderr_to_stdout exit_status binary)a     # todo: cd
    Port.open({:spawn_executable, System.get_env("SHELL")}, [{:args, ["-c", cmd]} | opts])
  end

  defp _print_list(l, into \\ "") do
    Enum.into(l, into, fn x -> inspect(x) <> "\n" end)
  end

  defp _add_data(st, p, d) do
    struct(st,
      data: Map.put(st.data, p, Map.get(st.data, p, "") <> d)
    )
  end

  defp _done(st, p, es) do
    # todo: add a new field "failed" and update it if es != 0
    st
    |> _add_data(p, "EXIT_STATUS: #{es}\n")
    |> struct(
        running: st.running -- [p],
        done: st.done ++ [p]
      )
    |> _run_next_in_queue
    |> (fn({st, msg}) -> _warn(st, msg) end).()

  end

  defp _show_data(st, list, id) do
    p = _id2p(list, id)

    """
    #{inspect p} #{Map.get(st.cmds, p, "index out of bounds")}
    #{Map.get(st.data, p, "index out of bounds")}
    """
  end

  defp _id2p(list, id) do
    # find id'th element in list to get the port
    Enum.at(list, _numeric_id(id) - 1)   # humans use 1-based indexes!
  end

  defp _numeric_id(id) do
    if String.match?(id, ~r/^\d+$/) do
      String.to_integer(id)
    else
      0
    end
  end

  defp _purge(st, id) do
    p = _id2p(st.done, id)
    struct(st,
      done: st.done -- [p],
      # cmds: Map.delete(st.cmds, p),
      data: Map.delete(st.data, p),
    )
  end

  defp _warn(st, msg) do
    struct(st, log: st.log <> _ts <> ": " <> msg <> "\n")
  end

  defp _ts(t \\ :os.timestamp) do
    { {y, mo, d}, {h, m, s} } = :calendar.now_to_local_time(t)
    :io_lib.format("~4B-~2..0B-~2..0B.~2..0B:~2..0B:~2..0B", [y,mo,d,h,m,s]) |> List.flatten |> to_string
  end

end
