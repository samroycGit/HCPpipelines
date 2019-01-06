#!/bin/bash

#
# # ReApplyFixMultiRunPipeline.sh
#
# ## Copyright Notice
#
# Copyright (C) 2017 The Human Connectome Project/Connectome Coordination Facility
#
# * Washington University in St. Louis
# * University of Minnesota
# * Oxford University
#
# ## Author(s)
#
# * Matthew F. Glasser, Department of Anatomy and Neurobiology, Washington University in St. Louis
# * Timothy B. Brown, Neuroinformatics Research Group, Washington University in St. Louis
#
# ## Product
#
# [Human Connectome Project][HCP] (HCP) Pipelines
#
# ## License
#
# See the [LICENSE](https://github.com/Washington-Univesity/Pipelines/blob/master/LICENSE.md) file
#
# <!-- References -->
# [HCP]: http://www.humanconnectome.org
#

# ------------------------------------------------------------------------------
#  Show usage information for this script
# ------------------------------------------------------------------------------

usage()
{
	local script_name
	script_name=$(basename "${0}")

	cat <<EOF

${script_name}: ReApplyFix Pipeline for MultiRun ICA+FIX

This script has two purposes (both in the context of MultiRun FIX):
1) Reapply FIX cleanup to the volume and default CIFTI (i.e., MSMSulc registered surfaces)
following manual reclassification of the FIX signal/noise components (see ApplyHandReClassifications.sh).
2) Apply FIX cleanup to the CIFTI from an alternative surface registration (e.g., MSMAll)
(either for the first time, or following manual reclassification of the components).
Only one of these two purposes can be accomplished per invocation.

Usage: ${script_name} PARAMETER...

PARAMETERs are [ ] = optional; < > = user supplied value

  Note: The PARAMETERs can be specified positionally (i.e. without using the --param=value
        form) by simply specifying all values on the command line in the order they are
		listed below.

		e.g. ${script_name} <path to study folder> <subject ID> <fMRINames> ...

  [--help] : show this usage information and exit
   --path=<path to study folder> OR --study-folder=<path to study folder>
   --subject=<subject ID> (e.g. 100610)
   --fmri-names=<fMRI names> an '@' symbol separated list of fMRI scan names (no whitespace)
     (e.g. /path/to/study/100610/MNINonLinear/Results/tfMRI_RETCCW_7T_AP/tfMRI_RETCCW_7T_AP.nii.gz@/path/to/study/100610/MNINonLinear/Results/tfMRI_RETCW_7T_PA/tfMRI_RETCW_7T_PA.nii.gz)
   --concat-fmri-name=<root name of the concatenated fMRI scan file> [Do not include path, extension, or any 'hp' string]
   --high-pass=<high-pass filter used in multi-run ICA+FIX>
   [--reg-name=<surface registration name> defaults to ${G_DEFAULT_REG_NAME}. (Use NONE for MSMSulc registration)
   [--low-res-mesh=<low res mesh number>] defaults to ${G_DEFAULT_LOW_RES_MESH}
   [--matlab-run-mode={0, 1, 2}] defaults to ${G_DEFAULT_MATLAB_RUN_MODE}
     0 = Use compiled MATLAB
     1 = Use interpreted MATLAB
     2 = Use interpreted Octave
   [--motion-regression={TRUE, FALSE}] defaults to ${G_DEFAULT_MOTION_REGRESSION}

EOF
}

