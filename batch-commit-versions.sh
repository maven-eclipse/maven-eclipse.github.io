#!/bin/bash
set -e

#get all the version numbers, reasonably safe to assume this isn't disappearing
cd maven/org/eclipse/swt/org.eclipse.swt.gtk.linux.x86_64
VERSIONS=$( ls -d */ | rev | cut -c 2- | rev | sort -t. -n -k1,1 -k2,2 -k3,3 -k4,4 )

cd ..
for VERSION in $VERSIONS
do
	echo "Version $VERSION"
	for PLATFORM in `ls`
	do
		cd $PLATFORM
		if [ -d "$VERSION" ]
		then
			git add $VERSION
		fi;
		cd ..
	done;
	git commit -m "Added SWT $VERSION jars"
done;