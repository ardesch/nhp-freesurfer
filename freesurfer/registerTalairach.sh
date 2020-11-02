#!/bin/bash

# Some default parameters
clean_up=0
reg_stages=3

# Help message
usage () {
echo "
=== registerTalairach ===

This script provides an alternative to FreeSurfer's -talairach, 
-gcareg, and -careg steps. It uses antsRegistration to create a linear
affine (talairach.xfm and talairach.lta) and a nonlinear 
(talairach.m3z) warp to Talairach space.

Usage:
sh registerTalairach.sh -i [movable] -o [output directory] -r [registration stages] [-c]

Required arguments:
-i	input volume (to be registered to Talairach space, needs to be skullstripped).
-o	output directory (e.g. ${subject}/mri/transforms).

Optional arguments
-r	number of Talairach registration steps.
	1: source > Talairach, 
	2: source > chimpanzee > Talairach 
	3: source > macaque > chimpanzee > Talairach. 
	Default = 3.
-c	clean up intermediate files. Include this flag to remove some 
	intermediate files (saves disk space). Default: off.
-h 	display this help message.

For the two- and three-step registrations, pre-calculated warps can be
used (e.g. from chimpanzee to Talairach or from NMT to Talairach) to
save computational resources. The script will automatically skip these
steps if existing warps are found in the output directory. "

}

# Parse arguments
while getopts ":i:o:r:ch" opt; do
  case $opt in
    i) mov=${OPTARG};;
    o) OUTPUT_DIR=${OPTARG};;
    r) reg_stages=${OPTARG};;
    c) clean_up=1;;   
    h)
	  usage
	  exit 1
      ;;         
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  	:)
      echo "Option -$OPTARG requires an argument" >&2
      exit 1
      ;;
  esac
done

# Check that required parameters, paths, and folders are set
if ((OPTIND == 1))
then
    usage; exit 1
elif [ "x" == "x$mov" ]; then
  echo "-i [movable] input is required"
  exit 1
elif [ "x" == "x$OUTPUT_DIR" ]; then
  echo "-o [OUTPUT_DIR] is required"
  exit 1
elif ! [[ "${reg_stages}" =~ ^[0-9]+$ ]]; then
  echo "number of registration stages should be an integer"
  exit 1
elif [ "${reg_stages}" -lt 1 ] || [ "${reg_stages}" -gt 3 ]; then
  echo "number of registration stages should be 1, 2, or 3"
  exit 1  
elif [ "x" == "x$FREESURFER_HOME" ]; then
  echo "FREESURFER_HOME not set, make sure to source FreeSurfer"
  exit 1  
elif [ "x" == "x$(which antsRegistration)" ]; then
  echo "Could not find ANTs"
  exit 1
fi

echo "
Running registerTalairach with the following parameters:
- input volume: 			${mov}
- output directory: 			${OUTPUT_DIR}
- number of registration stages:	${reg_stages}"

if [[ clean_up -eq 1 ]]
then
	echo "- clean-up:				yes"
else
	echo "- clean-up:				no"
fi

