#!/bin/bash -e

# NB: -e makes script to fail if internal script fails (for example when --run is enabled)

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
	echo "--inputfile=[FILENAME] - Input FITS file"
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
	echo "--ncores=[NCORES] - Number of cores to use [Default = all available]"
	echo "--run - Run the generated run script on the local shell. If disabled only run script will be generated for later run."	
	echo "--no-logredir - Do not redirect logs to output file in script "
	echo "--jobdir=[PATH] - Directory where to run job (default=/home/[RUNUSER]/aegean-job)"
	echo "--joboutdir=[PATH] - Directory where to place output products (same of rundir if empty) (default=empty)"
	echo "--waitcopy - Wait a bit after copying output files to output dir (default=no)"
	echo "--copywaittime=[COPY_WAIT_TIME] - Time to wait after copying output files (default=30)"
	echo "--save-summaryplot - Save summary plot with image+regions"
	echo "--save-catalog-to-json - Save catalogs to json format"
	echo "--save-bkgmaps - Save bkg & noise maps"

	echo ""

	echo "=========================="
  exit 1
fi


##########################
##    PARSE ARGS
##########################
JOB_DIR=""
JOB_OUTDIR=""
WAIT_COPY=false
COPY_WAIT_TIME=30

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
SAVE_CATALOG_TO_JSON=false
REDIRECT_LOGS=true
RUN_SCRIPT=false

echo "ARGS: $@"

for item in "$@"
do
	case $item in
		
		--inputfile=*)
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
		--save-catalog-to-json*)
    	SAVE_CATALOG_TO_JSON=true
    ;;
		--jobdir=*)
    	JOB_DIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--joboutdir=*)
    	JOB_OUTDIR=`echo "$item" | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--waitcopy*)
    	WAIT_COPY=true
    ;;
		--copywaittime=*)
    	COPY_WAIT_TIME=`echo $item | /bin/sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--ncores=*)
      NCORES=`echo $item | sed 's/[-a-zA-Z0-9]*=//'`
    ;;
		--no-logredir*)
			REDIRECT_LOGS=false
		;;
		--run*)
    	RUN_SCRIPT=true
    ;;
	*)
    # Unknown option
    echo "ERROR: Unknown option ($item)...exit!"
    exit 1
    ;;
	esac
done

# - Check arguments parsed
if [ "$INPUT_IMAGE" = "" ]; then
 	echo "ERROR: Missing input image arg!"
	exit 1
fi

if [ "$JOB_DIR" = "" ]; then
  echo "WARN: Empty JOB_DIR given, setting it to pwd ($PWD) ..."
	JOB_DIR="$PWD"
fi

if [ "$JOB_OUTDIR" = "" ]; then
  echo "WARN: Empty JOB_OUTDIR given, setting it to pwd ($PWD) ..."
	JOB_OUTDIR="$PWD"
fi

# - Extract base filename
filename=$INPUT_IMAGE
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

# - Set shfile
shfile="run_$filename_base_noext"'.sh'


