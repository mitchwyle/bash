#
# killall reimplementation of command in bash


# killall "program" -- Kill all processes with the name "program"
#

function shkillall() {
  local USAGE="Usage: $0 program"
  local program=""
  # Verify we have exactly one parameter, the name of the program we want to kill:
  case $# in
   1) x=x ;;
   *) echo "Wrong number of parameters." 
      echo $USAGE 
      exit 3 ;;
  esac
  program=$1

  $DBUG && set -x
    pidlist="$(
    ps aux | 
    grep $1 |
    grep -v grep |
    awk '{ print $2 }' )"
    $DBUG && echo "pidlist = $pidlist"
    case $pidlist"x" in
      x) echo "No instances of the program $program were running." ; exit 0 ;;
      *) x=x ;;
    esac
    kill $pidlist
}


main() {
  shkillall $@
}

export DBUG=false
main $@
