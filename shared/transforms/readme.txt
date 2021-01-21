Sources:

tal.nii.gz: 
mri_convert $FREESURFER_HOME/subjects/cvs_avg35_inMNI152/mri/brainmask.mgz \
--apply_transform $FREESURFER_HOME/subjects/cvs_avg35_inMNI152/mri/transforms/talairach.m3z -oc 0 0 0 talairach_volume.mgz
mri_convert talairach_volume.mgz talairach_volume.nii.gz

NMT_SS.nii.gz: 
Macaque template brain from NMT_v1.3 (https://github.com/jms290/NMT)
Seidlitz, J., Sponheim, C., Glen, D., Ye, F.Q., Saleem, K.S., Leopold, D.A., Ungerleider, L., Messinger, A. A population MRI brain template and analysis tools for the macaque. NeuroImage (2017). doi: 10.1101/105874)

chimp_template.nii.gz:
Template brain made with ANTs based on 65 chimpanzees from the National Chimpanzee Brain Resource (chimpanzeebrain.org)

All registrations were computed using ANTs (https://github.com/ANTsX/ANTs)