#######################################
##   DEFINE GENERATE EXE SCRIPT FCN
#######################################
generate_exec_script(){

	local shfile=$1
	
	
	echo "INFO: Creating sh file $shfile ..."
	( 
			echo "#!/bin/bash -e"
			
      echo " "
      echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         PREPARE JOB                     ****"'
      echo 'echo "*************************************************"'

      echo " "
       
      echo "echo \"INFO: Entering job dir $JOB_DIR ...\""
      echo "cd $JOB_DIR"

			echo " "
				
			echo "REMOVE_IMAGE=false"
			if [ ! -e $JOB_DIR/$filename_base ] ; then
				echo "echo \"INFO: Copying input file to job dir $JOB_DIR ...\""
				echo "cp $filename $JOB_DIR"
				echo "REMOVE_IMAGE=true"
      	echo " "
			fi

			echo " "

			echo "touch $logfile"

			echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         RUN BANE                        ****"'
      echo 'echo "*************************************************"'
			
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
			
			CMD="$EXE $ARGS"

			echo "echo \"INFO: Computing background & noise maps (CMD=$CMD) ...\""
			if [ $REDIRECT_LOGS = true ]; then			
      	echo "$CMD >> $logfile 2>&1"
			else
				echo "$CMD"
      fi

			echo " "

			echo 'BANE_STATUS=$?'
			echo 'if [ "$BANE_STATUS" != "0" ]; then'
			echo '  echo "ERROR: BANE failed with code=$BANE_STATUS ..."'	
			echo '  exit $BANE_STATUS'
			echo 'fi'

      echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         RUN SOURCE FINDER               ****"'
      echo 'echo "*************************************************"'
      
			EXE="aegean"
			ARGS="--find --cores=$NCORES --noise=$rms_file --background=$bkg_file --maxsummits=$FIT_MAX_COMPONENTS --seedclip=$SEED_THR --floodclip=$MERGE_THR --island --out=$catalog_file --table=$ds9_file,$catalog_tab_file $filename_base"
			CMD="$EXE $ARGS"

			echo "echo \"INFO: Extracting sources  (CMD=$CMD) ...\""
			if [ $REDIRECT_LOGS = true ]; then			
      	echo "$CMD >> $logfile 2>&1"
			else
				echo "$CMD"
      fi

      echo " "

			echo 'JOB_STATUS=$?'
			echo 'echo "Source finding terminated with status=$JOB_STATUS"'

			echo " "

			
			if [ $SAVE_SUMMARY_PLOT = true ]; then
      	echo 'echo "*************************************************"'
      	echo 'echo "****         MAKE SUMMARY PLOT             ****"'
      	echo 'echo "*************************************************"'
      
				echo "if [ -e $JOB_DIR/$ds9_comp_file ] ; then"
				echo "  echo \"INFO: Making summary plot with input image + extracted source islands ...\""
				echo "  draw_img.py --img=$filename_base --region=$ds9_comp_file --wcs --zmin=0 --zmax=0 --cmap=gray_r --contrast=0.3 --save --outfile=$summary_plot_file"
				echo "fi"	
			fi
			
			echo " "

			echo 'echo "*************************************************"'
      echo 'echo "****         CLEAR DATA                      ****"'
      echo 'echo "*************************************************"'
     
			echo 'echo "INFO: Clearing data ..."'

			echo 'if [ $REMOVE_IMAGE = false ]; then'
			echo "  rm $JOB_DIR/$filename_base"
			echo "fi"

			echo " "

			if [ $SAVE_BKG_MAPS = false ]; then
				echo "if [ -e $JOB_DIR/$bkg_file ] ; then"
				echo "  echo \"INFO: Removing bkg map file $bkg_file ...\""
		    echo "  rm $JOB_DIR/$bkg_file"
				echo "fi"
				echo ""	
				echo "if [ -e $JOB_DIR/$rms_file ] ; then"	
				echo "  echo \"INFO: Removing rms map file $rms_file ...\""
				echo "  rm $JOB_DIR/$rms_file"
				echo "fi"
			fi

      echo " "

      echo 'echo "*************************************************"'
      echo 'echo "****         COPY DATA TO OUTDIR             ****"'
      echo 'echo "*************************************************"'
      echo 'echo ""'
			
			if [ "$JOB_DIR" != "$JOB_OUTDIR" ]; then
				echo "echo \"INFO: Copying job outputs in $JOB_OUTDIR ...\""
				echo "ls -ltr $JOB_DIR"
				echo " "

				echo "# - Copy output plot(s)"
				echo 'png_count=`ls -1 *.png 2>/dev/null | wc -l`'
  			echo 'if [ $png_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output plot file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.png $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output jsons"
				echo 'json_count=`ls -1 *.json 2>/dev/null | wc -l`'
				echo 'if [ $json_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output json file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.json $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output tables"
				echo 'tab_count=`ls -1 *.tab 2>/dev/null | wc -l`'
				echo 'if [ $tab_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output table file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.tab $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy output regions"
				echo 'reg_count=`ls -1 *.reg 2>/dev/null | wc -l`'
				echo 'if [ $reg_count != 0 ] ; then'
				echo "  echo \"INFO: Copying output region file(s) to $JOB_OUTDIR ...\""
				echo "  cp *.reg $JOB_OUTDIR"
				echo "fi"

				echo " "

				echo "# - Copy bkg maps"
				echo "if [ -e $JOB_DIR/$bkg_file ] ; then"
				echo "  echo \"INFO: Copying bkg map file $bkg_file to $JOB_OUTDIR ...\""
				echo "  cp $JOB_DIR/$bkg_file $JOB_OUTDIR"
				echo "fi"

				echo " "
		
				echo "if [ -e $JOB_DIR/$rms_file ] ; then"
				echo "  echo \"INFO: Copying rms map file $rms_file to $JOB_OUTDIR ...\""
				echo "  cp $JOB_DIR/$rms_file $JOB_OUTDIR"
				echo "fi"  

				echo " "

				echo "# - Show output directory"
				echo "echo \"INFO: Show files in $JOB_OUTDIR ...\""
				echo "ls -ltr $JOB_OUTDIR"

				echo " "

				echo "# - Wait a bit after copying data"
				echo "#   NB: Needed if using rclone inside a container, otherwise nothing is copied"
				if [ $WAIT_COPY = true ]; then
           echo "sleep $COPY_WAIT_TIME"
        fi
	
			fi

      echo " "
      echo " "
      
      echo 'echo "*** END RUN ***"'

			echo 'exit $JOB_STATUS'

 	) > $shfile

	chmod +x $shfile
}
## close function generate_exec_script()

###############################
##    RUN AEGEAN
###############################
# - Check if job directory exists
if [ ! -d "$JOB_DIR" ] ; then 
  echo "INFO: Job dir $JOB_DIR not existing, creating it now ..."
	mkdir -p "$JOB_DIR" 
fi

# - Moving to job directory
echo "INFO: Moving to job directory $JOB_DIR ..."
cd $JOB_DIR

# - Generate run script
#filename_base=$(/usr/bin/basename "$INPUT_IMAGE")
#file_extension="${filename_base##*.}"
#filename_base_noext="${filename_base%.*}"
#shfile="run_$filename_base_noext"'.sh'

echo "INFO: Creating run script file $shfile ..."
generate_exec_script "$shfile"

# - Launch run script
if [ "$RUN_SCRIPT" = true ] ; then
	echo "INFO: Running script $shfile to local shell system ..."
	$JOB_DIR/$shfile
fi


echo "*** END SUBMISSION ***"

