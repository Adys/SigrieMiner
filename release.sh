#!/bin/bash
echo $(git show-ref --head HEAD | awk '{print $1}') > VERSION
git archive HEAD -o +MMOC_Recorder.tar
tar --append --file=+MMOC_Recorder.tar VERSION
bzip2 +MMOC_Recorder.tar
mv +MMOC_Recorder.tar.bz2 VERSION /var/www/sigrie/sigrie/sigrie/static/addon/