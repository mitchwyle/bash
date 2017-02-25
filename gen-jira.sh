#!/usr/bin/env bash

# create individual tasks in each vertical for drone work
# factor out the data in a file for each parameter of the yetibot script
# s=summary, v=vertical, a=assignee, d=description

 while read s v a d ; do
  echo "!jira create $s -j NAPP -c $v -a $a -d $d"
done

!jira create "Mitch is testing jira command in yetibot   please resolve and close this issue " -j NAPP -c "V-Identity" -a mwyle -d "This is the description"




