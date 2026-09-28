function run_analysis(varargin)
%RUN_ANALYSIS Convenience entry point: adds this project's src/ and
%   config/ folders to the MATLAB path, then runs the full resting-state
%   HRV -> gait performance LMM pipeline.
%
%   Usage:
%       run_analysis                            % uses data/LMM_HRV_GAIT_long.csv
%       run_analysis('DataFile', 'path/to.csv')  % use a different input file
%       run_analysis('OutputDir', 'path/to/out') % use a different output folder
%
%   Requires MATLAB's Statistics and Machine Learning Toolbox.

here = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(here, 'src')));
addpath(fullfile(here, 'config'));

run_hrv_gait_analysis(varargin{:});

end
