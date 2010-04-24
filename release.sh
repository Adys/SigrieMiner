#!/bin/bash
git show-ref -s --heads master > VERSION
cp MMOC_Recorder.toc *.lua VERSION /var/www/sigrie/sigrie/sigrie/static/addon/
