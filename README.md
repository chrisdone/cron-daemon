# cron-daemon (Unix-like only)

Useful for:

* An easy way to make background services on Linux or OS X using cron,
  and make sure it stays running.
* An easy way to run a process and automatically restart it by
  re-running the same command (via `--terminate`).

## Example with cron

Using cron, run your program `foo` like this:

``` shell
* * * * * /path/to/cron-daemon \
   /path/to/foo \
   --pid /tmp/foo.pid \
   --log /tmp/foo.log \
   --stdout /tmp/foo.stdout.log \
   --stderr /tmp/foo.stderr.log \
   -e PORT=2018 \ # optional, to pass environment variables
   --pwd /opt/foo \
   -- some arguments # optional
```

All arguments are optional apart from the program itself. But these
arguments are good for making sure that within cron your program makes
sense.

The program will be started after one minute. Every minute, cron will
run `cron-daemon` which will check whether the process is running. If
it is, it does nothing. If not, it runs it and writes its process ID
to `foo.pid`.

Because it's cron, it will ensure the program is running regularly,
and also persist through system restarts or logout.

Output in `--log foo.log` looks like:

```
INFO: Process ID 43780 not running.
INFO: Launching /usr/local/bin/finance
INFO: Arguments: ["/Users/chris/Finance/statements/"]
INFO: Environment: [("PORT","2018")]
INFO: Successfully launched PID: 44861
```

# Using with stack

Run with `stack build --file-watch --exec` to re-run your service
whenever a file is changed, for a service `webshow` that I run as
`webshow -d /webshow`:

    stack build --fast --file-watch --exec 'cron-daemon --pid .stack-work/pid --terminate -- webshow -d /webshow'

We pop the arguments after `--`, and `--pid` in a place that's
probably ignored by git.

# Help text

Run `--help`:

    cron-daemon - Run a program as a daemon with cron

    Usage: cron-daemon PROGRAM [--pid FILEPATH] [--log FILEPATH] [--stderr FILEPATH]
                       [--stdout FILEPATH] [-e|--env NAME=value] [--pwd DIR]
                       [ARGUMENT] [--debug-log-env] [--terminate]
      Run a program as a daemon with cron

    Available options:
      PROGRAM                  Run this program
      --pid FILEPATH           Write the process ID to this file
      --log FILEPATH           Log file
      --stderr FILEPATH        Process stderr file
      --stdout FILEPATH        Process stdout file
      -e,--env NAME=value      Environment variable
      --pwd DIR                Working directory
      ARGUMENT                 Argument for the child process
      --debug-log-env          Log environment variables in log file (default:
                               false)
      --terminate              Terminate the process if it's already running (can be
                               used for restart/update of binary)
      -h,--help                Show this help text

# Building statically


Build the docker image

    docker image build . -t cron-daemon

Run the Haskell build

    docker run --rm -v "$(pwd):$(pwd)" -w "$(pwd)" cron-daemon stack build --allow-different-user --system-ghc --ghc-options="-O0 -static -optl-static"

Copy the binary listed at the end, e.g.

    $ ldd .stack-work/dist/x86_64-linux/Cabal-2.2.0.1/build/cron-daemon/cron-daemon
	not a dynamic executable
