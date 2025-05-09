#! /bin/bash
#

# find all files still containing TMPL_ codes
FILES=$(grep -ril tmpl_ html/)

for output in $FILES
do
	input=$(echo $output | sed 's@^html/@tmpl/@g')
	perl convert.pl $input $output
done