# ------------------------------------------------------------------------------
#  Get the command line options for this script.
# ------------------------------------------------------------------------------
get_options()
{
	local arguments=("$@")

	# initialize global output variables
	unset p_StudyFolder      # ${1}
	unset p_Subject          # ${2}
	unset p_fMRINames        # ${3}
	unset p_ConcatName       # ${4}
	unset p_HighPass         # ${5}
	unset p_RegName          # ${6}
	unset p_LowResMesh       # ${7}
	unset p_MatlabRunMode    # ${8}
	unset p_MotionRegression # ${9}

	# set default values
	p_RegName=${G_DEFAULT_REG_NAME}
	p_LowResMesh=${G_DEFAULT_LOW_RES_MESH}
	p_MatlabRunMode=${G_DEFAULT_MATLAB_RUN_MODE}
	p_MotionRegression=${G_DEFAULT_MOTION_REGRESSION}
	
	# parse arguments
	local num_args=${#arguments[@]}
	local argument
	local index=0

	while [ "${index}" -lt "${num_args}" ]; do
		argument=${arguments[index]}

		case ${argument} in
			--help)
				usage
				exit 1
				;;
			--path=*)
				p_StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--study-folder=*)
				p_StudyFolder=${argument#*=}
				index=$(( index + 1 ))
				;;
			--subject=*)
				p_Subject=${argument#*=}
				index=$(( index + 1 ))
				;;
			--fmri-names=*)
				p_fMRINames=${argument#*=}
				index=$(( index + 1 ))
				;;
			--concat-fmri-name=*)
				p_ConcatName=${argument#*=}
				index=$(( index + 1 ))
				;;
			--high-pass=*)
				p_HighPass=${argument#*=}
				index=$(( index + 1 ))
				;;
			--reg-name=*)
				p_RegName=${argument#*=}
				index=$(( index + 1 ))
				;;
			--low-res-mesh=*)
				p_LowResMesh=${argument#*=}
				index=$(( index + 1 ))
				;;
			--matlab-run-mode=*)
				p_MatlabRunMode=${argument#*=}
				index=$(( index + 1 ))
				;;
			--motion-regression=*)
				p_MotionRegression=${argument#*=}
				index=$(( index + 1 ))
				;;
			*)
				usage
				log_Err_Abort "unrecognized option: ${argument}"
				;;
		esac
	done

	local error_count=0

	# check required parameters
	if [ -z "${p_StudyFolder}" ]; then
		log_Err "Study Folder (--path= or --study-folder=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Study Folder: ${p_StudyFolder}"
	fi
	
	if [ -z "${p_Subject}" ]; then
		log_Err "Subject ID (--subject=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Subject ID: ${p_Subject}"
	fi	

	if [ -z "${p_fMRINames}" ]; then
		log_Err "fMRI Names (--fmri-names=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "fMRI Names: ${p_fMRINames}"
	fi

	if [ -z "${p_ConcatName}" ]; then
		log_Err "Concatenated fMRI scan name (--concat-fmri-name=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Concatenated fMRI scan name: ${p_ConcatName}"
	fi
	
	if [ -z "${p_HighPass}" ]; then
		log_Err "High Pass (--high-pass=) required"
		error_count=$(( error_count + 1 ))
	else
		# Checks on the validity of the --high-pass argument
		if [[ "${p_HighPass}" == "0" ]]; then
			log_Msg "--high-pass=0 corresponds to a linear detrend"
		fi
		if [[ "${p_HighPass}" == pd* ]]; then
			local hpNum=${p_HighPass:2}
		else
			local hpNum=${p_HighPass}
		fi
		if ! [[ "${hpNum}" =~ ^[-]?[0-9]+$ ]]; then
			log_Err "--high-pass argument does not contain a properly specified numeric value"
			error_count=$(( error_count + 1 ))
		fi
		if [[ $(echo "${hpNum} < 0" | bc) == "1" ]]; then
			log_Err "--high-pass value must not be negative"
			error_count=$(( error_count + 1 ))
		fi
		log_Msg "High Pass: ${p_HighPass}"
	fi

	if [ -z "${p_RegName}" ]; then
		log_Err "Reg Name (--reg-name=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Reg Name: ${p_RegName}"
	fi
		
	if [ -z "${p_LowResMesh}" ]; then
		log_Err "Low Res Mesh (--low-res-mesh=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Low Res Mesh: ${p_LowResMesh}"
	fi
	
	if [ -z "${p_MatlabRunMode}" ]; then
		log_Err "MATLAB run mode value (--matlab-run-mode=) required"
		error_count=$(( error_count + 1 ))
	else
		case ${p_MatlabRunMode} in
			0)
				log_Msg "MATLAB Run Mode: ${p_MatlabRunMode} - Use compiled MATLAB"
				if [ -z "${MATLAB_COMPILER_RUNTIME}" ]; then
					log_Err_Abort "To use MATLAB run mode: ${p_MatlabRunMode}, the MATLAB_COMPILER_RUNTIME environment variable must be set"
				else
					log_Msg "MATLAB_COMPILER_RUNTIME: ${MATLAB_COMPILER_RUNTIME}"
				fi
				;;
			1)
				log_Msg "MATLAB Run Mode: ${p_MatlabRunMode} - Use interpreted MATLAB"
				;;
			2)
				log_Msg "MATLAB Run Mode: ${p_MatlabRunMode} - Use interpreted Octave"
				;;
			*)
				log_Err "MATLAB Run Mode value must be 0, 1, or 2"
				error_count=$(( error_count + 1 ))
				;;
		esac
	fi

	if [ -z "${p_MotionRegression}" ]; then
		log_Err "motion regression setting (--motion-regression=) required"
		error_count=$(( error_count + 1 ))
	else
		log_Msg "Motion Regression: ${p_MotionRegression}"
	fi

	if [ ${error_count} -gt 0 ]; then
		log_Err_Abort "For usage information, use --help"
	fi	
}

# ------------------------------------------------------------------------------
#  Show Tool Versions
# ------------------------------------------------------------------------------

show_tool_versions()
{
	# Show HCP pipelines version
	log_Msg "Showing HCP Pipelines version"
	cat ${HCPPIPEDIR}/version.txt

	# Show wb_command version
	log_Msg "Showing Connectome Workbench (wb_command) version"
	${CARET7DIR}/wb_command -version

	# Show fsl version
#	log_Msg "Showing FSL version"
#	fsl_version_get fsl_ver
#	log_Msg "FSL version: ${fsl_ver}"
}

# ------------------------------------------------------------------------------
#  Check for whether or not we have hand reclassification files
# ------------------------------------------------------------------------------

have_hand_reclassification()
{
	local StudyFolder="${1}"
	local Subject="${2}"
	local fMRIName="${3}"
	local HighPass="${4}"

	[ -e "${StudyFolder}/${Subject}/MNINonLinear/Results/${fMRIName}/${fMRIName}_hp${HighPass}.ica/HandNoise.txt" ]
}

# ------------------------------------------------------------------------------
#  Function for demeaning the movement regressors
# ------------------------------------------------------------------------------

