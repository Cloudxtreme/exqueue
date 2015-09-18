# we assume 'mix escript.build' is done.  The 'pwd' test also assumes that the
# command 'xq' is uptodate.  And finally, we don't start the "serve"r.  That
# has to be done manually before running 'mix test'.

defmodule ExQueueTest do
  use ExUnit.Case

  test "basics and pwd" do
    # including that 'p' shows the output of the *last completed* command (not
    # the first started!)

    cwd = File.cwd!

    o1 = :os.cmd('./exqueue pwd') |> to_string
    assert String.match?(o1, ~r(^started #Port<[0-9.]+>: {"#{cwd}", "pwd"}))

    o1 = :os.cmd('cd /tmp; xq q pwd') |> to_string
    assert String.match?(o1, ~r(^started #Port<[0-9.]+>: {"/tmp", "pwd"}))

    :timer.sleep 100

    o1 = :os.cmd('cd /tmp; xq p') |> to_string
    assert String.match?(o1, ~r(^/tmp$)m)

    o1 = :os.cmd('xq p') |> to_string
    assert String.match?(o1, ~r(^#{cwd}$)m)
  end

end
