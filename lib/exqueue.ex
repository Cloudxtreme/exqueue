defmodule ExQueue do
  alias ExQueue.Server

  @common_commands  ~w(q status peek print)
  @other_commands   ~w(run limit purge errors history)
  @shortcuts        %{"pe" => "peek", "p" => "print", "e" => "errors", "h" => "history"}
  @valid_commands   @common_commands ++ @other_commands ++ Map.keys(@shortcuts)

  # ---- (main)
  def main([]),             do: (_one_line_help; main(["status"]))
  def main(["-h"]),         do: _usage
  def main(["help"]),       do: _usage

  # start the server
  def main(["serve"]) do
    {:ok, _ } = Node.start(_gen_server_node_name, :shortnames)
    {:ok, _ } = Server.start_link

    # this is pretty much the only output it produces; just helps us know it
    # managed to become distributed, if you're troubleshooting
    IO.inspect(Node.self)

    # thanks to Jose Valim for suggesting this as a substitute for "--no-halt"
    :timer.sleep(:infinity)
  end

  def main([cmd|args]) when cmd in @valid_commands do
    _connect
    _gscall(String.to_atom(_expand(cmd)), args)
    # args can be a single word (like 'status') or multiple (like 'q wget -c ...')
  end

  def main([cmd|args]) do # not a valid command; default is "q"
    main([ "q" , cmd | args])
  end

  # ---- (service routines)

  defp _cwd, do: File.cwd!

  defp _gscall(cmd, []) do
    Server.gscall({cmd, _cwd}) |> _safe_print
  end
  defp _gscall(cmd, args) do
    Server.gscall({cmd, _cwd, Enum.join(args, " ")}) |> _safe_print
  end

  defp _expand(cmd) do
    Map.get(@shortcuts, cmd, cmd)
  end

  defp _connect do
    # first we need to make *ourselves* distributed
    "xq#{System.get_pid}"
    |> String.to_atom
    |> Node.start(:shortnames)

    # *then* we try to connect.  The '2' is number of attempts
    _connect(2)

    :timer.sleep 250    # otherwise the next command fails (FIXME)
  end

  defp _connect(0) do
    IO.puts "unable to connect; giving up"
  end
  defp _connect(tries) do
    unless Node.connect(_gen_server_node_name(:qualified)) do
      mescript = :escript.script_name |> to_string
      System.cmd("bash", ["-c", "( ( #{mescript} serve &>/dev/null & ) )"])
      IO.puts :stderr, "server spawned"

      # give it some time!
      :timer.sleep 500

      # try again
      _connect(tries - 1)
    end
  end

  defp _gen_server_node_name(:qualified) do
    n = _gen_server_node_name |> to_string
    # (FIXME) we don't know how erlang determines the short hostname so we cheat
    h = Node.self |> to_string |> String.split("@") |> Enum.at(1)

    String.to_atom(n <> "@" <> h)
  end

  defp _gen_server_node_name do
    "xq_" <> System.get_env("USER") |> String.to_atom
  end

  defp _safe_print(x) do
    String.chunk(x, :printable)
    |> Enum.map(fn x ->
      if String.printable?(x) do
        IO.write x
      else
        IO.write inspect(x)
      end
    end)
    IO.write "\n";
  end

  # ---- (help and usage)
  defp _one_line_help, do: IO.puts "(please run with '-h' for help)"
  defp _usage do
    IO.puts """
    xq -- shell queue for batch commands

    This 'usage' message is only a memory-jogger; you need to read the README
    for an intro and more details.

    Common commands:
      #{Enum.join(@common_commands, ", ")}

    Shortcuts for common commands:
      #{(for {k,v} <- @shortcuts, do: "#{k}: #{v}") |> Enum.join(", ")}

    Other commands available:
      #{Enum.join(@other_commands, ", ")}

    """
  end
end

# ----
# Exargs.main System.argv
