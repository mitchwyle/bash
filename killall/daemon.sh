
set -x

# launch a background daemon
./sleep300.sh &
pid=$!  #process identifier number

OS="$(uname -a)"  # this operating system

echo OS = $OS
echo pid = $pid

case $OS in
  *Darwin*) lsappinfo setinfo $pid --name "testprogram" ;;
  *) echo "testprogram" > /proc/$pid/comm ;;
esac

sleep 130 # give time to examine what is going on
kill $pid # kill the background daemon
