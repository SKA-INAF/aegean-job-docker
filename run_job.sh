#!/bin/bash

#######################################
##         CHECK ARGS
#######################################
NARGS="$#"
echo "INFO: NARGS= $NARGS"

if [ "$NARGS" -lt 1 ]; then
	echo "ERROR: Invalid number of arguments...see script usage!"
  echo ""
	echo "**************************"
  echo "***     USAGE          ***"
	echo "**************************"
 	echo "$0 [ARGS]"
	echo ""
	echo "=========================="
	echo "==    ARGUMENT LIST     =="
	echo "=========================="
	echo "*** MANDATORY ARGS ***"
	echo "--image=[FILENAME] - Input FITS file"
	echo ""

	echo "*** OPTIONAL ARGS ***"

	echo "=== AEGEAN OPTIONS ==="
	echo "--bkg-gridsize=[GRID_SIZE] - The [x,y] size of the grid to use [Default = ~4* beam size square]"
	echo "--bkg-boxsize=[BOX_SIZE] - The [x,y] size of the box over which the rms/bkg is calculated [Default = 5*grid]"
	echo "--seedthr=[SEED_THR] - The clipping value (in sigmas) for seeding islands [default: 5]"
	echo "--mergethr=[MERGE_THR] - The clipping value (in sigmas) for growing islands [default: 4]"
	echo "--fit-maxcomponents=[NCOMP] - If more than *maxsummits* summits are detected in an island, no fitting is done, only estimation"
	echo ""

	echo "=== RUN OPTIONS ==="
	echo "--runuser=[RUNUSER] - Username to be used when running script (default=cutex)"
	echo "--change-runuser=[VALUE] - Change username when running script (0/1) (default=1)"
	echo "--ncores=[NCORES] - Number of cores to use [Default = all available]"
	echo "--jobdir=[PATH] - Directory where to run job (default=/home/[RUNUSER]/aegean-job)"
	echo "--joboutdir=[PATH] - Directory where to place output products (same of rundir if empty) (default=empty)"

	echo ""
	echo "=== VOLUME MOUNT OPTIONS ==="
	echo "--rclone-copy-wait=[COPY_WAIT_TIME] - Time to wait after copying output files (default=30)"
	
	echo ""
	 	

	echo "=========================="
  exit 1
fi

##########################
##    PARSE ARGS
##########################
RUNUSER="aegean"
CHANGE_USER=true
JOB_DIR=""
JOB_OUTDIR=""
#JOB_ARGS=""

# - AEGEAN OPTIONS
NCORES="1"
INPUT_IMAGE=""
#BKG_BOX_SIZE="5"
#BKG_GRID_SIZE="4"
BKG_BOX_SIZE=""
BKG_GRID_SIZE=""
FIT_MAX_COMPONENTS="5"
SEED_THR="5"
MERGE_THR="4"
SAVE_SUMMARY_PLOT=false
SAVE_BKG_MAPS=false

# - RCLONE OPTIONS
MOUNT_RCLONE_VOLUME=0
MOUNT_VOLUME_PATH="/mnt/storage"
RCLONE_REMOTE_STORAGE="neanias-nextcloud"
RCLONE_REMOTE_STORAGE_PATH="."
RCLONE_MOUNT_WAIT_TIME=10
RCLONE_COPY_WAIT_TIME=30

echo "ARGS: $@"

for item in "$@"
do
	case $item in
		
		--image=*)
    	INPUT_IMAGE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--bkg-boxsize=*)
    	BKG_BOX_SIZE=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--bkg-gridsize=*)
    	BKG_GRID_SIZE=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--seedthr=*)
    	SEED_THR=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--mergethr=*)
    	MERGE_THR=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--fit-maxcomponents=*)
    	FIT_MAX_COMPONENTS=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--save-summaryplot*)
    	SAVE_SUMMARY_PLOT=true
    ;;
		--save-bkgmaps*)
    	SAVE_BKG_MAPS=true
    ;;
		--runuser=*)
    	RUNUSER=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--change-runuser=*)
    	CHANGE_USER_FLAG=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
			if [ "$CHANGE_USER_FLAG" = "1" ] ; then
				CHANGE_USER=true
			else
				CHANGE_USER=false
			fi
    ;;
		--jobdir=*)
    	JOB_DIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--joboutdir=*)
    	JOB_OUTDIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
#		--jobargs=*)
#    	JOB_ARGS=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
#    ;;
		--ncores=*)
      NCORES=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;		
		--mount-rclone-volume=*)
    	MOUNT_RCLONE_VOLUME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--mount-volume-path=*)
    	MOUNT_VOLUME_PATH=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-remote-storage=*)
    	RCLONE_REMOTE_STORAGE=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-remote-storage-path=*)
    	RCLONE_REMOTE_STORAGE_PATH=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-mount-wait=*)
    	RCLONE_MOUNT_WAIT_TIME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--rclone-copy-wait=*)
    	RCLONE_COPY_WAIT_TIME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;

	*)
    # Unknown option
    echo "ERROR: Unknown option ($item)...exit!"
    exit 1
    ;;
	esac
