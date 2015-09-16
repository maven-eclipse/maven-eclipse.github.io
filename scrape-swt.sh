#!/bin/bash
#set -e
# Instead of a very complicated java based downloader, 
# use basic bash to parse the raw HTML for download links, sort, extract, and install SWT
#
# Its best to run each stage individually like:
# bash -c "source scrape-swt.sh; set -e; stage_4_install"
#
# TODO: Somehow ignore maven versions we already have. 
# Until then source this script and run each stage manually
# Remove existing releases from tmp/urls.txt after stage_1_scrape

# Eclipse Mirror
# MUST HAVE DIRECTORY LISTING ENABLED
#MIRROR=http://mirror.cc.vt.edu/pub/eclipse/eclipse/downloads/
if true
then
	echo "Recent release mode"
	MIRROR=http://download.eclipse.org/eclipse/downloads/
	HASH_EXT=".sha512"
	HASH_CMD="sha512sum"
	DROPS_DIR="drops4"
else
	echo "Archive release mode"
	MIRROR=http://archive.eclipse.org/eclipse/downloads/
	HASH_EXT=".sha1"
	HASH_CMD="sha1sum"
	DROPS_DIR="drops4" #todo
fi

REPO=$PWD/maven
#DOWNLOAD_CMD="wget -i"
DOWNLOAD_CMD="aria2c -i"

stage_0_init() {
	rm -rf tmp downloads
}

stage_1_scrape_releases() {
	for CUR_RELEASE in "$@";
	do
		# for loop over above
		# 1) Get HTML of specific release index (follow redirects)
		# 2) Get all SWT urls. As this also matches the filename (which might be cut off), get the ending ">
		# 3) Cut off the ending "> (apparently 3 is needed for a hidden character)
		#TODO: SWT specific
		RELEASE_FILE=$( basename $CUR_RELEASE ).html
		URL=$MIRROR$CUR_RELEASE/
		echo "Dumping $URL"
		curl -L $URL > $RELEASE_FILE
		DIST_FILES=$( cat $RELEASE_FILE | grep -E -o 'swt-[a-zA-Z0-9\._-]+\">' | grep -v "sha1\|md5\|sha512" | rev | cut -c 3- | rev | sort | uniq )

		for CUR_FILE in $DIST_FILES;
		do
			echo $MIRROR/$CUR_RELEASE/$CUR_FILE >> urls.txt
			CHECKSUM_FILE=$CUR_FILE$HASH_EXT
			echo $MIRROR/$CUR_RELEASE/checksum/$CHECKSUM_FILE >> urls.txt
		done;
	done;
}

stage_1_scrape() {
	mkdir -p tmp
	cd tmp
	# 1) Get HTML of root (follow redirects)
	# 2) Ghetto match all urls in the common drops4 dir
	# 3) Only care about releases and milestones
	# 4) Filter out duplicates
	curl -L $MIRROR > index.html
	RELEASES=$( cat index.html | grep -E -o "$DROPS_DIR/[a-zA-Z0-9\.-]+" | grep -E "^$DROPS_DIR/[R]-" | sort | uniq )

	stage_1_scrape_releases $RELEASES
	cd ..
}

stage_2_download() {
	mkdir -p downloads
	cd downloads
	$DOWNLOAD_CMD ../tmp/urls.txt
	$HASH_CMD --check *$HASH_EXT
	cd ..
}

stage_3_extract() {
	cd downloads
	for VERSION in `ls *.zip | cut -d '-' -f 2  | sort | uniq`; do
		mkdir $VERSION
		cd $VERSION
		for FILE_TO_EXTRACT in `ls ../swt-$VERSION-*.zip`; do
			FILE_BASE=`basename $FILE_TO_EXTRACT .zip`
			unzip $FILE_TO_EXTRACT "swt.jar"
			mv "swt.jar" $FILE_BASE.jar
			if [[ $FILE_TO_EXTRACT == *"wce"* ]]
			then
				#special wce handling on 4.2 and 4.2.1
				mkdir wcetmp
				unzip $FILE_TO_EXTRACT "*.dll" -d wcetmp
				mv wcetmp/* $FILE_BASE.dll
				rm -rf wcetmp

				unzip $FILE_TO_EXTRACT "swtsrc.zip"
				mv "swtsrc.zip" $FILE_BASE.jar.src
			else
				unzip $FILE_TO_EXTRACT "swt-debug.jar"
				mv "swt-debug.jar" $FILE_BASE.jar.debug
				unzip $FILE_TO_EXTRACT "src.zip"
				mv "src.zip" $FILE_BASE.jar.src
			fi;
		done;
		cd ..
	done;
	cd ..
}

stage_4_install() {
	cd downloads
	#Special version sort to account for 4.2 < 4.2.1
	for VERSION in `ls -d */ | sort -t. -n -k1,1 -k2,2 -k3,3 -k4,4 | rev | cut -c 2- | rev`; do
		cd $VERSION
		for JAR_MAIN in `ls *.jar`; do 
			BASE=`basename $JAR_MAIN .jar`
			ARTIFACT_ID=org.eclipse.swt.`echo ${BASE#swt-$VERSION-} | sed -r -e 's/\-/\./g'`
			echo "Version $VERSION | Main $JAR_MAIN | Id $ARTIFACT_ID"
			if [[ $ARTIFACT_ID == *"wce"* ]]
			then
				SUFFIX="-Dfiles=$BASE.dll \
				-Dclassifiers=dll \
				-Dtypes=dll"
			else
				SUFFIX="-Dfiles=$JAR_MAIN.debug \
				-Dclassifiers=debug \
				-Dtypes=jar"
			fi;

			mvn deploy:deploy-file \
				-DgroupId=org.eclipse.swt \
				-DartifactId=$ARTIFACT_ID \
				-Dversion=$VERSION \
				-Durl=file:///$REPO \
				-Dfile=$JAR_MAIN \
				-Dsources=$JAR_MAIN.src \
				-DupdateReleaseInfo=true \
				$SUFFIX
		done;
		cd ..
	done;
	cd ..
}

if [ "$0" = "$BASH_SOURCE" ]; then
	echo "Being executed, running all stages"
	stage_0_init
	stage_1_scrape
	stage_2_download
	stage_3_extract
	stage_4_install
fi

