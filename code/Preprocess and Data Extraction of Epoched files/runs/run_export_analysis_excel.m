function run_export_analysis_excel()

fprintf('\n=====================================\n');
fprintf('EXPORT ANALYSIS EXCEL START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();

file = fullfile(cfg.paths.features_root, 'ANALYSIS_TABLE_participant_segment.csv');

if ~isfile(file)
    error('Merged table not found.');
end

T = readtable(file);

export_analysis_excel(cfg, T);

fprintf('\n=====================================\n');
fprintf('EXPORT ANALYSIS EXCEL END\n');
fprintf('=====================================\n');

end