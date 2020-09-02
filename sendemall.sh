#!/usr/bin/env bash

# Send email to a list, one message at a time
# requires a mail transport such as postfix, e.g. sudo apt-get install postscript
#

export MSGFILE=tm 	# file containing message including From, Subject

die() {		  	# helper function
  echo $1
  exit 1
}

main() {
  [ -f $1 ] || die "WTF: No list of addresses, exiting."
  cat $1 | 
  while read addr ; do
    echo "To: $addr"",mwyle@ebay.com" | cat - $MSGFILE | /usr/sbin/sendmail -oi -t
    echo "sending $MSGFILE to $addr . . ."
  done
}

main $1

