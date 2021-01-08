#!/bin/bash

# Some default parameters
version=10
clean_up=0 # don't clean up by default
ds_factor=1 # don't downsample by default
reg_stages=3 # three-step registration by default
targ_vox_size=1 # target voxel size equals 1
manual_edits=${SUBJECTS_DIR}/manual_edits
LF=${SUBJECTS_DIR}/tmp.log

# Help message
usage () { 
echo "
=== runFreeSurferMonkey version ${version} ===
Attempts to run FreeSurfer on small monkey brain data.
Usage:
sh runFreeSurferMonkey.sh -s [subject] -d [downsampling factor] -r [registration stages] [-c]
Required arguments:
-s      subject name given to the FreeSurfer output directory.
-d      downsampling factor applied to the original volume during pial surface reconstruction
        (this won't affect the final image resolution). Default = 1.
Optional arguments
-r      number of Talairach registration steps. 
        1: source > Talairach, 
        2: source > chimpanzee > Talairach,
        3: source > macaque > chimpanzee > Talairach. 
        Default = 3.
-m      path pointing to the folder containing manual segmentations and input files
        (by default assumed to be $SUBJECTS_DIR/manual_edits).
-c      clean up intermediate files. Include this flag to remove some intermediate files 
        (saves disk space). Default: off.
This script assumes the following paths are set in the environment:
SUBJECTS_DIR:     directory where the FreeSurfer output will be saved.
SHARED_DIR:       directory where shared files are stored (e.g. transforms).
SCRIPTS_DIR:      directory where the additional scripts are located.
"
}

# Parse arguments
while getopts ":s:d:r:m:ch" opt; do
  case $opt in
    s) subject=${OPTARG};;
    d) ds_factor=${OPTARG};;
    r) reg_stages=${OPTARG};;
    m) manual_edits=${OPTARG};;       
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
elif [ "x" == "x$subject" ]; then
  echo "-s [subject] is required"
  exit 1
elif ! [[ "${reg_stages}" =~ ^[0-9]+$ ]]; then
  echo "number of registration stages should be an integer"
  exit 1
elif [ "${reg_stages}" -lt 1 ] || [ "${reg_stages}" -gt 3 ]; then
  echo "number of registration stages should be 1, 2, or 3"
  exit 1
elif ! [ -d "${manual_edits}" ]; then
  echo "could not find ${manual_edits}"
  exit 1    
elif [ "x" == "x$SUBJECTS_DIR" ]; then
  echo "SUBJECTS_DIR not set, make sure to source FreeSurfer"
  exit 1
elif [ "x" == "x$FREESURFER_HOME" ]; then
  echo "FREESURFER_HOME not set, make sure to source FreeSurfer"
  exit 1
elif [ "x" == "x$SHARED_DIR" ]; then
  echo "SHARED_DIR not set"
  exit 1
elif [ "x" == "x$SCRIPTS_DIR" ]; then
  echo "SCRIPTS_DIR not set"
  exit 1
elif [ "x" == "x$(which antsRegistration)" ]; then
  echo "Could not find ANTs"
  exit 1
fi

echo "
###########################################
### FREESURFER HIGH-RESOLUTION PIPELINE ###
###  FOR MONKEY SURFACE RECONSTRUCTION  ###
###                 V1.${version}               ###
###########################################
" >> ${LF}

echo Script: $0 >> ${LF}
echo Subject: ${subject} >> ${LF}
echo SUBJECTS_DIR: ${SUBJECTS_DIR} >> ${LF}
echo Downsampling factor: ${ds_factor} >> ${LF}
echo Number of registration stages: ${reg_stages} >> ${LF}
echo Target voxel size: ${targ_vox_size} mm >> ${LF}
echo >> ${LF}
date >> ${LF}
uname -a >> ${LF}

echo "
###########################################
###     STEP 1: PREPARE INPUT FILES     ###
###########################################
" >> ${LF}

echo "Copy hires input volume and set voxel size to ${targ_vox_size} mm divided by downsampling factor." >> ${LF}
echo >> ${LF}

cd ${SUBJECTS_DIR}
hires_vox_size=$(bc -l <<< "${targ_vox_size} / ${ds_factor}")
hires_vox_size=$(printf "%.2f\n" ${hires_vox_size})
mkdir -v ${manual_edits}/hires >> ${LF}

