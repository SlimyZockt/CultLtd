#!/usr/bin/env sh


while inotifywait -r ./* --exclude "trace.spall"; do
    rsync -avz --exclude "trace.spall" -e "ssh  -i /home/myt/.ssh/myt" . myt@192.168.178.38:/home/myt/CultLtd
done