# Registration functions
doRegister() {

	# Initialization
	antsRegistration -d 3 --float 1 -r [${trg}, ${mov} , 1] -t Rigid[0.1] \
	--winsorize-image-intensities [0.005, 0.995] \
	-m MI[${trg}, ${mov}, 1, 32] -c 0 -f 4 -s 2 \
	-o [${regBase}_init, ${regBase}_init.nii.gz] -v

	# Rigid registration. using the initialization
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--transform Rigid[0.1] \
	--metric MI[${trg},${regBase}_init.nii.gz,1,32,Regular,0.25] \
	--convergence [1000x500x250x100,1e-6,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_rigid, ${regBase}_rigid.nii.gz] \
	--v

	# Affine registration
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--transform Affine[0.1] \
	--metric MI[${trg},${regBase}_rigid.nii.gz,1,32,Regular,0.25] \
	--convergence [1000x500x250x100,1e-6,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output [${regBase}_affine, ${regBase}_affine.nii.gz] \
	--v

	# Combine all transforms so far to create an initial transform for the nonlinear registration
	antsApplyTransforms --dimensionality 3 \
	--input ${mov} --reference-image ${trg} \
	--output Linear[${regBase}_linear.mat] \
	--interpolation Linear \
	--transform ${regBase}_affine0GenericAffine.mat \
	--transform ${regBase}_rigid0GenericAffine.mat \
	--transform ${regBase}_init0GenericAffine.mat \
	--v

	# Nonlinear registration using affine as initial transform
	antsRegistration --dimensionality 3 --float 1 \
	--interpolation Linear \
	--winsorize-image-intensities [0.005, 0.995] \
	--use-histogram-matching 1 \
	--initial-moving-transform ${regBase}_linear.mat \
	--transform SyN[0.1,3,0] \
	--metric CC[${trg}, ${mov},1,4] \
	--convergence [100x70x50x20,1e-6,10] \
	--shrink-factors 8x4x2x1 \
	--smoothing-sigmas 3x2x1x0vox \
	--output ${regBase}_nonlinear \
	--v

	# Apply the transform
	antsApplyTransforms --dimensionality 3 --float 1 \
	--input ${mov} --reference-image ${trg} \
	--output [${regBase}.nii.gz, 1] \
	--interpolation Linear \
	--transform ${regBase}_nonlinear1Warp.nii.gz \
	--transform ${regBase}_nonlinear0GenericAffine.mat \
	--v

	# Check that the displacement field is correct
	antsApplyTransforms --dimensionality 3 --float 1 \
	--input ${mov} --reference-image ${trg} \
	--output ${regBase}_warped.nii.gz \
	--interpolation Linear \
	--transform ${regBase}.nii.gz \
	--v

}

register_one_step() {

	echo
	echo Starting one-step registration.
	echo

	# Register movable volume to talairach volume directly.
	# This may work well if both volumes have approximately the same size, resolution, and anatomy.
	echo
	echo Step 1:
	echo Registering movable volume to talairach volume.
	echo

	mov=${mov_nii}
	trg=${tal}
	regBase=${outBaseFinal}

	doRegister

	# Rename output files
	mv -v ${outBaseFinal}_nonlinear0GenericAffine.mat ${finalTransformLin}.mat
	mv -v ${outBaseFinal}_nonlinear1Warp.nii.gz ${finalTransformNonLin}.nii.gz

}

register_two_step() {

	echo
	echo Starting two-step registration.
	echo	

	# Step 1: register between movable and chimp template

	# Get sizes of the volumes
	mri_binarize --count size_mov.txt --i ${mov_nii} --min 0.001 
	mri_binarize --count size_chimp.txt --i ${chimp} --min 0.001 
	vol_mov=$(awk '{print $(NF-2)}' size_mov.txt)
	vol_chimp=$(awk '{print $(NF-2)}' size_chimp.txt)
	rm size_mov.txt
	rm size_chimp.txt

	if (( $(echo "${vol_chimp} > ${vol_mov}" | bc -l) )) # if chimp is larger than mov
	then

		echo
		echo Step 1:
		echo Registering movable volume to chimp template volume.
		echo

		mov=${mov_nii}
		trg=${chimp}
		outBase3="${mov%%.*}"_to_"${trg%%.*}"
		regBase=${outBase3}

		doRegister

	else

		echo
		echo Step 1:
		echo Registering chimp template to movable volume.
		echo

		# Swap mov and targ
		mov=${chimp}
		trg=${mov_nii}
		outBase3="${mov%%.*}"_to_"${trg%%.*}"
		regBase=${outBase3}

		doRegister

	fi

	# Check if registration from chimp to talairach already exists
	if [ ! -f ${outBase1}.nii.gz ] 
	then

		# Step 2: register chimp template to talairach
		echo
		echo Step 2:
		echo Registering chimp template to talairach.
		echo

		mov=${chimp}
		trg=${tal}
		regBase=${outBase1}

		doRegister

	else

		echo
		echo Step 2:
		echo Existing warps from chimp template to talairach found, skipping this registration step.
		echo

	fi	

	# Combine the transforms
	if (( $(echo "${vol_chimp} > ${vol_mov}" | bc -l) )) # if chimp template is larger than mov
	then

		echo
		echo Combining warp from mov to chimp and warp from chimp to talairach.
		echo

		# Movable is smaller than chimp
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${outBase1}.nii.gz \
		--transform ${outBase3}_nonlinear1Warp.nii.gz \
		--transform ${outBase3}_nonlinear0GenericAffine.mat \
		--v

		# Also combine the linear tranforms
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${outBase1}_nonlinear0GenericAffine.mat \
		--transform ${outBase3}_nonlinear0GenericAffine.mat \
		--v

	else

		echo
		echo Combining inverse warp from chimp to mov and warp from chimp to talairach.
		echo

		# Movable is larger than chimp
		# Invert the second transform here since we were going from chimp to movable
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${outBase1}.nii.gz \
		--transform [${outBase3}_nonlinear0GenericAffine.mat, 1] \
		--transform ${outBase3}_nonlinear1InverseWarp.nii.gz \
		--v

		# Also combine the linear tranforms
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${outBase1}_nonlinear0GenericAffine.mat \
		--transform [${outBase3}_nonlinear0GenericAffine.mat, 1] \
		--v

	fi

}

register_three_step() {

	echo
	echo Starting three-step registration.
	echo

	# Step 1: register between movable and NMT

	# Get sizes of the volumes
	mri_binarize --count size_mov.txt --i ${mov_nii} --min 0.001 
	mri_binarize --count size_nmt.txt --i ${nmt} --min 0.001 
	vol_mov=$(awk '{print $(NF-2)}' size_mov.txt)
	vol_nmt=$(awk '{print $(NF-2)}' size_nmt.txt)
	rm size_mov.txt
	rm size_nmt.txt

	if (( $(echo "${vol_nmt} > ${vol_mov}" | bc -l) )) # if nmt is larger than mov
	then

		echo
		echo Step 1:
		echo Registering movable volume to NMT volume.
		echo

		mov=${mov_nii}
		trg=${nmt}
		outBase3="${mov%%.*}"_to_"${trg%%.*}"
		regBase=${outBase3}

		doRegister

	else

		echo
		echo Step 1:
		echo Registering NMT to movable volume.
		echo

		# Swap mov and targ
		mov=${nmt}
		trg=${mov_nii}
		outBase3="${mov%%.*}"_to_"${trg%%.*}"
		regBase=${outBase3}

		doRegister

	fi

	# Check if registration from NMT to talairach already exists
	if [ ! -f ${outBase0}.nii.gz ] 
	then

		# Check if registration from nmt to chimp already exists
		if [ ! -f ${outBase2}.nii.gz ] 
		then

			# Step 2: register NMT template to chimp template
			echo
			echo Step 2:
			echo Registering NMT template to chimp template
			echo

			mov=${nmt}
			trg=${chimp}
			outBase2="${mov%%.*}"_to_"${trg%%.*}"
			regBase=${outBase2}

			doRegister

		else

			echo
			echo Step 2:
			echo Existing warps from NMT template to chimp template found, skipping this registration step.
			echo

		fi		

		# Check if registration from chimp to talairach already exists
		if [ ! -f ${outBase1}.nii.gz ] 
		then

			# Step 1: register chimp template to talairach
			echo
			echo Step 3:
			echo Registering chimp template to talairach
			echo

			mov=${chimp}
			trg=${tal}
			outBase1="${mov%%.*}"_to_"${trg%%.*}"
			regBase=${outBase1}

			doRegister
			
		else

			echo
			echo Step 3:
			echo Existing warps from chimp template to talairach found, skipping this registration step.
			echo

		fi

		echo
		echo Combining the transforms from NMT to chimp and from chimp to talairach.
		echo

		# Combine the transforms
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${nmt} --reference-image ${tal} \
		--output [${outBase0}_nonlinear1Warp.nii.gz, 1] \
		--interpolation Linear \
		--transform ${outBase2}_nonlinear1Warp.nii.gz \
		--transform ${outBase2}_nonlinear0GenericAffine.mat \
		--transform ${outBase1}_nonlinear1Warp.nii.gz \
		--transform ${outBase1}_nonlinear0GenericAffine.mat \
		--v

		# Also combine the linear transforms
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${nmt} --reference-image ${tal} \
		--output Linear[${outBase0}_nonlinear0GenericAffine.mat] \
		--interpolation Linear \
		--transform ${outBase2}_nonlinear0GenericAffine.mat \
		--transform ${outBase1}_nonlinear0GenericAffine.mat \
		--v

	else

		echo
		echo Steps 2-3:
		echo Existing warps from NMT template to talairach found, skipping these registration steps.
		echo

	fi

	# Combine the transforms
	if (( $(echo "${vol_nmt} > ${vol_mov}" | bc -l) )) # if NMT is larger than mov
	then

		echo
		echo Combining warp from mov to NMT and warp from NMT to talairach.
		echo

		# Movable is smaller than NMT
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${outBase0}.nii.gz \
		--transform ${outBase3}_nonlinear1Warp.nii.gz \
		--transform ${outBase3}_nonlinear0GenericAffine.mat \
		--v

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${outBase0}_nonlinear0GenericAffine.mat \
		--transform ${outBase3}_nonlinear0GenericAffine.mat \
		--v

	else

		echo
		echo Combining inverse warp from NMT to mov and warp from NMT to talairach
		echo
		
		# Movable is larger than NMT
		# Invert the second transform here since we were going from NMT to movable
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output [${finalTransformNonLin}.nii.gz, 1] \
		--interpolation Linear \
		--transform ${outBase0}.nii.gz \
		--transform [${outBase3}_nonlinear0GenericAffine.mat, 1] \
		--transform ${outBase3}_nonlinear1InverseWarp.nii.gz \
		--v

		# Also combine the linear tranform
		antsApplyTransforms --dimensionality 3 --float 1 \
		--input ${mov} --reference-image ${tal} \
		--output Linear[${finalTransformLin}.mat] \
		--interpolation Linear \
		--transform ${outBase0}_nonlinear0GenericAffine.mat \
		--transform [${outBase3}_nonlinear0GenericAffine.mat, 1] \
		--v

	fi

}

# Do the registrations
cd ${OUTPUT_DIR}
source ${FREESURFER_HOME}/startfreesurfer

# Prepare movable volume
mov_fname="${mov##*/}"
mov_nii="${mov_fname%%.*}".nii.gz
cp ${mov} ${mov_fname} # copy potential .mgz volume to OUTPUT_DIR
mri_convert ${mov} ${mov_nii} # convert movable volume to .nii.gz and place it in OUTPUT_DIR

# Prepare some variables
nmt=NMT_SS.nii.gz
chimp=chimp_template.nii.gz
tal=tal.nii.gz
outBase0="${nmt%%.*}"_to_"${tal%%.*}"
outBase1="${chimp%%.*}"_to_"${tal%%.*}"
outBase2="${nmt%%.*}"_to_"${chimp%%.*}"
outBaseFinal="${mov_nii%%.*}"_to_"${tal%%.*}"
finalTransformLin=talairach_linear
finalTransformNonLin=talairach_nonlinear

case ${reg_stages} in
	1) register_one_step ;;
	2) register_two_step ;;
	3) register_three_step ;;