cd ${SCRIPTS_DIR}
matlab -nodisplay -nosplash -r "try, changeVoxelSize('${manual_edits}', \
{'inputT1.mgz', 'aseg.presurf.mgz', 'aseg.auto_noCCseg.mgz', 'wm.asegedit.mgz', 'filled.mgz'}, \
'${manual_edits}/hires', ${hires_vox_size}), catch, end, quit"
echo "Changed voxel size in header of images in ${manual_edits}/hires to ${hires_vox_size} mm." >> ${LF}


echo "
###########################################
###  STEP 2: FS HIRES UNTIL PIAL SURFS  ###
###########################################
" >> ${LF}

# Freesurfer autorecon1 stage
cd ${SUBJECTS_DIR}
source ${FREESURFER_HOME}/SetUpFreeSurfer.sh

recon-all -s ${subject} -i ${manual_edits}/hires/inputT1.mgz -motioncor -hires

# Add the previous log messages to recon-all.log
cat ${subject}/scripts/recon-all.log >> ${LF}
mv ${LF} ${subject}/scripts/recon-all.log
LF=${subject}/scripts/recon-all.log

# Get original volume in FreeSurfer space
recon-all -s ${subject}_tmp -i ${manual_edits}/inputT1.mgz -motioncor -hires 2>&1 | tee -a ${LF}
mri_convert ${subject}_tmp/mri/orig.mgz ${subject}/mri/orig_native.nii.gz 2>&1 | tee -a ${LF}

echo >> ${LF}
echo "Removing ${subject}_tmp:" >> ${LF}
rm -v -r ${subject}_tmp 2>&1 | tee -a ${LF}
echo >> ${LF}

# Get warp from fake-header hires space to native space with FSL
mri_convert ${subject}/mri/orig.mgz ${subject}/mri/orig.nii.gz 2>&1 | tee -a ${LF}
flirt -in ${subject}/mri/orig_native.nii.gz -ref ${subject}/mri/orig.nii.gz \
-omat ${subject}/mri/transforms/native2hires.mat -dof 7 -v 2>&1 | tee -a ${LF}
convert_xfm -omat ${subject}/mri/transforms/hires2native.mat \
-inverse ${subject}/mri/transforms/native2hires.mat 2>&1 | tee -a ${LF}
lta_convert --infsl ${subject}/mri/transforms/hires2native.mat --outreg ${subject}/mri/transforms/hires2native.dat \
--src ${subject}/mri/orig.nii.gz --trg ${subject}/mri/orig_native.nii.gz 2>&1 | tee -a ${LF}
lta_convert --infsl ${subject}/mri/transforms/native2hires.mat --outreg ${subject}/mri/transforms/native2hires.dat \
--src ${subject}/mri/orig_native.nii.gz --trg ${subject}/mri/orig.nii.gz 2>&1 | tee -a ${LF}

