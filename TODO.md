- Forward console to stderr in serial bridge host
- Disable dmesg while printing results to serial bridge host
- eventually, capture dmesg and associate with test
- send serial bridge host a "im done" message when we've run all the tests
- capture ctrl-c and make it print any received tests. is this necessary? don't we just print them as we receive them? idk. Maybe we want to print them all at the end of execution anyway just for visual clarity when not redirecting to a file?
- obvious colored log message in stderr output when a test starts/finishes would be neat
- make the tests not print out the json when run with an env var