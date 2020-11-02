function createFakeT1(filePath, minIntensity, minGradient, varargin)
%CREATEFAKET1  Invert T2-like contrast to produce a T1-like image.
%
%   CREATEFAKET1(filePath, minIntensity, minGradient) creates a fake T1
%   volume based on filePath, inverting all intensities above minIntensity
%   and smoothing voxels near intensity gradients higher than minGradient.
%
%   Input arguments:
%   filePath          full path name to MRI volume to be inverted [string]
%   minIntensity      initial threshold for inverting intensities (intensities
%                     at and below this value will be discarded) [float]
%   minGradient       voxels near intensity gradients larger than minGradient
%                     will be smoothed with neighboring voxels to remove a high-
%                     intensity ring around the brain [float]
%
%   Optional input arguments:
%   keepScale         keeps original intensity range of input image [boolean]
%   maxInt            maximum intensity in the output image
%
%   Dirk Jan Ardesch, VU Amsterdam

% Defaults
keepScale = 0; % boolean
maxInt = 120; % intensity of the brightest voxels in the output image

% Check filetype
if contains(filePath, '.nii.gz')
    basename = filePath(1:strfind(filePath, '.nii.gz')-1);
    suffix = '.nii.gz';
elseif contains(filePath, '.nii')
    basename = filePath(1:strfind(filePath, '.nii')-1);
    suffix = '.nii';
elseif contains(filePath, '.mgz')
    basename = filePath(1:strfind(filePath, '.mgz')-1);
    suffix = '.mgz';
else
    error('Image file format not recognized. Must be .nii, .nii.gz, or .mgz');
end

% Parse optional arguments
while ~isempty(varargin)
    if numel(varargin) == 1
        error('lscatter:missing_option', ...
            'Optional arguments must come in pairs.');
    end
    
    switch lower(varargin{1})
        case 'keepscale'
            assert(varargin{2} == 0 | varargin{2} == 1)
            keepScale = varargin{2};
        case 'maxint'
            assert(isnumeric(varargin{2}));
            maxInt = varargin{2};                         
        otherwise
            error('option %s unknown', varargin{1});
    end

    varargin(1:2) = [];

end

% Load image and prepare output
im=MRIread(filePath);
out=im;
out.vol=out.vol.*0;
fprintf('Creating fake T1 for %s with minIntensity = %.2e\n', ...
    filePath, minIntensity);

% Determine how to scale the images intensities
signalMask = im.vol > minIntensity;
im.vol = im.vol .* signalMask; % remove noise

% Make histogram
[N, edges] = histcounts(im.vol(:));

% Find peaks
[~, locs, ~, p] = findpeaks(N);

% Find the most prominent peaks (should be GM and WM)
[~, I] = sort(p, 'descend');

% Find the intensities of these peaks
peak_intensities = edges(locs(I(1:2)));
peak2peak = abs(diff(peak_intensities));

% Take two peak2peak distances before and after the peak as range
if ~keepScale
    sigma = 2;
    minIntensity = min(peak_intensities) - sigma * peak2peak;
    maxIntensity = max(peak_intensities) + sigma * peak2peak;
    rangeIntensity = maxIntensity - minIntensity;
else
    minIntensity = min(im.vol(:));
    maxIntensity = max(im.vol(:));
    rangeIntensity = maxIntensity - minIntensity;
end     

% Invert intensities
mask = (im.vol > minIntensity) & (im.vol < maxIntensity);
im.vol(mask) = (im.vol(mask) - minIntensity)./rangeIntensity; % feature scaling
out.vol(mask) = 1 - im.vol(mask); % invert
out.vol = out.vol .* maxInt; % scale back to a sensible range
out.vol = out.vol .* signalMask; % remove any noise intensities again

% Compute gradient and smooth volume at high gradient intensities
for i = 1:5 % five times seems enough

    [Gx, Gy, Gz] = imgradientxyz(out.vol, 'intermediate');
    G = abs(Gx)+abs(Gy)+abs(Gz); % total gradient
    mask = double(G > minGradient);
    mask = smooth3(mask, 'gaussian', 3);

    % Take a weighted average of smoothed and unsmoothed data for voxels in
    % mask (i.e. neighborhood of high intensity gradient)
    smoothvol = smooth3(out.vol, 'gaussian', 3);
    out.vol(mask > 0) = out.vol(mask > 0).*(1-mask(mask>0)) + smoothvol(mask > 0).*mask(mask>0);
        
end

% Write output image
MRIwrite(out, sprintf('%s_fakeT1%s', basename, suffix));
fprintf('Saved as %s_fakeT1%s.\n', basename, suffix);

end