demeanMovementRegressors() {
	In=${1}
	log_Debug_Msg "demeanMovementRegressors: In: ${In}"
	Out=${2}
	log_Debug_Msg "demeanMovementRegressors: Out: ${Out}"
	log_Debug_Msg "demeanMovementRegressors: getting nCols"
	nCols=$(head -1 ${In} | wc -w)
	
	log_Debug_Msg "demeanMovementRegressors: nCols: ${nCols}"
	log_Debug_Msg "demeanMovementRegressors: getting nRows"
	nRows=$(wc -l < ${In})
	log_Debug_Msg "demeanMovementRegressors: nRows: ${nRows}"
	
	AllOut=""
	c=1
	while (( c <= nCols )) ; do
		ColIn=`cat ${In} | sed 's/  */ /g' | sed 's/^ //g' | cut -d " " -f ${c}`
		bcstring=$(echo "$ColIn" | tr '\n' '+' | sed 's/\+*$//g')
		valsum=$(echo "$bcstring" | bc -l)
		valmean=$(echo "$valsum / $nRows" | bc -l)
		ColOut=""
		r=1
		while (( r <= nRows )) ; do
			val=`echo "${ColIn}" | head -${r} | tail -1`
			newval=`echo "${val} - ${valmean}" | bc -l`
			ColOut=`echo ${ColOut} $(printf "%10.6f" $newval)`
			r=$((r+1))
		done
		ColOut=`echo ${ColOut} | tr ' ' '\n'`
		AllOut=`paste <(echo "${AllOut}") <(echo "${ColOut}")`
		c=$((c+1))
	done
	echo "${AllOut}" > ${Out}
}

# ------------------------------------------------------------------------------
#  Main processing of script.
# ------------------------------------------------------------------------------

