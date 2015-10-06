defmodule ExQueue.Server do
  use GenServer

  defmodule State do
    defstruct limit: 1, log: "", queue: [], running: [], done: [], cmds: %{}, data: %{}
  end

  @name {:global, :exqueue}

  # ---- client API

  def start_link do
    GenServer.start_link(__MODULE__, %State{}, name: @name)
  end

  # args can be a single atom, like :status, or a tuple, like {:q, cmd}, etc.
  def gscall(args) do
    GenServer.call(@name, args)
  end

  # ---- server (callbacks), one for each command

  def handle_call({:q, pwd, cmd}, _from, st) do
    {st, msg} = st
                |> _add_cmd_to_queue(pwd, cmd)
                |> _run_next_in_queue
    {:reply, msg, st}
  end

  def handle_call({:run, pwd, cmd}, _from, st) do
    {st, msg} = st
                |> _add_cmd_to_queue(pwd, cmd, :top)
                |> _run_next_in_queue(:run)
    {:reply, msg, st}
  end

  def handle_call({:limit, _pwd, new}, _from, st) do
    if String.match?(new, ~r/^\d+$/) do
      {st, msg} = st
                  |> struct(limit: String.to_integer(new))
                  |> _run_next_in_queue
                  # ideally, you should do all this in a new fun that sets the
                  # limit, then runs _run_next_in_queue as many times as
                  # needed to fill the queue, instead of adding just *one*
                  # task.  Ignored for now... I don't expect to be making the
                  # limit jump more than one step up.  (Workaround if needed:
                  # just run the same limit command multiple times!)
      {:reply, "ok\n" <> msg, st}
    else
      {:reply, "bad number", st}
    end
  end

  def handle_call({:history, _pwd}, _from, st) do
    msg = Enum.into(st.cmds, [], fn {p, c} -> "#{inspect p}\t\t#{c}" end) |> Enum.join("\n")
    {:reply, msg, st}
  end

  def handle_call({:status, _pwd}, _from, st) do
    msg = """
      LIMIT: #{st.limit}

      QUEUED:
      #{_print_list(st.queue)}
      RUNNING:
      #{_print_list(st.running)}
      DONE:
      #{_print_list(st.done)}
      LOG/MESSAGES:
      #{st.log}
      """
    # flush the log
    st = struct(st, log: "")
    {:reply, msg, st}
  end

  def handle_call({:peek, _pwd}, from, st) do
    handle_call({:peek, _pwd, "0"}, from, st)
  end
  def handle_call({:peek, _pwd, id}, _from, st) do
    {:reply, _show_data(st, st.running, id), st}
  end

  def handle_call({:print, _pwd}, from, st) do
    handle_call({:print, _pwd, "0"}, from, st)
  end
  def handle_call({:print, _pwd, id}, _from, st) do
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
      |> _warn("XQ SERVER: unexpected CAST message:")
      |> _warn(inspect(x))
    }
  end

  # :data and :exit_status are the two kinds of messages a port sends
  def handle_info({p, {:data, d}}, st) do
    {:noreply, _add_data(st, p, d)}
  end
  def handle_info({p, {:exit_status, es}}, st) do
    {:noreply, _done(st, p, es)}
  end

  def handle_info(x, st) do
    {:noreply, st
      |> _warn("XQ SERVER: unexpected INFO message:")
      |> _warn(inspect(x))
    }
  end

  # ---- queue handling functions

  # -------- return "state"

  defp _add_cmd_to_queue(st, pwd, cmd),       do: struct(st, queue: st.queue ++ [{pwd, cmd}])
  defp _add_cmd_to_queue(st, pwd, cmd, :top), do: struct(st, queue: [ {pwd, cmd} | st.queue ])

  # -------- return "state", "message"

  defp _run_next_in_queue(st, :run) do
    # save current limit, temp'ly raise it, get stuff done, then set it back
    l = st.limit
    {st, msg} = _run_next_in_queue( struct(st, limit: length(st.running)+1) )
    { struct(st, limit: l), msg }
  end

  defp _run_next_in_queue(st = %State{queue: []}) do
    {st, "ExQueue: queue is empty"}
  end
  defp _run_next_in_queue(st = %State{limit: l, running: r, queue: q}) when length(r) >= l do
    {st, "ExQueue: #{length(r)} jobs running (limit #{l}), #{length(q)} in queue"}
  end
  defp _run_next_in_queue(st = %State{queue: [h|t]}) do
    p = _port_open(h)
    st = struct(st,
      queue:   t,
      running: st.running ++ [ p ],
      cmds:    Map.put(st.cmds, p, elem(h, 0) <> "\n\t" <> _ts <> "\t" <> elem(h, 1)),
    )
    {st, "started #{inspect p}: #{inspect h}"}
  end

  # ---- service routines that touch the "state"

  # -------- return "state"

  defp _add_data(st, p, d) do
    struct(st,
      data: Map.put(st.data, p, Map.get(st.data, p, "") <> d)
    )
  end

  defp _done(st, p, es) do
    # todo: add a new field "failed" and update it if es != 0
    st
    |> _add_data(p, "EXIT_STATUS: #{es}")
    |> struct(
        running: st.running -- [p],
        done:    st.done ++ [p],
        cmds:    Map.update!(st.cmds, p, fn(x) -> x <> "\n\t" <> _ts <> "\t(#{es})" end)
      )
    |> _run_next_in_queue
    |> (fn({st, msg}) -> _warn(st, msg) end).()

  end

  defp _purge(st, id) do
    p = _id2p(st.done, id)
    struct(st,
      done: st.done -- [p],
      data: Map.delete(st.data, p),
    )
  end

  defp _warn(st, msg) do
    struct(st, log: st.log <> _ts <> ": " <> msg <> "\n")
  end

  # ---- service routines that don't touch the "state"

  defp _port_open({pwd, cmd}) do
    opts = ~w(stderr_to_stdout exit_status binary)a
    Port.open({:spawn_executable, System.get_env("SHELL")}, [{:cd, pwd}, {:args, ["-c", cmd]} | opts])
  end

  defp _print_list(l, into \\ "") do
    Enum.into(l, into, fn x -> inspect(x) <> "\n" end)
  end

  defp _show_data(st, list, id), do: _show_data(st, _id2p(list, id))

  defp _show_data(_st, nil), do: "(job number out of bounds)"
  defp _show_data(st, p),    do: """
    #{inspect p} #{Map.get(st.cmds, p, "IF THIS PRINTS, SOMETHING IS WRONG!")}
    #{Map.get(st.data, p, "(no output produced??)")}
    """

  # find id'th element in list to get the port (note: humans use 1-based indexing)
  defp _id2p(list, id), do: Enum.at(list, _numeric_id(id) - 1)

  defp _numeric_id(id) do
    if String.match?(id, ~r/^\d+$/) do
      String.to_integer(id)
    else
      0
    end
  end

  defp _ts(t \\ :os.timestamp) do
    { {_, _, d}, {h, m, s} } = :calendar.now_to_local_time(t)
    :io_lib.format("~2..0B.~2..0B:~2..0B:~2..0B", [d,h,m,s]) |> List.flatten |> to_string
  end

end