# Get warp from fake-header hires space to native space with ANTs
antsRegistration --dimensionality 3 --float 1 \
    --output [${subject}/mri/transforms/hires2native_ANTs,] \
    --interpolation Linear \
    --winsorize-image-intensities [0.005,0.995] \
    --use-histogram-matching 1 \
    --initial-moving-transform [${subject}/mri/orig.nii.gz, ${subject}/mri/orig_native.nii.gz,1] \
    --transform Rigid[0.1] \
    --metric MI[${subject}/mri/orig.nii.gz, ${subject}/mri/orig_native.nii.gz,1,32,Regular,0.25] \
    --convergence [1000x500x250x100,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
    --transform Affine[0.1] \
    --metric MI[${subject}/mri/orig.nii.gz, ${subject}/mri/orig_native.nii.gz,1,32,Regular,0.25] \
    --convergence [1000x500x250x100,1e-6,10] \
    --shrink-factors 8x4x2x1 \
    --smoothing-sigmas 3x2x1x0vox \
    --v 2>&1 | tee -a ${LF}

mv -v ${subject}/mri/transforms/hires2native_ANTs0GenericAffine.mat ${subject}/mri/transforms/hires2native_ANTs.mat 2>&1 | tee -a ${LF}

# Register to talairach
cp -v ${SHARED_DIR}/transforms/* ${subject}/mri/transforms/ 2>&1 | tee -a ${LF}

if [[ "${clean_up}" -eq 1 ]]
then
  echo >> ${LF}
  echo "Registering to talairach with ${reg_stages} steps, cleaning up output..." >> ${LF}
  echo >> ${LF}
  sh ${SCRIPTS_DIR}/registerTalairach.sh -i ${SUBJECTS_DIR}/${subject}/mri/orig.mgz -o ${SUBJECTS_DIR}/${subject}/mri/transforms \
  -r ${reg_stages} -c 2>&1 | tee ${subject}/mri/transforms/registerTalairach.log
else
  echo >> ${LF}
  echo "Registering to talairach with ${reg_stages} steps, saving output..." >> ${LF}
  echo >> ${LF}
  sh ${SCRIPTS_DIR}/registerTalairach.sh -i ${SUBJECTS_DIR}/${subject}/mri/orig.mgz -o ${SUBJECTS_DIR}/${subject}/mri/transforms \
  -r ${reg_stages} 2>&1 | tee ${subject}/mri/transforms/registerTalairach.log
fi 

# Continue recon-all
recon-all -s ${subject} -nuintensitycor -normalization

cp -v ${subject}/mri/T1.mgz ${subject}/mri/brainmask.mgz 2>&1 | tee -a ${LF}
recon-all -s ${subject} -canorm -calabel

# Warp to hires space
mri_vol2vol --mov ${manual_edits}/hires/aseg.presurf.mgz --targ ${subject}/mri/orig.mgz \
--o ${subject}/mri/aseg.presurf.mgz --regheader --interp nearest 2>&1 | tee -a ${LF}
mri_vol2vol --mov ${manual_edits}/hires/aseg.auto_noCCseg.mgz --targ ${subject}/mri/orig.mgz \
--o ${subject}/mri/aseg.auto_noCCseg.mgz --regheader --interp nearest 2>&1 | tee -a ${LF}

# Continue recon-all
recon-all -s ${subject} -normalization2 -maskbfs 

# Warp white matter segmentation to hires space
mri_vol2vol --mov ${manual_edits}/hires/wm.asegedit.mgz --targ ${subject}/mri/orig.mgz \
--o ${subject}/mri/wm.asegedit.mgz --regheader --interp nearest 2>&1 | tee -a ${LF}
mri_pretess ${subject}/mri/wm.asegedit.mgz wm ${subject}/mri/norm.mgz ${subject}/mri/wm.mgz 2>&1 | tee -a ${LF}
mri_vol2vol --mov ${manual_edits}/hires/filled.mgz --targ ${subject}/mri/orig.mgz \
--o ${subject}/mri/filled.mgz --regheader --interp nearest 2>&1 | tee -a ${LF}

# Start of surface reconstruction
recon-all -s ${subject} -tessellate -smooth1 -inflate1 -qsphere -fix -use-new-fixer -white -smooth2 

# Backup ?h.white.preaparc
echo >> ${LF}
mv -v ${subject}/surf/lh.white.preaparc ${subject}/surf/lh.white.preaparc_old 2>&1 | tee -a ${LF}
mv -v ${subject}/surf/rh.white.preaparc ${subject}/surf/rh.white.preaparc_old 2>&1 | tee -a ${LF}

# Copy smoothwm into white.preaparc
cp -v ${subject}/surf/lh.smoothwm ${subject}/surf/lh.white.preaparc 2>&1 | tee -a ${LF}
cp -v ${subject}/surf/rh.smoothwm ${subject}/surf/rh.white.preaparc 2>&1 | tee -a ${LF}
echo >> ${LF}

# Finish autorecon2 and start autorecon3
recon-all -s ${subject} -inflate2 -curvHK -curvstats -sphere -surfreg -jacobian_white -avgcurv -cortparc

echo "
###########################################
###        STEP 3: FS CONF2HIRES        ###
###########################################
" >> ${LF}

# Downsample inputT1_hires so that the voxel size becomes the target voxel size, and use as 'fake' rawavg.mgz.
mv -v ${subject}/mri/rawavg.mgz ${subject}/mri/rawavg_bak.mgz 2>&1 | tee -a ${LF}
mri_convert ${manual_edits}/hires/inputT1.mgz -ds ${ds_factor} ${ds_factor} ${ds_factor} \
--conform ${subject}/mri/rawavg.mgz 2>&1 | tee -a ${LF}

recon-all.v6.hires -s ${subject} -conf2hires

# Remove the symlinks created by conf2hires (not used)
echo >> ${LF}
echo "Removed:" >> ${LF}
rm -v ${subject}/surf/lh.white 2>&1 | tee -a ${LF}
rm -v ${subject}/surf/rh.white 2>&1 | tee -a ${LF}
rm -v ${subject}/surf/lh.pial 2>&1 | tee -a ${LF}
rm -v ${subject}/surf/rh.pial 2>&1 | tee -a ${LF}
echo >> ${LF}

# Smooth the final surfaces
mris_smooth -n 3 ${subject}/surf/lh.white.rawavg ${subject}/surf/lh.white 2>&1 | tee -a ${LF}
mris_smooth -n 3 ${subject}/surf/rh.white.rawavg ${subject}/surf/rh.white 2>&1 | tee -a ${LF}
mris_smooth -n 3 ${subject}/surf/lh.pial.rawavg ${subject}/surf/lh.pial 2>&1 | tee -a ${LF}
mris_smooth -n 3 ${subject}/surf/rh.pial.rawavg ${subject}/surf/rh.pial 2>&1 | tee -a ${LF}

# Clean up
echo >> ${LF}
mv -v ${subject}/mri/rawavg_bak.mgz ${subject}/mri/rawavg.mgz 2>&1 | tee -a ${LF}
echo >> ${LF}
echo "Removed:" >> ${LF}
rm -v ${subject}/mri/rawavg.*.mgz 2>&1 | tee -a ${LF} # remove some unused output from conf2hires
echo >> ${LF}

echo "
###########################################
###     STEP 4: RESTORE VOXEL SIZE      ###
###########################################
" >> ${LF}

# Backup intermediate files
echo >> ${LF}
echo "Back up FreeSurfer reconstruction in fake header space." >> ${LF}
echo >> ${LF}

mkdir -v ${subject}_fakehdr 2>&1 | tee -a ${LF}
mv -v ${subject}/label ${subject}/mri ${subject}/stats ${subject}/surf ${subject}/tmp ${subject}/touch ${subject}/trash \
${subject}_fakehdr/ 2>&1 | tee -a ${LF} # move most folders over to ${subject}_fakeheader
mkdir -v ${subject}/label ${subject}/mri ${subject}/mri/transforms ${subject}/stats ${subject}/surf ${subject}/tmp ${subject}/touch ${subject}/trash \
2>&1 | tee -a ${LF} # recreate the moved folders
cp -rv ${subject}/scripts ${subject}_fakehdr 2>&1 | tee -a ${LF} # except the scripts folder, copy this one

# Copy back some files that will be needed later
cp -v ${subject}_fakehdr/mri/transforms/hires2native* ${subject}/mri/transforms/ 2>&1 | tee -a ${LF}
cp -v ${subject}_fakehdr/mri/transforms/native2hires* ${subject}/mri/transforms/ 2>&1 | tee -a ${LF}
cp -v ${subject}_fakehdr/mri/orig_native.nii.gz ${subject}/mri/ 2>&1 | tee -a ${LF}
cp -v ${subject}_fakehdr/label/*h.cortex.label ${subject}/label/ 2>&1 | tee -a ${LF}
cp -v ${subject}_fakehdr/mri/aseg.auto_noCCseg.label_intensities.txt ${subject}/mri/ 2>&1 | tee -a ${LF}
mri_convert ${subject}_fakehdr/mri/orig_native.nii.gz ${subject}/mri/orig.mgz 2>&1 | tee -a ${LF}
surfs=(sphere sphere.reg qsphere.nofix curv curv.pial thickness area area.mid area.pial volume)
hemispheres=(lh rh)
for surf in ${surfs[@]}
do
	
  for hemi in ${hemispheres[@]}
	do
		
    cp -v ${subject}_fakehdr/surf/${hemi}.${surf} ${subject}/surf/${hemi}.${surf} 2>&1 | tee -a ${LF}
	
  done

done

echo >> ${LF}
echo "Warp volumes back to original space." >> ${LF}

# Warp volumes to original voxel size and coordinates
vols=(rawavg nu T1 brainmask norm brain brain.finalsurfs)
for vol in ${vols[@]}
do

	mri_vol2vol --targ ${subject}/mri/orig.mgz \
	--mov ${subject}_fakehdr/mri/${vol}.mgz \
	--o ${subject}/mri/${vol}.mgz \
	--reg ${subject}/mri/transforms/hires2native.dat 2>&1 | tee -a ${LF}

done

segs=(aseg.auto_noCCseg aseg.auto aseg.presurf wm.asegedit wm filled ctrl_pts)
for seg in ${segs[@]}
do

	mri_vol2vol --targ ${subject}/mri/orig.mgz \
	--mov ${subject}_fakehdr/mri/${seg}.mgz \
	--o ${subject}/mri/${seg}.mgz \
	--reg ${subject}/mri/transforms/hires2native.dat \
	--nearest 2>&1 | tee -a ${LF}

done

echo >> ${LF}
echo "Warp surfaces back to original space." >> ${LF}
echo >> ${LF}

# Warp surfaces to original voxel size and coordinates
surfs=(orig inflated white.preaparc smoothwm inflated pial white sphere)
for surf in ${surfs[@]}
do
	for hemi in ${hemispheres[@]}
	do
    cp -v ${subject}_fakehdr/surf/${hemi}.${surf} ${subject}/surf/${hemi}.${surf}_old 2>&1 | tee -a ${LF}
    mri_surf2surf --sval-xyz ${surf}_old --reg ${subject}/mri/transforms/native2hires.dat ${subject}/mri/orig.mgz \
    --tval ${hemi}.${surf} --tval-xyz ${subject}/mri/orig.mgz --hemi ${hemi} --s ${subject} 2>&1 | tee -a ${LF}
    echo "Removed:" >> ${LF}
    rm -v ${subject}/surf/${hemi}.${surf}_old 2>&1 | tee -a ${LF}
    echo >> ${LF}
 done
done

nofixsurfs=(qsphere orig.nofix smoothwm.nofix inflated.nofix)
for surf in ${nofixsurfs[@]}
do
	for hemi in ${hemispheres[@]}
	do
		# use qsphere.nofix to warp the .nofix surfaces
    cp -v ${subject}_fakehdr/surf/${hemi}.${surf} ${subject}/surf/${hemi}.${surf}_old 2>&1 | tee -a ${LF}
    mri_surf2surf --sval-xyz ${surf}_old --reg ${subject}/mri/transforms/native2hires.dat ${subject}/mri/orig.mgz \
    --tval ${hemi}.${surf} --tval-xyz ${subject}/mri/orig.mgz --hemi ${hemi} --s ${subject} \
    --surfreg qsphere.nofix 2>&1 | tee -a ${LF}
    echo "Removed:" >> ${LF}
    rm -v ${subject}/surf/${hemi}.${surf}_old 2>&1 | tee -a ${LF}
    echo >> ${LF}	done
  done
done

# And finally do qsphere.nofix itself
for hemi in ${hemispheres[@]}
do
  mv -v ${subject}/surf/${hemi}.qsphere.nofix ${subject}/surf/${hemi}.qsphere.nofix_old 2>&1 | tee -a ${LF}
  mri_surf2surf --sval-xyz qsphere.nofix_old --reg ${subject}/mri/transforms/native2hires.dat ${subject}/mri/orig.mgz \
  --tval ${hemi}.qsphere.nofix --tval-xyz ${subject}/mri/orig.mgz --hemi ${hemi} --s ${subject} \
  --surfreg qsphere.nofix_old 2>&1 | tee -a ${LF}
  echo >> ${LF}
  echo "Removed:" >> ${LF}
  rm -v ${subject}/surf/${hemi}.sphere 2>&1 | tee -a ${LF} # don't need ?h.sphere, will recreate later
  rm -v ${subject}/surf/${hemi}.qsphere.nofix_old 2>&1 | tee -a ${LF}
  echo >> ${LF}
done

echo "Warp annotations back to original space." >> ${LF}
echo >> ${LF}

# Convert ?h.curv, ?h.curv.pial, ?h.thickness, ?h.area, ?h.area.mid, ?h.area.pial, ?h.volume to native voxel size
cd ${SCRIPTS_DIR}
matlab -nodisplay -nosplash -r "try, rescaleAnnotations('${SUBJECTS_DIR}', '${subject}', \
'${SUBJECTS_DIR}/${subject}/mri/orig_native.nii.gz', '${SUBJECTS_DIR}/${subject}_fakehdr/mri/orig.mgz'), \
catch, end, quit"
cd ${SUBJECTS_DIR}

echo >> ${LF}
echo "Warp Talairach transforms back to original space." >> ${LF}
echo >> ${LF}

# Concatenate original talairach transform with the transform from native to fake voxel size
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${subject}/mri/orig_native.nii.gz --reference-image ${SHARED_DIR}/transforms/tal.nii.gz \
--output Linear[${subject}/mri/transforms/talairach.mat] \
--interpolation Linear \
--transform ${subject}_fakehdr/mri/transforms/talairach.mat \
--transform ${subject}/mri/transforms/hires2native_ANTs.mat \
--v 2>&1 | tee -a ${LF}

convertTransformFile 3 ${subject}/mri/transforms/talairach.mat ${subject}/mri/transforms/talairach.txt 2>&1 | tee -a ${LF}
lta_convert --initk ${subject}/mri/transforms/talairach.txt --outmni ${subject}/mri/transforms/talairach.xfm \
--src ${subject}/mri/orig.mgz --trg ${SHARED_DIR}/transforms/tal.nii.gz 2>&1 | tee -a ${LF} # xfm
lta_convert --ltavox2vox --initk ${subject}/mri/transforms/talairach.txt --outlta ${subject}/mri/transforms/talairach.lta \
--src ${subject}/mri/orig.mgz --trg $FREESURFER_HOME/average/RB_all_2016-05-10.vc700.gca 2>&1 | tee -a ${LF} # lta

# Combine with the nonlinear talairach transform
mv ${subject}/mri/transforms/talairach_nonlinear.nii.gz ${subject}/mri/transforms/talairach_nonlinear_old.nii.gz 2>&1 | tee -a ${LF}
antsApplyTransforms --dimensionality 3 --float 1 \
--input ${subject}_fakehdr/mri/orig_native.nii.gz \
--reference-image ${SHARED_DIR}/transforms/tal.nii.gz \
--output [${subject}/mri/transforms/talairach_nonlinear.nii.gz, 1] \
--interpolation Linear \
--transform ${subject}_fakehdr/mri/transforms/talairach_nonlinear.nii.gz \
--transform ${subject}/mri/transforms/hires2native_ANTs.mat \
--v 2>&1 | tee -a ${LF}

# Convert nonlinear warp to .m3z format
mri_warp_convert --initk ${subject}/mri/transforms/talairach_nonlinear.nii.gz \
--outm3z ${subject}/mri/transforms/talairach.m3z \
--insrcgeom ${subject}/mri/orig.mgz 2>&1 | tee -a ${LF}

echo >> ${LF}
echo Restored voxel size. >> ${LF}

echo "
###########################################
###      STEP 5: FINISH RECON-ALL       ###
###########################################
" >> ${LF}

# Recreate some files from autorecon2 based on the new voxel dimensions
recon-all -s ${subject} -smooth2 -inflate2 -curvHK -curvstats

# Rest of autorecon3
recon-all -s ${subject} -autorecon3 -nopial # skip pial because it is already created

# Clean up
if [[ "${clean_up}" -eq 1 ]]
then
	echo "Cleaning up..." >> ${LF}
	echo "Removed:" >> ${LF}
	rm -v -r ${manual_edits}/hires 2>&1 | tee -a ${LF}
	rm -v -r ${subject}_fakehdr 2>&1 | tee -a ${LF}
	echo >> ${LF}
fi

awk -v t=$SECONDS 'BEGIN{t=int(t*1000); printf "Total processing time: %02d h %02d min %02d s.\n", t/3600000, t/60000%60, t/1000%60}' 2>&1 | tee -a ${LF}

echo "
###########################################
### FREESURFER RECONSTRUCTION FINISHED! ###
###  CHECK RECON-ALL.LOG AND THE FINAL  ###
###         SURFACES FOR ERRORS         ###
###########################################
" 2>&1 | tee -a ${LF}

exit 0