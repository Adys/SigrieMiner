#!/bin/bash
git pull
git show-ref -s --heads master > VERSION
cp +MMOC_Recorder.toc *.lua VERSION /var/www/sigrie/sigrie/sigrie/static/addon/
sed -i 's/DEBUG_LEVEL = 4/DEBUG_LEVEL = 1/m' MMOC_Recorder.lua