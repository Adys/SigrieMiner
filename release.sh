#!/bin/bash
git show-ref -s --heads master > VERSION
git archive HEAD --output=+MMOC_Recorder.tar
tar --append --file=+MMOC_Recorder.tar VERSION
bzip2 +MMOC_Recorder.tar
cp +MMOC_Recorder.tar.bz2 VERSION /var/www/sigrie/sigrie/sigrie/static/addon/
rm +MMOC_Recorder.tar.bz2
