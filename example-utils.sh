#!/usr/bin/env bash
#===============================================================================
#
#          FILE:  utils-functions.sh
#         USAGE:  example-utils.sh
#   DESCRIPTION:  a small collection of reusable bash functions that are helpful for scripting
#		  not intended to be . sourced or loaded, but copy-pasted and changed for 
#		  each script.  This script is an example of using the utils.
# 
#        AUTHOR:  Mitch Wyle (mfw), mwyle@ebay.com
#       COMPANY:  eBay Inc.
#       VERSION:  0.0.2
#       CREATED:  10/16/2014 02:22:46 PM PDT
#      MODIFIED:  11/05/2014 10:30:00 AM PDT
#     COPYRIGHT:  Author disclaims copyright; instead, here is a blessing:
#
#		  May you do good and not evil.
#		  May you find forgiveness for yourself and forgive others.
#		  May you share freely, never taking more than you give.
#
#===============================================================================

# It is often a good idea to put this block near the top of your script file:
# Must run under bash!   Bash-specific commands used.
if [ ! "$BASH_VERSION" ] ; then
  exec /bin/bash "$0" "$@"
fi

export LOCKFILE=/var/tmp/LOCK-MyScript-LOCK  	# mutual exclusion lock file
trap '/bin/rm -rf $LOCKFILE' 0                  # clean up on exit (including all trappable abnormal terminations)

## Functions for logging, die, try
#
log () {	# useful wrapper if your script may use multilog or syslog but may not always
  echo "$1"
}
#
die() {
  local o ; o=$* ;
  log "FATAL $o" ;
  exit 1;
}
#
try() {
  "$@"
  local EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then
    local FILE ; FILE=$(readlink -m "${BASH_SOURCE[1]}")
    local LINE ; LINE=${BASH_LINENO[0]}
    log "WARN $FILE: line $LINE: Command \`$*' failed with exit code $EXIT_CODE."
  fi
  return $EXIT_CODE
}
#
mutex () {			# this variation uses flock(1) (most reliable)
  exec 9>$LOCKFILE
  if ! flock -n 9  ; then
    log "WARN process $pid has the mutex lock"
    return 1
  fi
  # we now have the lock until 9 is closed (it will be closed automatically when we exit)
}
#
# example calling sequence:
# LOCKFILE=/var/tmp/myscriptname.sh
# mutex || {
#   echo "$(date) $0 already running.  Exiting. " >> $LOGFILE
#   echo "$0 already running. Exiting." >&2; exit 1;
# }


# An alternative, less-reliable version of mutex:
#
# mutual exclusion (mutex) to verify we are the only version of ourself running.
# File Descriptor 9 on a lock file whose name is passed in to this function
# Return 1 if someone else has the lock; return 0 if we have exclusive lock.
# See: http://go/shmutex
mutex () {
  local file=$1 pid pids                  # file containing process id (pid) of processes accessing it
  exec 9>>"$file"                         # file descripers 2, 9 find all processes currently accessing lock
  { pids=$(fuser -f "$file"); } 2>&- 9>&- # gather pids of all processes accessing lock file using fuser(1)
  for pid in $pids; do                    # loop through all PIDs
    [[ "$pid" = "$$" ]] && continue           # ignore our own PID
    exec 9>&-                             # Someone else has the lock file
    return 1                              # return error code
  done
}
#
# example calling sequence:
# LOCKFILE=/var/tmp/LOCK-myscriptname-LOCK
# mutex $LOCKFILE || {
#   echo "$(date) $0 already running.  Exiting. " >> $LOGFILE
#   echo "$0 already running. Exiting." >&2; exit 1;
# }


# For Solaris, we need to retreat to the least reliable /bin/sh method:
#
export LOCKFILE=/var/tmp/LOCK-myscriptname-LOCK
trap '/bin/rm -rf $LOCKFILE' 0      # clean up on exit (including all trappable abnormal terminations)
mutex() {
  echo "INFO Trying to get lock $LOCKFILE..."
   mkdir $LOCKFILE  || {
    log "WARN Failed to acquire lock!  mkdir returned $?"
    exit 1
  }
}
#
# example calling sequence:
# mutex || {
#   echo "$(date) $0 already running.  Exiting. " >> $LOGFILE
#   echo "$0 already running. Exiting." >&2; exit 1;
# }


####################################################
#
# Example use of multilog from a bash script:
#
main () {
  export i ;
  for i in {000..300} ; do
    echo "DEBUG hello world"
  done
}
(echo "INFO  $0 starting" ; main 2>&1 ; echo "INFO $0 completed." 2>&1) |
multilog t s15000000 n20 /var/tmp/spool_synchronize_tfs_files
#
# Multilog Options and their meaning:
#       t                                               # prepend time stamp
#       s15000000 n20                                   # 15 MB files, max 20 of them, rotate before writing
#       '!tai64nlocal'                                  # translate from "attoseconds since the big bang" to to human readable
#       /var/tmp/myscriptname		                # write to this directory