esac

echo
echo Applying final warp to movable volume.
echo

# Check that the displacement field is correct for the final transform
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${mov_nii} --reference-image ${trg} \
--output ${outBaseFinal}_warped.nii.gz \
--interpolation Linear \
--transform ${finalTransformNonLin}.nii.gz \
--v

echo
echo Converting ANTs warps to FreeSurfer xfm, lta, and m3z formats.
echo

# Convert the warps to FS formats
cp ${finalTransformLin}.mat talairach.mat # save a copy for later use
convertTransformFile 3 talairach.mat talairach.txt
lta_convert --initk talairach.txt --outmni talairach.xfm --src ${mov_fname} --trg ${tal} # xfm
lta_convert --ltavox2vox --initk talairach.txt --outlta talairach.lta --src ${mov_fname} --trg $FREESURFER_HOME/average/RB_all_2016-05-10.vc700.gca # lta
mri_warp_convert --initk ${finalTransformNonLin}.nii.gz --outm3z talairach.m3z --insrcgeom ${mov_fname} # m3z

# Apply the transforms to check accuracy of transforms
# Linear transform
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${mov_nii} --reference-image ${tal} \
--output "${mov_nii%%.*}"_to_"${tal%%.*}"_linear.nii.gz \
--interpolation Linear \
--transform ${finalTransformLin}.mat \
--v

# Nonlinear transform
mri_convert ${mov_nii} \
--apply_transform talairach.m3z \
-oc 0 0 0 \
"${mov_nii%%.*}"_to_"${tal%%.*}"_nonlinear.nii.gz

# Optional: clean up intermediate files
if [ "${clean_up}" -eq 1 ]
then

	echo Removed:
	rm -v ${outBase0}*
	rm -v ${outBase1}*
	rm -v ${outBase2}*
	rm -v ${outBase3}*
	rm -v {finalTransformLin}*
	rm -v {finalTransformNonLin}*	

fi

echo
echo registerTalairach done.
echo

exit 0
