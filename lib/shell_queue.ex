defmodule ShellQueue do
  alias ShellQueue.Server

  @common_commands  ~w(q status peek print)
  @other_commands   ~w(run purge history)
  @shortcuts        %{"st" => "status", "pe" => "peek", "p" => "print"}
  @valid_commands   @common_commands ++ @other_commands ++ Map.keys(@shortcuts)

  # ---- (main)
  def main([]),             do: _usage
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
    _gscall(String.to_atom(_expand(cmd)), args, _get_server_pid)
    # args can be a single word (like 'status') or multiple (like 'q wget -c ...')
  end

  # ---- (service routines)

  defp _gscall(cmd, [], pid) do
    Server.gscall(pid, cmd) |> _safe_print
  end
  defp _gscall(cmd, args, pid) do
    Server.gscall(pid, {cmd, Enum.join(args, " ")}) |> _safe_print
  end

  defp _expand(cmd) do
    Map.get(@shortcuts, cmd, cmd)
  end

  defp _get_server_pid do
    # first we need to make *ourselves* distributed
    "sq#{System.get_pid}"
    |> String.to_atom
    |> Node.start(:shortnames)

    unless Node.connect(_gen_server_node_name(:qualified)) do
      IO.puts :stderr, "FATAL: #{inspect self} #{Node.self} could not connect to #{_gen_server_node_name(:qualified)}"
      System.halt(1)
    end
    :timer.sleep 250    # otherwise the next command fails (FIXME)
    :global.whereis_name :shellqueue
  end

  defp _gen_server_node_name(:qualified) do
    n = _gen_server_node_name |> to_string
    # (FIXME) we don't know how erlang determines the short hostname so we cheat
    h = Node.self |> to_string |> String.split("@") |> Enum.at(1)

    String.to_atom(n <> "@" <> h)
  end

  defp _gen_server_node_name do
    "sq_" <> System.get_env("USER") |> String.to_atom
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

  # ---- (usage)
  defp _usage do
    IO.puts """
    sq -- shell queue for batch commands

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
