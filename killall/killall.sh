#
# killall reimplementation of command in bash


# killall "program" -- Kill all processes with the name "program"
#

function shkillall() {
  local USAGE="Usage: $0 program"
  # Verify we have exactly one parameter, the name of the program we want to kill:
  case $# in
   1) x=x ;;
   *) echo "Wrong number of parameters." 
      echo $USAGE 
      exit 3 ;;
  esac

  $DBUG && set -x
  ps aux | 
  grep $1 |
  grep -v grep |
  awk '{ print $2 }' |
  xargs kill 
}


main() {
  shkillall $@
}

export DBUG=false
main $@