done


# - Check job args
if [ "$INPUT_IMAGE" = "" ]; then
	echo "ERROR: Empty INPUT_IMAGE argument (hint: you must specify image at least)!"
	exit 1
fi

#if [ "$JOB_ARGS" = "" ]; then
#	echo "ERROR: Empty JOB_ARGS argument (hint: you must specify image at least)!"
#	exit 1
#fi


###############################
##    MOUNT VOLUMES
###############################
if [ "$MOUNT_RCLONE_VOLUME" = "1" ] ; then

	# - Create mount directory if not existing
	echo "INFO: Creating mount directory $MOUNT_VOLUME_PATH ..."
	mkdir -p $MOUNT_VOLUME_PATH	

	# - Get device ID of standard dir, for example $HOME
	#   To be compared with mount point to check if mount is ready
	DEVICE_ID=`stat "$HOME" -c %d`
	echo "INFO: Standard device id @ $HOME: $DEVICE_ID"

	# - Mount rclone volume in background
	uid=`id -u $RUNUSER`

	echo "INFO: Mounting rclone volume at path $MOUNT_VOLUME_PATH for uid/gid=$uid ..."
	MOUNT_CMD="/usr/bin/rclone mount --daemon --uid=$uid --gid=$uid --umask 000 --allow-other --file-perms 0777 --dir-cache-time 0m5s --vfs-cache-mode full $RCLONE_REMOTE_STORAGE:$RCLONE_REMOTE_STORAGE_PATH $MOUNT_VOLUME_PATH -vvv"
	eval $MOUNT_CMD

	# - Wait until filesystem is ready
	echo "INFO: Sleeping $RCLONE_MOUNT_WAIT_TIME seconds and then check if mount is ready..."
	sleep $RCLONE_MOUNT_WAIT_TIME

	# - Get device ID of mount point
	MOUNT_DEVICE_ID=`stat "$MOUNT_VOLUME_PATH" -c %d`
	echo "INFO: MOUNT_DEVICE_ID=$MOUNT_DEVICE_ID"
	if [ "$MOUNT_DEVICE_ID" = "$DEVICE_ID" ] ; then
 		echo "ERROR: Failed to mount rclone storage at $MOUNT_VOLUME_PATH within $RCLONE_MOUNT_WAIT_TIME seconds, exit!"
		exit 1
	fi

	# - Print mount dir content
	echo "INFO: Mounted rclone storage at $MOUNT_VOLUME_PATH with success (MOUNT_DEVICE_ID: $MOUNT_DEVICE_ID)..."
	ls -ltr $MOUNT_VOLUME_PATH

	# - Create job & data directories
	echo "INFO: Creating job & data directories ..."
	mkdir -p $MOUNT_VOLUME_PATH/jobs
	mkdir -p $MOUNT_VOLUME_PATH/data

	# - Create job output directory
	#echo "INFO: Creating job output directory $JOB_OUTDIR ..."
	#mkdir -p $JOB_OUTDIR

fi


###############################
##    SET OPTIONS
###############################
# - Set job dir
if [ "$JOB_DIR" == "" ]; then
	if [ "$CHANGE_USER" = true ]; then
		JOB_DIR="/home/$RUNUSER/aegean-job"
	else
		JOB_DIR="$HOME/aegean-job"
	fi
fi

# - Extract base filename
filename_base=$(basename "$INPUT_IMAGE")
file_extension="${filename_base##*.}"
filename_base_noext="${filename_base%.*}"

# - Set RMS & background map filenames
rms_file="$filename_base_noext"'_rms.fits'
bkg_file="$filename_base_noext"'_bkg.fits'
	
# - Set catalog filename
catalog_file="catalog-$filename_base_noext"'.dat'
catalog_tab_file="catalog-$filename_base_noext"'.tab'

# - Set DS9 region filename
ds9_file="ds9-$filename_base_noext"'.reg'
ds9_isle_file="ds9-$filename_base_noext"'_isle.reg'
ds9_comp_file="ds9-$filename_base_noext"'_comp.reg'


# - Set logfile
logfile="output_$filename_base_noext"'.log'

# - Define summary output plot filename
summary_plot_file="plot_$filename_base_noext"'.png'

###############################
##    RUN AEGEAN JOB
###############################
# - Enter job dir
echo "INFO: Entering job dir $JOB_DIR ..."
cd $JOB_DIR

# - Run BANE
EXE="BANE"
BKG_GRID_OPTS=""
if [ "$BKG_GRID_SIZE" != "" ]; then
	BKG_GRID_OPTS="--grid=$BKG_GRID_SIZE $BKG_GRID_SIZE "
fi
BKG_BOX_OPTS=""
if [ "$BKG_BOX_SIZE" != "" ]; then
	BKG_BOX_OPTS="--box=$BKG_BOX_SIZE $BKG_BOX_SIZE "