main()
{
	local this_script_dir=$(readlink -f "$(dirname "$0")")

	# Show tool versions
	show_tool_versions

	log_Msg "Starting main functionality"

	# Retrieve positional parameters
	local StudyFolder="${1}"
	local Subject="${2}"
	local fMRINames="${3}"
	local ConcatNameOnly="${4}"
	# Make sure that ${4} is indeed without path or extension
	ConcatNameOnly=$(basename $($FSLDIR/bin/remove_ext $ConcatNameOnly))
	#script used to take absolute paths, so generate the absolute path and leave the old code
	local ConcatName="${StudyFolder}/${Subject}/MNINonLinear/Results/${ConcatNameOnly}/${ConcatNameOnly}"
	local HighPass="${5}"

	local RegName
	if [ -z "${6}" ]; then
		RegName=${G_DEFAULT_REG_NAME}
	else
		RegName="${6}"
	fi
	
	local LowResMesh
	if [ -z "${7}" ]; then
		LowResMesh=${G_DEFAULT_LOW_RES_MESH}
	else
		LowResMesh="${7}"
	fi
	
	local MatlabRunMode
	if [ -z "${8}" ]; then
		MatlabRunMode=${G_DEFAULT_MATLAB_RUN_MODE}
	else
		MatlabRunMode="${8}"
	fi

	local MotionRegression
	if [ -z "${9}" ]; then
		MotionRegression="${G_DEFAULT_MOTION_REGRESSION}"
	else
		MotionRegression="${9}"
	fi

	# Turn MotionRegression into an appropriate numeric value for fix_3_clean
	case $(echo ${MotionRegression} | tr '[:upper:]' '[:lower:]') in
        ( true | yes | 1)
            MotionRegression=1
            ;;
        ( false | no | none | 0)
            MotionRegression=0
            ;;
		*)
			log_Err_Abort "motion regression setting must be TRUE or FALSE"
			;;
	esac
		
	# Log values retrieved from positional parameters
	log_Msg "StudyFolder: ${StudyFolder}"
	log_Msg "Subject: ${Subject}"
	log_Msg "fMRINames: ${fMRINames}"
	log_Msg "ConcatName: ${ConcatName}"
	log_Msg "HighPass: ${HighPass}"
	log_Msg "RegName: ${RegName}"
	log_Msg "LowResMesh: ${LowResMesh}"
	log_Msg "MatlabRunMode: ${MatlabRunMode}"
	log_Msg "MotionRegression: ${MotionRegression}"

	# Naming Conventions and other variables
	local Caret7_Command="${CARET7DIR}/wb_command"
	log_Msg "Caret7_Command: ${Caret7_Command}"
	
	local RegString
	if [ "${RegName}" != "NONE" ] ; then
		RegString="_${RegName}"
	else
		RegString=""
	fi

	if [ ! -z ${LowResMesh} ] && [ ${LowResMesh} != ${G_DEFAULT_LOW_RES_MESH} ]; then
		RegString+=".${LowResMesh}k"
	fi

	log_Msg "RegString: ${RegString}"
	
	# For interpreted modes, make sure that fix_3_clean has access to the functions it needs
	# (e.g., read_avw, save_avw, ciftiopen, ciftisave)
	# Several environment variables are set in FSL_FIXDIR/settings.sh, which is sourced below for interpreted modes
	export FSL_MATLAB_PATH="${FSLDIR}/etc/matlab"
	local ML_PATHS="addpath('${FSL_MATLAB_PATH}'); addpath('${FSL_FIXDIR}');"

	export FSL_FIX_WBC="${Caret7_Command}"
	# WARNING: FSL_FIXDIR/settings.sh doesn't currently check whether FSL_FIX_WBC is already defined.
	# Thus, when that settings.sh file gets sourced as part of the invocation of the intepreted matlab
	# and octave modes (below), there is a possibility that the version of wb_command used within
	# interpreted matlab/octave may not be the same as what is used throughout the remainder of this script.
	# (It all depends on how the user has set up their FSL_FIXDIR/settings.sh file).
	
	# Some defaults
	local aggressive=0
	local newclassification=0
	local hp=${HighPass}
	local DoVol=0
	local fixlist=".fix"

    # If we have a hand classification and no regname, reapply fix to the volume as well
	if have_hand_reclassification ${StudyFolder} ${Subject} ${ConcatNameOnly} ${hp}
	then
		fixlist="HandNoise.txt"
		#TSC: if regname (which applies to the surface) isn't NONE, assume the hand classification was previously already applied to the volume data
		if [[ "${RegName}" == "NONE" ]]
		then
			DoVol=1
		fi
	fi
	# WARNING: fix_3_clean doesn't actually do anything different based on the value of DoVol (its 5th argument).
	# Rather, if a 5th argument is present, fix_3_clean does NOT apply cleanup to the volume, *regardless* of whether
	# that 5th argument is 0 or 1 (or even a non-sensical string such as 'foo').
	# It is for that reason that the code below needs to use separate calls to fix_3_clean, with and without DoVol
	# as an argument, rather than simply passing in the value of DoVol as set within this script.
	# Not sure if/when this non-intuitive behavior of fix_3_clean will change, but this is accurate as of fix1.067

	log_Msg "Use fixlist=$fixlist"
	
	local fmris=${fMRINames//@/ } # replaces the @ that combines the filenames with a space
	log_Msg "fmris: ${fmris}"

	DIR=`pwd`
	log_Msg "PWD : $DIR"

	###LOOP HERE --> Since the files are being passed as a group

	echo $fmris | tr ' ' '\n' #separates paths separated by ' '

	## ---------------------------------------------------------------------------
	## Preparation (highpass) on the individual runs
	## ---------------------------------------------------------------------------

	#Loops over the runs and do highpass on each of them
	log_Msg "Looping over files and doing highpass to each of them"
	
    NIFTIvolMergeSTRING=""
    NIFTIvolhpVNMergeSTRING=""
    SBRefVolSTRING=""
    MeanVolSTRING=""
    VNVolSTRING=""
    CIFTIMergeSTRING=""
    CIFTIhpVNMergeSTRING=""
    MeanCIFTISTRING=""
    VNCIFTISTRING=""
    MovementNIFTIMergeSTRING=""
    MovementNIFTIhpMergeSTRING=""
    MovementTXTMergeSTRING=""

	for fmriname in $fmris ; do
		# Make sure that fmriname is indeed without path or extension
		fmriname=$(basename $($FSLDIR/bin/remove_ext $fmriname))
	    #script used to take absolute paths, so generate the absolute path and leave the old code
	    fmri="${StudyFolder}/${Subject}/MNINonLinear/Results/${fmriname}/${fmriname}.nii.gz"

		log_Msg "Top of loop through fmris: fmri: ${fmri}"

		fmriNoExt=$($FSLDIR/bin/remove_ext $fmri)

		# Create necessary strings for merging across runs
		# N.B. Some of these files don't exist yet, and are about to get created
		NIFTIvolMergeSTRING+="${fmriNoExt}_demean "
		NIFTIvolhpVNMergeSTRING+="${fmriNoExt}_hp${hp}_vnts "  #These are the individual run, VN'ed *time series*
		SBRefVolSTRING+="${fmriNoExt}_SBRef "
		MeanVolSTRING+="${fmriNoExt}_mean "
		VNVolSTRING+="${fmriNoExt}_hp${hp}_vn "  #These are the individual run, VN'ed NIFTI *maps* (created by functionhighpassandvariancenormalize)
		CIFTIMergeSTRING+="-cifti ${fmriNoExt}_Atlas${RegString}_demean.dtseries.nii "
		CIFTIhpVNMergeSTRING+="-cifti ${fmriNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii "
		MeanCIFTISTRING+="-cifti ${fmriNoExt}_Atlas${RegString}_mean.dscalar.nii "
		VNCIFTISTRING+="-cifti ${fmriNoExt}_Atlas${RegString}_hp${hp}_vn.dscalar.nii "  #These are the individual run, VN'ed CIFTI *maps* (created by functionhighpassandvariancenormalize)
		MovementNIFTIMergeSTRING+="${fmriNoExt}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf.nii.gz "
		MovementNIFTIhpMergeSTRING+="${fmriNoExt}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf_hp.nii.gz "

		cd `dirname $fmri`
		fmri=`basename $fmri`  # After this, $fmri no longer includes the leading directory components
		fmri=`$FSLDIR/bin/imglob $fmri`  # After this, $fmri will no longer have an extension (if there was one initially)
		log_Msg "fmri: $fmri"
		[ `imtest $fmri` != 1 ] && echo Invalid FMRI file && exit 1

		tr=`$FSLDIR/bin/fslval $fmri pixdim4`
		log_Msg "tr: $tr"
		log_Msg "processing FMRI file $fmri with highpass $hp"

		#Demean movement regressors, volumes, and CIFTI data
        if [[ ! -f Movement_Regressors_demean.txt ]]; then
    	    demeanMovementRegressors Movement_Regressors.txt Movement_Regressors_demean.txt
	    fi
	    MovementTXTMergeSTRING+="$(pwd)/Movement_Regressors_demean.txt "
	    
		if [[ ! -f ${fmri}_demean.nii.gz ]]; then
		    ${FSLDIR}/bin/fslmaths $fmri -Tmean ${fmri}_mean
	        ${FSLDIR}/bin/fslmaths $fmri -sub ${fmri}_mean ${fmri}_demean
        fi

	    if [[ ! -f ${fmriNoExt}_Atlas${RegString}_demean.dtseries.nii ]]; then
	        ${FSL_FIX_WBC} -cifti-reduce ${fmriNoExt}_Atlas${RegString}.dtseries.nii MEAN ${fmriNoExt}_Atlas${RegString}_mean.dscalar.nii
	        ${FSL_FIX_WBC} -cifti-math "TCS - MEAN" ${fmriNoExt}_Atlas${RegString}_demean.dtseries.nii -var TCS ${fmriNoExt}_Atlas${RegString}.dtseries.nii -var MEAN ${fmriNoExt}_Atlas${RegString}_mean.dscalar.nii -select 1 1 -repeat
        fi

		# MPH: ReApplyFixMultiRunPipeline has only a single pass through functionhighpassandvariancenormalize
		# whereas hcp_fix_multi_run has two (because it runs melodic, which is not re-run here).
		# So, the "1st pass" VN is the only-pass, and there is no "2nd pass" VN
		
		# Check if "1st pass" VN on the individual runs is needed; high-pass gets done here as well
        if [[ ! -f "${fmriNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii" || \
              ! -f "${fmriNoExt}_Atlas${RegString}_vn.dscalar.nii" || \
              ! -f "${fmriNoExt}_hp${hp}_vnts.nii.gz" || \
              ! -f "${fmriNoExt}_hp${hp}_vn.nii.gz" ]]
        then
            if [[ -e .fix.functionhighpassandvariancenormalize.log ]] ; then
                rm .fix.functionhighpassandvariancenormalize.log
            fi
	    	case ${MatlabRunMode} in
		    0)
			    # Use Compiled Matlab
				# MPH: Current version of fix (fix1.067) does not have a compiled version of run_functionhighpassandvariancenormalize
				log_Err_Abort "MATLAB run mode of ${MatlabRunMode} not currently supported"
				
                "${FSL_FIXDIR}/compiled/$(uname -s)/$(uname -m)/run_functionhighpassandvariancenormalize.sh" "${MATLAB_COMPILER_RUNTIME}" "$tr" "$hp" "$fmri" "${FSL_FIX_WBC}" "${RegString}"
                ;;
            1)
                # interpreted matlab
                (source "${FSL_FIXDIR}/settings.sh"; echo "${ML_PATHS} addpath('${this_script_dir}/scripts'); functionhighpassandvariancenormalize($tr, $hp, '$fmri', '${FSL_FIX_WBC}', '${RegString}');" | matlab -nojvm -nodisplay -nosplash)
                ;;
            2)
                # interpreted octave
                (source "${FSL_FIXDIR}/settings.sh"; echo "${ML_PATHS} addpath('${this_script_dir}/scripts'); functionhighpassandvariancenormalize($tr, $hp, '$fmri', '${FSL_FIX_WBC}', '${RegString}');" | octave-cli -q --no-window-system)
                ;;
            esac
	    fi

        log_Msg "Dims: $(cat ${fmri}_dims.txt)"

		# Demean the movement regressors
        if [[ ! -f $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf.nii.gz ]]; then
	        fslmaths $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf.nii.gz -Tmean $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf_mean.nii.gz
	        fslmaths $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf.nii.gz -sub $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf_mean.nii.gz $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf.nii.gz
	        $FSLDIR/bin/imrm $(pwd)/${fmri}_hp${hp}.ica/mc/prefiltered_func_data_mcf_conf_mean.nii.gz
	    fi

	    log_Msg "Bottom of loop through fmris: fmri: ${fmri}"

	done  ###END LOOP (for fmriname in $fmris; do)

	## ---------------------------------------------------------------------------
	## Concatenate the individual runs and create necessary files
	## ---------------------------------------------------------------------------

	ConcatNameNoExt=$($FSLDIR/bin/remove_ext $ConcatName)  # No extension, but still includes the directory path
	
    if [[ ! -f ${ConcatNameNoExt}.nii.gz ]]; then
		# Merge volumes from the individual runs
        fslmerge -tr ${ConcatNameNoExt}_demean ${NIFTIvolMergeSTRING} $tr
        fslmerge -tr ${ConcatNameNoExt}_hp${hp}_vnts ${NIFTIvolhpVNMergeSTRING} $tr
        fslmerge -t  ${ConcatNameNoExt}_SBRef ${SBRefVolSTRING}
        fslmerge -t  ${ConcatNameNoExt}_mean ${MeanVolSTRING}
        fslmerge -t  ${ConcatNameNoExt}_hp${hp}_vn ${VNVolSTRING}
		# Average across runs
        fslmaths ${ConcatNameNoExt}_SBRef -Tmean ${ConcatNameNoExt}_SBRef
        fslmaths ${ConcatNameNoExt}_mean -Tmean ${ConcatNameNoExt}_mean  # "Grand" mean across runs
		fslmaths ${ConcatNameNoExt}_demean -add ${ConcatNameNoExt}_mean ${ConcatNameNoExt}
		  # Preceeding line adds back in the "grand" mean; resulting file not used below, but want this concatenated version (without HP or VN) to exist
        fslmaths ${ConcatNameNoExt}_hp${hp}_vn -Tmean ${ConcatNameNoExt}_hp${hp}_vn  # Mean VN map across the individual runs
        fslmaths ${ConcatNameNoExt}_hp${hp}_vnts -mul ${ConcatNameNoExt}_hp${hp}_vn ${ConcatNameNoExt}_hp${hp} 
          # Preceeding line restores the mean VN map
        fslmaths ${ConcatNameNoExt}_SBRef -bin ${ConcatNameNoExt}_brain_mask # Inserted to create mask to be used in melodic for suppressing memory error - Takuya Hayashi
    fi

	# Same thing for the CIFTI
    if [[ ! -f ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}.dtseries.nii ]]; then
        ${FSL_FIX_WBC} -cifti-merge ${ConcatNameNoExt}_Atlas${RegString}_demean.dtseries.nii ${CIFTIMergeSTRING}
        ${FSL_FIX_WBC} -cifti-average ${ConcatNameNoExt}_Atlas${RegString}_mean.dscalar.nii ${MeanCIFTISTRING}
        ${FSL_FIX_WBC} -cifti-math "TCS + MEAN" ${ConcatNameNoExt}_Atlas${RegString}.dtseries.nii -var TCS ${ConcatNameNoExt}_Atlas${RegString}_demean.dtseries.nii -var MEAN ${ConcatNameNoExt}_Atlas${RegString}_mean.dscalar.nii -select 1 1 -repeat
        ${FSL_FIX_WBC} -cifti-merge ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii ${CIFTIhpVNMergeSTRING}
        ${FSL_FIX_WBC} -cifti-average ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}_vn.dscalar.nii ${VNCIFTISTRING}
        ${FSL_FIX_WBC} -cifti-math "TCS * VN" ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}.dtseries.nii -var TCS ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii -var VN ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}_vn.dscalar.nii -select 1 1 -repeat
    fi
	
	# At this point the concatenated VN'ed time series (both volume and CIFTI, following the "1st pass" VN) can be deleted
	log_Msg "Removing the concatenated VN'ed time series"
	$FSLDIR/bin/imrm ${ConcatNameNoExt}_hp${hp}_vnts
	/bin/rm -f ${ConcatNameNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii

	# Nor do we need the concatenated demeaned time series (either volume or CIFTI)
	log_Msg "Removing the concatenated demeaned time series"
	$FSLDIR/bin/imrm ${ConcatNameNoExt}_demean
	/bin/rm -f ${ConcatNameNoExt}_Atlas${RegString}_demean.dtseries.nii

	# Also, we no longer need the individual run VN'ed or demeaned time series (either volume or CIFTI); delete to save space
	for fmri in $fmris ; do
		log_Msg "Removing the individual run VN'ed and demeaned time series for ${fmri}"
		fmriNoExt=$($FSLDIR/bin/remove_ext $fmri)
		$FSLDIR/bin/imrm ${fmriNoExt}_hp${hp}_vnts
		$FSLDIR/bin/imrm ${fmriNoExt}_demean
		/bin/rm -f ${fmriNoExt}_Atlas${RegString}_hp${hp}_vn.dtseries.nii
		/bin/rm -f ${fmriNoExt}_Atlas${RegString}_demean.dtseries.nii

		# Following removes the individual run hp'ed time series
		# MPH, 12/21/2018: Leaving them for now
		#	log_Msg "Removing the individual run HP'ed time series for ${fmri}"
		#	$FSLDIR/bin/imrm ${fmriNoExt}_hp${hp}
		#	/bin/rm -f ${fmriNoExt}_Atlas${RegString}_hp${hp}.dtseries.nii
	done

	## ---------------------------------------------------------------------------
	## Housekeeping related to files expected for fix_3_clean
	## ---------------------------------------------------------------------------

	local ConcatFolder=`dirname ${ConcatName}`
	cd ${ConcatFolder}
	##Check to see if concatination occured

	local concatfmri=`basename ${ConcatNameNoExt}`  # Directory path is now removed
	local concatfmrihp=${concatfmri}_hp${hp}

    #this directory should exist and not be empty (i.e., melodic has already been run)
	cd ${concatfmrihp}.ica

	#This is the concated volume time series from the 1st pass VN, with the mean VN map multiplied back in
	${FSLDIR}/bin/imrm filtered_func_data
	${FSLDIR}/bin/imln ../${concatfmrihp} filtered_func_data

	#This is the concated CIFTI time series from the 1st pass VN, with the mean VN map multiplied back in
	if [[ -f ../${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii ]] ; then
		log_Msg "FOUND FILE: ../${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii"
		log_Msg "Performing imln"

		rm -f Atlas.dtseries.nii
		$FSLDIR/bin/imln ../${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii Atlas.dtseries.nii
		
		log_Msg "START: Showing linked files"
		ls -l ../${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii
		ls -l Atlas.dtseries.nii
		log_Msg "END: Showing linked files"
	else
		log_Err_Abort "FILE NOT FOUND: ../${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii"
	fi
	
	AlreadyHP="-1"

	case ${MatlabRunMode} in
		0)
			# Use Compiled Matlab
			
			local matlab_exe="${HCPPIPEDIR}/ICAFIX/scripts/Compiled_fix_3_clean/run_fix_3_clean.sh"
	
			#matlab_compiler_runtime=${MATLAB_COMPILER_RUNTIME}
			local matlab_function_arguments=("'${fixlist}'" "${aggressive}" "${MotionRegression}" "${AlreadyHP}")
			if [[ DoVol == 0 ]]
			then
    			matlab_function_arguments+=("${DoVol}")
			fi
			local matlab_logfile="${StudyFolder}/${Subject}_${concatfmri}${RegString}_hp${hp}.matlab.log"
			#MPH: This logfile should go in a different location (probably in the .ica directory)

			local matlab_cmd=("${matlab_exe}" "${MATLAB_COMPILER_RUNTIME}" "${matlab_function_arguments[@]}")

			# redirect tokens must be parsed by bash before doing variable expansion, and thus can't be inside a variable
			log_Msg "Run MATLAB command: ${matlab_cmd[*]} >> ${matlab_logfile} 2>&1"
			"${matlab_cmd[@]}" >> "${matlab_logfile}" 2>&1
			log_Msg "MATLAB command return code $?"
			;;
		
		1)
			# Use interpreted MATLAB
            if [[ DoVol == 0 ]]
            then
    			(source "${FSL_FIXDIR}/settings.sh"; matlab -nojvm -nodisplay -nosplash <<M_PROG
${ML_PATHS} fix_3_clean('${fixlist}',${aggressive},${MotionRegression},${AlreadyHP},${DoVol});
M_PROG
)
            else
    			(source "${FSL_FIXDIR}/settings.sh"; matlab -nojvm -nodisplay -nosplash <<M_PROG
${ML_PATHS} fix_3_clean('${fixlist}',${aggressive},${MotionRegression},${AlreadyHP});
M_PROG
)
            fi

			;;

		2)
			# Use interpreted OCTAVE
            if [[ DoVol == 0 ]]
            then
    			(source "${FSL_FIXDIR}/settings.sh"; octave-cli -q --no-window-system <<M_PROG
${ML_PATHS} fix_3_clean('${fixlist}',${aggressive},${MotionRegression},${AlreadyHP},${DoVol});
M_PROG
)
            else
    			(source "${FSL_FIXDIR}/settings.sh"; octave-cli -q --no-window-system <<M_PROG
${ML_PATHS} fix_3_clean('${fixlist}',${aggressive},${MotionRegression},${AlreadyHP});
M_PROG
)
            fi

			;;

		*)
			# Unsupported MATLAB run mode
			log_Err_Abort "Unsupported MATLAB run mode value: ${MatlabRunMode}"
			;;
	esac

	cd ..

	## ---------------------------------------------------------------------------
	## Rename some files (relative to the default names coded in fix_3_clean.m)
	## ---------------------------------------------------------------------------

	if [[ -f ${concatfmrihp}.ica/filtered_func_data_clean.nii.gz ]]
	then
	    $FSLDIR/bin/immv ${concatfmrihp}.ica/filtered_func_data_clean ${concatfmrihp}_clean
        $FSLDIR/bin/immv ${concatfmrihp}.ica/filtered_func_data_clean_vn ${concatfmrihp}_clean_vn
	fi

	if [[ -f ${concatfmrihp}.ica/Atlas_clean.dtseries.nii ]] ; then
		/bin/mv ${concatfmrihp}.ica/Atlas_clean.dtseries.nii ${concatfmri}_Atlas${RegString}_hp${hp}_clean.dtseries.nii
		/bin/mv ${concatfmrihp}.ica/Atlas_clean_vn.dscalar.nii ${concatfmri}_Atlas${RegString}_hp${hp}_clean_vn.dscalar.nii
	fi

	## ---------------------------------------------------------------------------
	## Split the cleaned volume and CIFTI back into individual runs.
	## ---------------------------------------------------------------------------

	## The cleaned volume and CIFTI have no mean.
	## The time series of the individual runs were variance normalized via the 1st pass through functionhighpassandvariancenormalize.
	## The mean VN map (across runs) was then multiplied into the concatenated time series, and that became the input to FIX.
	## We now reverse that process.
	## i.e., the mean VN (across runs) is divided back out, and the VN map for the individual run multiplied back in.
	## Then the mean is added back in to return the timeseries to its original state minus the noise (as estimated by FIX).
	
	Start="1"
	for fmriname in $fmris ; do
	    # Make sure that fmriname is indeed without path or extension
		fmriname=$(basename $($FSLDIR/bin/remove_ext $fmriname))
	    #script used to take absolute paths, so generate the absolute path and leave the old code
	    fmri="${StudyFolder}/${Subject}/MNINonLinear/Results/${fmriname}/${fmriname}.nii.gz"
		fmriNoExt=$($FSLDIR/bin/remove_ext $fmri)
		NumTPS=`${FSL_FIX_WBC} -file-information ${fmriNoExt}_Atlas${RegString}.dtseries.nii -no-map-info -only-number-of-maps`
	    Stop=`echo "${NumTPS} + ${Start} -1" | bc -l`
	    log_Msg "Start=${Start} Stop=${Stop}"
	
	    log_Debug_Msg "Splitting cifti back into individual runs"
	    cifti_out=${fmriNoExt}_Atlas${RegString}_hp${hp}_clean.dtseries.nii
	    ${FSL_FIX_WBC} -cifti-merge ${cifti_out} -cifti ${concatfmri}_Atlas${RegString}_hp${hp}_clean.dtseries.nii -column ${Start} -up-to ${Stop}
	    ${FSL_FIX_WBC} -cifti-math "((TCS / VNA) * VN) + Mean" ${cifti_out} -var TCS ${cifti_out} -var VNA ${concatfmri}_Atlas${RegString}_hp${hp}_vn.dscalar.nii -select 1 1 -repeat -var VN ${fmriNoExt}_Atlas${RegString}_hp${hp}_vn.dscalar.nii -select 1 1 -repeat -var Mean ${fmriNoExt}_Atlas${RegString}_mean.dscalar.nii -select 1 1 -repeat

	    readme_for_cifti_out=${cifti_out%.dtseries.nii}.README.txt
	    touch ${readme_for_cifti_out}
	    short_cifti_out=${cifti_out##*/}
	    echo "${short_cifti_out} was generated by applying \"multi-run FIX\" (using 'ReApplyFixPipelineMultiRun.sh')" >> ${readme_for_cifti_out}
	    echo "across the following individual runs:" >> ${readme_for_cifti_out}
	    for readme_fmri_name in ${fmris} ; do
    	    # Make sure that readme_fmri_name is indeed without path or extension
			readme_fmri_name=$(basename $($FSLDIR/bin/remove_ext $readme_fmri_name))
			#script used to take absolute paths, so generate the absolute path and leave the old code
    	    readme_fmri="${StudyFolder}/${Subject}/MNINonLinear/Results/${readme_fmri_name}/${readme_fmri_name}.nii.gz"
		    echo "  ${readme_fmri}" >> ${readme_for_cifti_out}
	    done
		
		if (( DoVol == 1 ))
		then
	        log_Debug_Msg "Splitting volumes (nifti) back into individual runs"
			volume_out=${fmriNoExt}_hp${hp}_clean.nii.gz
	        ${FSL_FIX_WBC} -volume-merge ${volume_out} -volume ${concatfmrihp}_clean.nii.gz -subvolume ${Start} -up-to ${Stop}
	        fslmaths ${volume_out} -div ${concatfmrihp}_vn -mul ${fmriNoExt}_hp${hp}_vn -add ${fmriNoExt}_mean ${volume_out}
        fi
	    Start=`echo "${Start} + ${NumTPS}" | bc -l`
	done

	## ---------------------------------------------------------------------------
	## Remove all the large time series files in ${ConcatFolder}
	## ---------------------------------------------------------------------------

	## Deleting these files would save a lot of space.
	## But downstream scripts (e.g., RestingStateStats) assume they exist, and
	## if deleted they would therefore need to be re-created "on the fly" later
	
	# $FSLDIR/bin/imrm ${concatfmri}
	# $FSLDIR/bin/imrm ${concatfmri}_hp${hp}
	# $FSLDIR/bin/imrm ${concatfmri}_hp${hp}_clean
	# /bin/rm -f ${concatfmri}_Atlas${RegString}.dtseries.nii
	# /bin/rm -f ${concatfmri}_Atlas${RegString}_hp${hp}.dtseries.nii
	# /bin/rm -f ${concatfmri}_Atlas${RegString}_hp${hp}_clean.dtseries.nii

	cd ${DIR}

	log_Msg "Completing main functionality"
}

