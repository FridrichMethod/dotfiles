#!/usr/bin/env perl
# tests/e2e/timeout.pl LIMIT COMMAND [ARG...]: GNU timeout's contract for the
# end-to-end harness on a machine that has neither timeout nor gtimeout (the
# macos-15 runner), which still always has perl. COMMAND runs in a process
# group of its own; when LIMIT seconds pass, the group gets TERM, then KILL
# two seconds later, and this exits 124, as `timeout` does. Otherwise it
# exits with COMMAND's status, 128+N when signal N ended it, and 127 when
# COMMAND cannot be run. tests/e2e/lib/common.sh picks it in
# e2e_find_timeout; tests/e2e-harness.sh tests it.
use strict;
use warnings;
use POSIX ();

my $limit = shift @ARGV;
if (!defined $limit || $limit !~ /\A[0-9]+\z/ || !@ARGV) {
    print STDERR "usage: timeout.pl SECONDS COMMAND [ARG...]\n";
    exit 125;
}

my $pid = fork;
if (!defined $pid) {
    print STDERR "timeout.pl: fork failed: $!\n";
    exit 125;
}
if ($pid == 0) {
    setpgrp(0, 0);
    exec { $ARGV[0] } @ARGV or do {
        print STDERR "timeout.pl: cannot run $ARGV[0]: $!\n";
        POSIX::_exit(127);
    };
}
# Both sides set the group, so a limit that fires at once still finds it.
setpgrp($pid, $pid);

my $timed_out = 0;
local $SIG{ALRM} = sub {
    $timed_out = 1;
    kill 'TERM', -$pid;
    sleep 2;
    kill 'KILL', -$pid;
};
alarm $limit;
my $waited;
do { $waited = waitpid($pid, 0) } while ($waited == -1 && $!{EINTR});
my $status = $?;
alarm 0;
exit 124 if $timed_out;
exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
