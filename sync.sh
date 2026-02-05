#!/usr/bin/env sh

rsync -avzP . myt@192.168.178.38:/home/myt/CultLtd --exclude ./trace.spall
