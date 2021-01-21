function editAseg(aseg, brainFilled, wmFilled, outDir)
%EDITASEG    Edit FreeSurfer aseg.mgz volume based on some manual
%segmentations.
%
%   EDITASEG(aseg, brainFilled, wmFilled, outPath) adds voxels in
%   brainFilled to aseg, improves white matter based on wmFilled, and saves
%   aseg.auto_noCCseg.mgz and aseg.presurf.mgz to outDir.
%
%   Input arguments:
%   aseg                path pointing to an aseg.mgz volume [string]
%   brainFilled         path pointing to a volume with the the following
%                       intensities [string]:
%                       255:    left hemisphere
%                       127:    right hemisphere
%                       231:    cerebellum, brain stem, fourth ventricle
%   wmFilled            path pointing to a filled.mgz volume [string]
%   outDir              path pointing to a directory to which the output
%                       volumes aseg.auto_noCCseg.mgz and aseg.presurf.mgz
%                       will be written
%
%   Dirk Jan Ardesch, VU Amsterdam

aseg = MRIread(aseg);
brainFilled = MRIread(brainFilled); % cerebellum/brainstem/4th ventricle = 231
wmFilled = MRIread(wmFilled);

% initialize output image
output = aseg;
output.vol = zeros(size(output.vol)); % erase image

% add gray matter
output.vol(brainFilled.vol == 255) = 3;
output.vol(brainFilled.vol == 127) = 42;

% add filled_wm
output.vol(wmFilled.vol == 255) = wmFilled.vol(wmFilled.vol == 255)./255 .* 2;
output.vol(wmFilled.vol == 127) = wmFilled.vol(wmFilled.vol == 127)./127 .* 41;

% add some aseg intensities
intensities = unique(aseg.vol);
intensities(intensities == 0) = [];
intensities(intensities == 2) = []; % don't overwrite white matter
intensities(intensities == 3) = []; % don't add gray matter
intensities(intensities == 41) = []; % don't overwrite white matter
intensities(intensities == 42) = []; % don't add gray matter
intensities(intensities == 77) = []; % also remove WM hypointensities

for k = 1:length(intensities)
    output.vol(aseg.vol==intensities(k)) = intensities(k);
end

% Now fill up the cerebellum, brain stem, and 4th ventricle for voxels
% in filled_brain that have intensity 231

% for each nonzero voxel in leftover_gm, check whether it's closest to
% LH GM, RH GM, LH cereb, RH cereb, or brainstem
leftover_gm = double(brainFilled.vol == 231); % leftover voxels (that are 999/231 in filled_brain)
fprintf('%i leftover voxels found.\n', nnz(leftover_gm(:)));
unchanged_ind = 0; % initialize unchanged_ind

while nnz(unchanged_ind) < length(unchanged_ind) % while voxels are being updated

    % for each voxel in leftover_gm, check its 6 neighbors in output.vol. If >0 neighbor is
    % nonzero in original aseg, set to the value of the most common neighbor
    % value (if it's a draw, do a 50/50).
    A = padarray(leftover_gm, [1,1,1]);
    leftover_ind = find(A);
    unchanged_ind = zeros(length(leftover_ind), 1); % reset unchanged indices
    [id_i, id_j, id_k] = ind2sub(size(A), leftover_ind);

    aseg_cb = output.vol .* ismember(output.vol, [7, 8, 15, 16, 46, 47]); % brainstem, 4th ventricle & cerebellum
    aseg_tmp = aseg_cb; % temporary aseg for each iteration of while loop
    aseg_pad = padarray(aseg_cb, [1,1,1,]);

    for x = 1:length(leftover_ind)

        curr_i = id_i(x);
        curr_j = id_j(x);
        curr_k = id_k(x);
        curr_vox = aseg_pad(curr_i, curr_j, curr_k); % account for padding

        neighbors = [ ...
            id_i(x)-1, id_j(x), id_k(x); ...                   
            id_i(x), id_j(x), id_k(x); ...
            id_i(x)+1, id_j(x), id_k(x); ...                   
            id_i(x), id_j(x)-1, id_k(x); ...
            id_i(x), id_j(x), id_k(x); ...
            id_i(x), id_j(x)+1, id_k(x); ...
            id_i(x), id_j(x), id_k(x)-1; ...
            id_i(x), id_j(x), id_k(x); ...
            id_i(x), id_j(x), id_k(x)+1; ...
            ];

        indx = sub2ind(size(A), neighbors(:,1), neighbors(:,2), neighbors(:,3)); % convert to linear indices

        [GC, GR] = count_unique(aseg_pad(indx));

        if curr_vox ~= 0 || (length(GR) == 1 && GR == 0) % if voxel is already updated or if there are only 0 voxels in neighborhood, don't need to update

            unchanged_ind(x) = 1; % keep track of the fact that voxel wasn't updated

        else

            % update in aseg_gm
            GC(GR == 0) = []; % remove counts corresponding to 0
            GR(GR == 0) = []; % remove the 0 itself
            maxval = max(GC);
            I = find(GC == maxval); % find multiple matches if any
            if length(I) > 1
                I = randsample(I, 1); % pick one at random
            end

            aseg_tmp(curr_i-1, curr_j-1, curr_k-1) = GR(I); % index 1 is the most common non-zero value
        end
    end

    % update output.vol and leftover gm
    output.vol(aseg_tmp > 0) = aseg_tmp(aseg_tmp > 0);
    leftover_gm = double(output.vol == 0) .* double(brainFilled.vol > 0); % leftover voxels (that are in filled_brain but 0 in aseg)

    fprintf('unchanged: %i/%i\n', nnz(unchanged_ind), length(unchanged_ind));

end

% Save the aseg.presurf.mgz
MRIwrite(output, [outDir, '/aseg.presurf.mgz']);

% Remove the corpus callosum and save the aseg.auto_noCCseg.mgz
ccLH = double(ismember(aseg.vol, [251:255])) .* double(brainFilled.vol == 255);
ccRH = double(ismember(aseg.vol, [251:255])) .* double(brainFilled.vol == 127);
output.vol(ccLH > 0) = 2;
output.vol(ccRH > 0) = 41;
MRIwrite(output, [outDir, '/aseg.auto_noCCseg.mgz']);

%% Functions

% count_unique: should do the same as groupcounts in R2019a and above
function [GC, GR] = count_unique(A)

    GR = unique(A(:));
    GC = nan(size(GR));

    % for each entry in u, count the number of times it occurs in A and
    % put that in GC

    for i = 1:length(GR)

        GC(i) = sum(A == GR(i));

    end



end

end