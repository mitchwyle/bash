#!/usr/bin/env bash


gcloud compute instances list \
  --format='csv(cpuPlatform,id,creationTimestamp,name,zone,machineType,kind,networkInterfaces,scheduling,selfLink,tags)' \
  --flatten=u
