# nhp-freesurfer
Collection of scripts based on FreeSurfer for cortical reconstruction of small non-human primate brains.

## Requirements:
* FreeSurfer 6.0
* FSL 6.0 (included with FreeSurfer 6.0)
* MATLAB
* [ANTs](https://github.com/ANTsX/ANTs)

## Additional FreeSurfer requirements:
* [Patches](https://surfer.nmr.mgh.harvard.edu/fswiki/BrainVolStatsFixed) for mri_segstats and mris_anatomical stats that fix a bug where volumetrics are not computed correctly in volumes that don't have 1 mm voxel sizes. Copy these patched binaries into $FREESURFER_HOME/bin and remove the .mac extension.
* [recon-all.v6.hires](https://github.com/freesurfer/freesurfer/blob/d26114a201333f812d2cef67a338e2685c004d00/scripts/recon-all.v6.hires), a modification of the v6.0 recon-all pipeline to better handle high-resolution files. Copy these files into $FREESURFER_HOME/bin.

## How to use these scripts to process your own primate MRI data:
* Download and install the software requirements according to their respective instructions
* Download the additional FreeSurfer requirements and place them inside $FREESURFER_HOME/bin
* Download the nhp-freesurfer repository and save to a folder of choice
* In a terminal window, specify the following paths:
```
export FREESURFER_HOME=/path/to/your/FreeSurfer/installation
export SUBJECTS_DIR=/path/to/desired/FreeSurfer/output
export SHARED_DIR=/path/to/nhp-freesurfer/shared
export SCRIPTS_DIR=/path/to/nhp-freesurfer/freesurfer
```
* Then, do a first run to create a skullstripped input file and several segmentations that will likely need some manual edits. These steps are described in the createManualEditFiles.sh script (if you already have these files, put them in a folder called 'manual_edits' in SUBJECTS_DIR and skip this step)
* Finally, run the main script:
`sh runFreeSurferMonkey.sh -s [subjectname] -d [downsamplingfactor]`
A downsampling factor of 2 or 3 should work well for high-resolution data of smaller primate brains (from macaque-size to galago-size). For (much) larger brains, this downsampling factor may not be necessary, and the default number of Talairach registration steps should be changed from 3 to 2 (for a chimpanzee-sized brain) or 1 (for a human-sized brain). Use the -h flag to see more help information.

The scripts have been tested on MacOS 10.14 (Mojave) with FreeSurfer 6.0. Other versions of MacOS should work if they support 32-bit binaries, other versions of FreeSurfer will likely not work.