# ------------------------------------------------------------------------------
#  "Global" processing - everything above here should be in a function
# ------------------------------------------------------------------------------

set -e # If any command exits with non-zero value, this script exits

# Verify that HCPPIPEDIR environment variable is set
if [ -z "${HCPPIPEDIR}" ]; then
	echo "$(basename ${0}): ABORTING: HCPPIPEDIR environment variable must be set"
	exit 1
fi

# Load function libraries
source ${HCPPIPEDIR}/global/scripts/log.shlib # Logging related functions
source ${HCPPIPEDIR}/global/scripts/fsl_version.shlib # Functions for getting FSL version
log_SetToolName "ReApplyFixPipelineMultiRun.sh"
log_Msg "HCPPIPEDIR: ${HCPPIPEDIR}"

# Verify any other needed environment variables are set
log_Check_Env_Var CARET7DIR
log_Check_Env_Var FSLDIR

# Establish defaults
G_DEFAULT_REG_NAME="NONE"
G_DEFAULT_LOW_RES_MESH=32
G_DEFAULT_MATLAB_RUN_MODE=1		# Use interpreted MATLAB
G_DEFAULT_MOTION_REGRESSION="FALSE"
	
# Determine whether named or positional parameters are used
if [[ ${1} == --* ]]; then
	# Named parameters (e.g. --parameter-name=parameter-value) are used
	log_Msg "Using named parameters"

	# Get command line options
	get_options "$@"

	# Invoke main functionality
	#     ${1}               ${2}           ${3}             ${4}                  ${5}            ${6}           ${7}              ${8}                ${9}
	main "${p_StudyFolder}" "${p_Subject}" "${p_fMRINames}" "${p_ConcatName}" "${p_HighPass}" "${p_RegName}" "${p_LowResMesh}" "${p_MatlabRunMode}" "${p_MotionRegression}"

else
	# Positional parameters are used
	log_Msg "Using positional parameters"
	main "$@"

fi







