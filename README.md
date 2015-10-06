# ExQueue -- shell command execution queue

`exqueue` is a command to manage an "execution queue" -- a queue of pending
shell commands to execute.  It will run one job at a time.  `exqueue` is best
for batch programs where the output is small-ish (`wget --progress=dot:mega`
for example); **it cannot be used for programs which require user input**.

I've aliased it to `xq` so many of the examples will use that.  I recommend
you do too; `exqueue` is too long even with completion, especially because I
ex-pect to have many more ex-tremely useful commands starting with "ex" ;-)

The main features are: add commands to queue, check queue/running/finished job
status, peek at output of running program(s), print output of finished
programs, and forcibly run a job even if something else is already running.
The decision to allow at most one job at a time stems from the expectation
that this will mostly be used for IO-bound jobs (downloads, backups and other
file system level tasks, git commands, etc.)  If you need more parallelism,
try [exargs](https://github.com/sitaramc/exargs).

# TL;DR / Intro

    # generic example
    xq some-command some-args

    # wget example
    xq wget --progress=dot:mega http://files.gitminutes.com/episodes/37.mp3

    # or if you want to use exargs (see http://github.com/sitaramc/exargs) to
    # queue up 4 downloads one after the other.  If nothing else is running,
    # this will start downloading 37.mp3 and queue the rest.
    xa -1 "xq wget --progress=dot:mega http://files.gitminutes.com/episodes/%.mp3" {37..40}

    # status
    xq              # or, 'xq status'; see 'xq -h' for commands and shortcuts

    # peek at the in-progress output of the currently running command
    xq pe           # or, 'xq peek'

    # print the output of the *last* completed command
    xq p            # or, 'xq print'

# Commands

The following sub-commands can be used:

*   `q`: queue up a command.  If nothing else is running, the command starts
    immediately.  This is the default if you directly give a shell command
    (i.e., if you supply some arguments but they are not one of the recognised
    'exqueue' sub-commands).

*   `status`: check status.  This is the default command if you run just `xq`,
    with absolutely no arguments.  The output looks somewhat like this (yeah
    it's ugly; I'm waiting for some inspiration there!):

        limit:    1
        queued:
        "/tmp/sseq 1 12"
        "/tmp/sseq 1 13"
        "/tmp/sseq 1 14"

        running:
        #Port<0.2254>

        done:
        #Port<0.2138>
        #Port<0.2249>

        log/messages:
        2015-09-02.21:48:38: started #Port<0.2249>: /tmp/sseq 1 11
        2015-09-02.21:48:49: ExQueue: 1 jobs running (limit 1), 3 in queue

*   `pe` or `peek` at the output of the currently running command.

*   `p` or `print`: print the output of the **last** finished command, and
    delete its output from memory.

    In the example `status` output above, `print` will show you the output of
    job 2249, then delete it from the status.  A subsequent `print` will then
    show you job 2138 (unless the currently running job (2254) finishes before
    then!)

    If you want to see the output of jobs other than the last one in the list,
    use `xq p 1` for the first one, `xq p 2` for the second, etc.

*   `run`: forcibly run a command even if something else is already running.
    Essentially bypasses the "one job at a time" limit.  Note that jobs
    already in the queue *will* still wait till nothing else is running before
    they can start (i.e., both the original job *and* the queue-jumper must
    finish before the next job in the queue is picked up).

*   `limit`: change the limit.  If the new limit is greater than the number of
    jobs currently running, the next job in the queue is started.  Running
    jobs are not killed if you reduce the limit.  If you set it to zero, the
    queue is effectively blocked, even if running jobs complete.

*   Check the `history` of commands.  When you `print` the output of a job,
    the output is deleted from memory, but the command name, start and end
    times, and exit status, are kept forever.  (Well... until you kill the
    server anyway; we're not using any persistent storage for anything).

    Note that the *end* time and exit status are printed first, due to some
    laziness on my part!

# Quoting, special filenames, etc.

*   If you're using special filenames, you may have to quote them twice:

        xq q "wc 'filename with spaces'"

    I tend to not care too much about files like that anyway, so unless lots
    of people want to use this and ask, that's where it stays.

*   If you're using **zsh**, you may get some weird errors:

        xq q "wget http://www.example.com/download?file"
        zsh:1: no matches found: http://www.example.com/download?file

    If that happens, try

        xq q "noglob wget http://www.example.com/download?file"

    (This is a zsh thing; happens all the time and is nothing to do with `xq`)

# Other notes

*   Stderr is mixed in with stdout.  This is not going to change.  If you need
    to separate them, use redirection in the command you're passing off to
    `exqueue`, then examine the output file yourself.

*   You can `peek` as many times as you wish.  It does not act like `tail -f`;
    it acts like `cat` -- each time you peek, you get **all** the output that
    the program produced so far.

*   If you run programs with **HUGE** amounts of output, it's best (from a
    memory utilisation point of view) to redirect the output.  So this

        xq q "some-command --huge-output > command.out"

    is good, while this

        xq q "some-command --huge-output"

    may not be.  `exqueue` is a long running program, and I have no idea
    if/how/when Erlang chooses to give that memory back to the OS.

