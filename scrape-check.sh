#!/bin/bash
# This script will scrape the Eclipse downloads page for releases that we do not have already
# If there are no new releases it will return 0
# If there are new releases it will return 1, get urls with "cat urls.txt". Then stage_2_download can be run
#
# Optionally will read scrape-check-existing.txt for additional releases to ignore, used to keep this repo and the release repo in sync
#
# This is best used as a cronjob that will email you when there are new releases
set -e
# MIRROR=http://download.eclipse.org/eclipse/downloads/
source scrape-swt.sh

#build expected releases
# EXISTING_RELEASES=( 4.5.1RC2 )
EXISTING_RELEASES=()
rootDir=`pwd`
cd maven/org/eclipse/swt/org.eclipse.swt.gtk.linux.x86_64
for i in `ls -d */ | rev | cut -c 2- | rev`; do
	EXISTING_RELEASES+=($i)
done
cd $rootDir

OTHER_EXISTING_RELEASES_FILE="scrape-check-existing.txt"
if [[ -f "$OTHER_EXISTING_RELEASES_FILE" ]]; then
	echo "Found $OTHER_EXISTING_RELEASES_FILE, adding to existing releases"
	while IFS='' read -r line || [[ -n "$line" ]]; do
		EXISTING_RELEASES+=($line)
	done < "$OTHER_EXISTING_RELEASES_FILE"
fi

echo "Existing releases: ${EXISTING_RELEASES[@]}"

stage_0_init
mkdir -p tmp
cd tmp

curl -L $MIRROR > index.html
#R is ignored because its for releases
RELEASES=$( cat index.html | grep -E -o "$DROPS_DIR/[a-zA-Z0-9\.-]+" | grep -E "^$DROPS_DIR/[SRM]-" | sort | uniq )

#build list of paths that contain 
NEW_RELEASES=()
for curReleasePath in $RELEASES; do
	curReleaseVersion=$( echo $curReleasePath | cut -d'/' -f2 | cut -d'-' -f2 )	
	
	#temporary workaround as 3.x releases aren't yet in the repo
	if [[ "$curReleaseVersion" == 3* ]]; then
		echo "Skipping release $curReleaseVersion"
		continue;
	fi

	#slow bash array contains
	found=false
	for curExpectedRelease in "${EXISTING_RELEASES[@]}"; do
		# echo "$curReleaseVersion is $curExpectedRelease"
		if [[ "$curReleaseVersion" = "$curExpectedRelease" ]]; then
			found=true
			break;
		fi
	done

	if ! $found; then
		# echo $curReleasePath
		NEW_RELEASES+=($curReleasePath)
	fi
done

echo "==Finished parsing paths=="
if [[ ${#NEW_RELEASES[@]} -eq 0 ]]; then
	echo "No new releases found, exiting"
	exit 0
fi

for i in "${NEW_RELEASES[@]}"; do
	echo "New release $i"
done

stage_1_scrape_releases "${NEW_RELEASES[@]}"

exit 1