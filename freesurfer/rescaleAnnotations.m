function rescaleAnnotations(subjectsDir, subject, originalVolume, processedVolume)
%RESCALEANNOTATIONS  Rescales several FreeSurfer annotations from voxel
%sizes in a source volume to voxel sizes in a target volume.
%
%   RESCALEANNOTATIONS(subjectsDir, subject, originalVolume) rescales
%   ?h.curv, ?h.curv.pial, ?h.thickness, ?h.area, ?h.area.mid,
%   ?h.area.pial, ?h.volume, and ?h.cortex based on the difference between
%   voxel sizes in originalVolume and processedVolume.
%
%   Input arguments:
%   subjectsDir       FreeSurfer subjects directory [string]
%   subject           FreeSurfer subject [string]
%   originalVolume    path to original volume [string]
%   processedVolume   path to processed volume [string]
%
%   Dirk Jan Ardesch, VU Amsterdam

system(['export SUBJECTS_DIR=', subjectsDir]);
cd(subjectsDir);

% This script assumes isotropic voxel sizes
orig = MRIread(originalVolume);
proc = MRIread(processedVolume);
f = orig.xsize / proc.xsize;

% One-dimensional annotations
% Remaining files (like avg_curv, white.H etc will be regenerated later)
annots1d = {
    'curv', ...
    'curv.pial', ...
    'thickness', ...
};

for i = 1:length(annots1d)
    
    % LH
    [curv, fnum] = read_curv(sprintf('%s/surf/lh.%s', subject, annots1d{i}));
    write_curv(sprintf('%s/surf/lh.%s', subject, annots1d{i}), curv .* f, fnum);

    % RH
    [curv, fnum] = read_curv(sprintf('%s/surf/rh.%s', subject, annots1d{i}));
    write_curv(sprintf('%s/surf/rh.%s', subject, annots1d{i}), curv .* f, fnum);
    
end

% Two-dimensional annotations
annots2d = {
    'area', ...
    'area.mid', ...
    'area.pial', ...
};


for i = 1:length(annots2d)
    
    % LH
    [curv, fnum] = read_curv(sprintf('%s/surf/lh.%s', subject, annots2d{i}));
    write_curv(sprintf('%s/surf/lh.%s', subject, annots2d{i}), curv .* (f^2), fnum);

    % RH
    [curv, fnum] = read_curv(sprintf('%s/surf/rh.%s', subject, annots2d{i}));
    write_curv(sprintf('%s/surf/rh.%s', subject, annots2d{i}), curv .* (f^2), fnum);
    
end

% Three-dimensional annotations
annots3d = {
    'volume', ...
};


for i = 1:length(annots3d)
    
    % LH
    [curv, fnum] = read_curv(sprintf('%s/surf/lh.%s', subject, annots3d{i}));
    write_curv(sprintf('%s/surf/lh.%s', subject, annots3d{i}), curv .* (f^3), fnum);

    % RH
    [curv, fnum] = read_curv(sprintf('%s/surf/rh.%s', subject, annots3d{i}));
    write_curv(sprintf('%s/surf/rh.%s', subject, annots3d{i}), curv .* (f^3), fnum);
    
end

% Restore cortex.label
l = read_label([], [subject, '/label/lh.cortex']);
write_label(l(:,1), l(:,2:4).*f, l(:,5), [subject, '/label/lh.cortex']);

end