fi
BKG_OPTS="--cores=$NCORES $BKG_GRID_OPTS $BKG_BOX_OPTS "

ARGS="$BKG_OPTS $filename_base"

if [ "$CHANGE_USER" = true ]; then
	CMD="runuser -l $RUNUSER -g $RUNUSER -c '""$EXE $ARGS""'"
else
	CMD="$EXE $ARGS"
fi

echo "INFO: Computing background & noise maps (CMD=$CMD) ..."
eval "$CMD"
BANE_STATUS=$?

if [ "$BANE_STATUS" != "0" ]; then
	echo "ERROR: BANE failed with code=$BANE_STATUS ..."	
	exit 1
fi

echo " "

# - Run source finder
EXE="aegean"
ARGS="--find --cores=$NCORES --noise=$rms_file --background=$bkg_file --maxsummits=$FIT_MAX_COMPONENTS --seedclip=$SEED_THR --floodclip=$MERGE_THR --island --out=$catalog_file --table=$ds9_file,$catalog_tab_file $filename_base"
if [ "$CHANGE_USER" = true ]; then
	CMD="runuser -l $RUNUSER -g $RUNUSER -c '""$EXE $ARGS""'"
else
	CMD="$EXE $ARGS"
fi

echo "INFO: Extracting sources (CMD=$CMD) ..."
eval "$CMD"
JOB_STATUS=$?

# - Clear data
if [ $SAVE_BKG_MAPS = false ]; then
	if [ -e $JOB_DIR/$bkg_file ] ; then	
		echo "INFO: Removing bkg map file $bkg_file ..."
		rm $JOB_DIR/$bkg_file
	fi
	if [ -e $JOB_DIR/$rms_file ] ; then	
		echo "INFO: Removing rms map file $rms_file ..."
		rm $JOB_DIR/$rms_file
	fi
fi

# - Check status
if [ "$JOB_STATUS" != "0" ]; then
	echo "ERROR: Aegean failed with code=$JOB_STATUS ..."
	exit 1
fi

# - Make summary plot
if [ $SAVE_SUMMARY_PLOT = true ]; then
	if [ -e $JOB_DIR/$ds9_comp_file ] ; then	
		echo "INFO: Making summary plot with input image + extracted source islands ..."
		draw_img.py --img=$filename_base --region=$ds9_comp_file --wcs --zmin=0 --zmax=0 --cmap=gray_r --contrast=0.3 --save --outfile=$summary_plot_file
	fi
fi

# - Copy output data to output directory
if [ "$JOB_DIR" != "$JOB_OUTDIR" ]; then
	echo "INFO: Copying job outputs in $JOB_OUTDIR ..."
	ls -ltr $JOB_DIR

	# - Copy output plot(s)
	png_count=`ls -1 *.png 2>/dev/null | wc -l`
  if [ $png_count != 0 ] ; then
		echo "INFO: Copying output plot file(s) to $JOB_OUTDIR ..."
		cp *.png $JOB_OUTDIR
	fi

	# - Copy output jsons
	json_count=`ls -1 *.json 2>/dev/null | wc -l`
	if [ $json_count != 0 ] ; then
		echo "INFO: Copying output json file(s) to $JOB_OUTDIR ..."
		cp *.json $JOB_OUTDIR
	fi

	# - Copy output tables
	tab_count=`ls -1 *.tab 2>/dev/null | wc -l`
	if [ $tab_count != 0 ] ; then
		echo "INFO: Copying output table file(s) to $JOB_OUTDIR ..."
		cp *.tab $JOB_OUTDIR
	fi

	# - Copy output regions
	reg_count=`ls -1 *.reg 2>/dev/null | wc -l`
	if [ $reg_count != 0 ] ; then
		echo "INFO: Copying output region file(s) to $JOB_OUTDIR ..."
		cp *.reg $JOB_OUTDIR
	fi

	# - Copy bkg maps
	if [ -e $JOB_DIR/$bkg_file ] ; then	
		echo "INFO: Copying bkg map file $bkg_file to $JOB_OUTDIR ..."
		cp $JOB_DIR/$bkg_file $JOB_OUTDIR
	fi
	if [ -e $JOB_DIR/$rms_file ] ; then	
		echo "INFO: Copying rms map file $rms_file to $JOB_OUTDIR ..."
		cp $JOB_DIR/$rms_file $JOB_OUTDIR
	fi  

	# - Show output directory
	echo "INFO: Show files in $JOB_OUTDIR ..."
	ls -ltr $JOB_OUTDIR

	# - Wait a bit after copying data
	#   NB: Needed if using rclone inside a container, otherwise nothing is copied
	if [ "$MOUNT_RCLONE_VOLUME" = "1" ] ; then
		echo "INFO: Sleeping $RCLONE_COPY_WAIT_TIME seconds to allow out file copy ..."
		sleep $RCLONE_COPY_WAIT_TIME
	fi

fi


