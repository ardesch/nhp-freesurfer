#!/bin/bash

# === createManualEditFiles ===
# A set of commands to create some segmentations to be manually edited:
# - aseg.auto_noCCseg.mgz
# - aseg.presurf.mgz
# - wm.asegedit.mgz
# - filled.mgz

# This script assumes the following paths are set in the environment:
# FREESURFER_HOME:	FreeSurfer home directory
# SUBJECTS_DIR:     directory where the FreeSurfer output will be saved.
# SHARED_DIR:       directory where shared files are stored (e.g. transforms).
# SCRIPTS_DIR:      directory where the additional scripts are located.

# In addition, it assumes that a skullstripped T1-like structural image called inputT1.mgz is
# present in ${manual_edits}}.

# How to use:
# First set the required paths as environment variables in a terminal window (e.g. 'export SUBJECTS_DIR=path/to/subjects/dir').
# Then run each section of the script separately by copy/pasting the corresponding commands into the terminal window.
# After each code section, check the resulting segmentations in the manual_edits folder and edit where necessary before continuing.
# After running this script, all prerequisite segmentations should be present to run the runFreeSurferMonkey.sh script. The 
# FreeSurfer output directory created during createManualEditFiles.sh can then be deleted.

# Some default parameters (update where relevant)
subject=my_subject
reg_stages=3 # three-step registration by default
manual_edits=${SUBJECTS_DIR}/manual_edits

#####################
##### SECTION 1 #####
#####################

# Set up FreeSurfer
source $FREESURFER_HOME/SetUpFreeSurfer.sh
cd ${SUBJECTS_DIR}

# Autorecon1
recon-all -i ${manual_edits}/inputT1.mgz -s ${subject} -motioncor -hires
cp -rv ${SHARED_DIR}/transforms/* ${subject}/mri/transforms/
sh ${SCRIPTS_DIR}/registerTalairach.sh \
-i ${SUBJECTS_DIR}/${subject}/mri/orig.mgz \
-o ${SUBJECTS_DIR}/${subject}/mri/transforms \
-r ${reg_stages} -c 2>&1 | tee ${SUBJECTS_DIR}/${subject}/mri/transforms/registerTalairach.log
recon-all -s ${subject} -nuintensitycor -normalization
cp ${subject}/mri/T1.mgz ${subject}/mri/brainmask.mgz # copy brainmask

# Autorecon2
recon-all -s ${subject} -canorm -calabel -normalization2 -maskbfs -segmentation -fill

# Edit these files in the manual_edits folder and save them without the _tmp addition.
cp ${subject}/mri/aseg.presurf.mgz ${manual_edits}/aseg.presurf_tmp.mgz
cp ${subject}/mri/aseg.auto_noCCseg.mgz ${manual_edits}/aseg.auto_noCCseg_tmp.mgz
cp ${subject}/mri/wm.asegedit.mgz ${manual_edits}wm.asegedit_tmp.mgz
cp ${subject}/mri/wm.asegedit.mgz ${manual_edits}/wm.asegedit_orig.mgz # STILL NECESSARY?
echo "Check _tmp.mgz files in ${manual_edits}, correct them where necessary and save without _tmp"

#####################
##### SECTION 2 #####
#####################

# Continue processing
cp ${manual_edits}/wm.asegedit.mgz ${subject}/mri/wm.asegedit.mgz # copy edited version back to continue

# Then, recreate the filled.mgz volume
mri_pretess ${subject}/mri/wm.asegedit.mgz wm ${subject}/mri/norm.mgz ${subject}/mri/wm.mgz
recon-all -s ${subject} -fill
cp ${subject}/mri/filled.mgz ${manual_edits}/filled.mgz

# also fill brainmask
cp ${subject}/mri/brainmask.mgz ${subject}/mri/wm.mgz
recon-all -s ${subject} -fill
cp ${subject}/mri/filled.mgz ${manual_edits}/brain_filled_tmp.mgz # edit such that cerebellum, brainstem, and 4th ventricle have intensity 231 (or 999 when editing in uchar), save as brain_filled.mgz
echo "Edit ${manual_edits}/brain_filled_tmp.mgz such that cerebellum, brainstem, and 4th ventricle have intensity 231 (or 999 in uchar), and save without _tmp"

#####################
##### SECTION 3 #####
#####################

# Then, use the brain_filled.mgz and filled.mgz to automatically edit the aseg volumes.
cd ${SCRIPTS_DIR}
matlab -nodisplay -nosplash -r "try, editAseg('${manual_edits}/aseg.presurf.mgz', \
'${manual_edits}/brain_filled.mgz', \
'${manual_edits}/filled.mgz', \
'${manual_edits}'), catch, end, quit" # refine aseg
cd ${SUBJECTS_DIR}

# Finally, warp the volumes back to native space (i.e. the same as inputT1.mgz)
ims=(wm.asegedit filled aseg.auto_noCCseg aseg.presurf)
cd ${manual_edits}

for im in ${ims[@]}
do

  mri_label2vol --seg ${im}.mgz --temp ${SUBJECTS_DIR}/${subject}/mri/rawavg.mgz --o ${im}-in-rawavg.mgz --regheader ${im}.mgz

done

echo "Check -in-rawavg.mgz files in ${manual_edits}, confirm that they are in the same space as the original input image, and save without -in-rawavg."

#####################
### END OF SCRIPT ###
#####################