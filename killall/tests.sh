#
#function shkillall() {
#  local USAGE="Usage: $0 program"
#  # Verify we have exactly one parameter, the name of the program we want to kill:
#  case $# in
#   1) x=x ;;
#   *) echo "Wrong number of parameters." 
#      echo $USAGE 
#      exit 3 ;;
#  esac
#
#  $DBUG && set -x
#  ps aux | 
#  grep $1 |
#  grep -v grep |
#  awk '{ print $2 }' |
#  xargs kill 
#}
#

# Tests for the killall bash script

# Verify killall works for non-existent program.
function testnonexistent() {
  local DBUG=true
   $DBUG && set -x
  ./killall.sh nontexistantprogram
   $DBUG && echo "exit status: $?"
}

# Verify killall works for a single instance of a program



testnonexistent



