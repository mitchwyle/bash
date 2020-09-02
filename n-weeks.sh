#!/usr/local/bin/bash

# execute a command only if today is modulo N days from START

export DBUG=true

export START="06/29/2020 00:00:00"

export SECS
export START_SECS=$(date "+%s" -d "$START")

$DBUG && echo $START
$DBUG && echo $START_SECS


# set interval (in weeks)
INTERVAL=3

# get week of year
WEEK=$(/bin/date +%V)

# run command if WEEK is divisible by INTERVAL
if [ $(( $WEEK % $INTERVAL )) -eq 0 ]; then
  # WEEK is divisible by INTERVAL

  # execute command ...
  echo $WEEK
else 
  echo This week $WEEK is not divisible by $INTERVAL
fi
