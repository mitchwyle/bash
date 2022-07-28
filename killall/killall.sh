#
# killall bash function & unit tests



# Kill all processes with the name "program"
function shkillall() {
  local USAGE="killall program"
  # Verify we have exactly one parameter, the name of the program we want to kill:
  case $# in
   1) break ;;
   *) echo "Wrong number of arguments\n" 
      echo $USAGE 
      exit 3 ;;
  esac

  ps aux | 
  killall $1
  grep $1 |
  grep -v grep |
  awk '{ print $2 }'
  # xargs kill 
}


main() {
  local USAGE="$0 program"
  # Verify we have exactly one parameter, the name of the program we want to kill:
  case $# in
   1) break ;;
   *) echo "Wrong number of arguments\n" 
      echo $USAGE 
      exit 3 ;;
  esac

  shkillall 
  
}
