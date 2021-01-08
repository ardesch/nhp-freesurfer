function changeVoxelSize(inputDir, volumes, outputDir, size)
%CHANGEVOXELSIZE    Change the voxel size in the header of an MRI volume.
%
%   CHANGEVOXELSIZE(inputDir, volumes, outputDir, s) loads each volume in
%   volumes from inputDir, sets the isotropic voxel size to s, and saves
%   the output to outputDir.
%
%   Input arguments:
%   inputDir            path pointing to a directory containing the volumes to
%                       operate on [string]
%   volumes             volumes to change the voxel size of (without extension)
%                       [cell array of strings]
%   outputDir           path pointing to a directory to save the ouput
%                       volume(s) to [string]
%   size                desired voxel size [float]
%
%   Dirk Jan Ardesch, VU Amsterdam

for i = 1:length(volumes)

	filePath = strcat(inputDir, '/', volumes{i});
	outPath = strcat(outputDir, '/', volumes{i});

	% Check filetype
	assert(contains(filePath, {'.nii.gz', '.nii', '.mgz'}), ...
    '%s: Image file format not recognized. Must be .nii, .nii.gz, or .mgz', ...
    filePath);

	im = MRIread(filePath);

	% Check that voxels are isotropic
	assert(length(unique(im.volres)) == 1, ...
	'%s: Voxel size must be isotropic', filePath);

	origsize = im.volres(1);

	% Change header
	im.vox2ras0(1:3, 1:4) = im.vox2ras0(1:3, 1:4) .* (size/origsize);
	im.vox2ras(1:3, 1:4) = im.vox2ras(1:3, 1:4) .* (size/origsize);
	im.vox2ras1(1:3, 1:4) = im.vox2ras1(1:3, 1:4) .* (size/origsize);
	im.xsize = size;
	im.ysize = size;
	im.zsize = size;
	im.volres = [size size size];
	im.tkrvox2ras(1:3, 1:4) = im.tkrvox2ras(1:3, 1:4) .* (size/origsize);

    % Write output image
	MRIwrite(im, outPath);

end

end