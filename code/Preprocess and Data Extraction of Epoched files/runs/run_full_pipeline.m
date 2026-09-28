function run_full_pipeline()
%RUN_FULL_PIPELINE Main wrapper for the current preprocessing/data pipeline.
%
% Core pipeline:
%   1. Stage 1 preprocessing
%   2. ECG all-context test/summary
%   3. Build FULL master table
%   4. Merge Kinesis
%   5. Build analysis table
%   6. Build serial-order HRV table/QC
%   7. Analyze serial-order HRV
%   8. Build HRV-gait LMM analysis tables
%   9. Export readable Excel report
%   10. Export pipeline QC summary
%
% Optional:
%   - Exploratory correlation report

clc;

fprintf('\n=====================================\n');
fprintf('RUN FULL PIPELINE START\n');
fprintf('=====================================\n');

project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(project_root));

%% Settings
run_optional_correlation = false;

%% 1. Stage 1 preprocessing
fprintf('\n[1/10] Running Stage 1 preprocessing...\n');
run_preprocessing_stage1();

%% 2. ECG summary
fprintf('\n[2/10] Running ECG all-context summary...\n');

if exist('run_clean_ecg_all', 'file') == 2
    run_clean_ecg_all();
else
    error(['run_clean_ecg_all.m not found. ', ...
        'ECG features cannot be generated.']);
end

%% 3. Build FULL master table
fprintf('\n[3/10] Building FULL master table...\n');
build_full_master_table();

%% 4. Merge Kinesis
fprintf('\n[4/10] Merging Kinesis into FULL table...\n');
run_merge_kinesis_to_full_table();

%% 5. Build analysis table
fprintf('\n[5/10] Building analysis table...\n');
run_build_analysis_table();

%% 6. Build serial-order HRV table/QC
fprintf('\n[6/10] Building serial-order HRV table/QC...\n');

if exist('build_serial_order_hrv_table', 'file') == 2
    build_serial_order_hrv_table();
else
    error(['build_serial_order_hrv_table.m not found. ', ...
        'Serial-order HRV output cannot be generated.']);
end

%% 7. Analyze serial-order HRV
fprintf('\n[7/10] Analyzing serial-order HRV...\n');

if exist('analyze_serial_order_hrv', 'file') == 2
    analyze_serial_order_hrv();
else
    error(['analyze_serial_order_hrv.m not found. ', ...
        'Serial-order HRV analysis cannot be generated.']);
end

%% 8. Build HRV-gait LMM analysis tables
fprintf('\n[8/10] Building HRV-gait LMM analysis tables...\n');

if exist('build_lmm_analysis_tables', 'file') == 2
    build_lmm_analysis_tables();
else
    error(['build_lmm_analysis_tables.m not found. ', ...
        'HRV-gait LMM tables cannot be generated.']);
end

%% 9. Export readable Excel report
fprintf('\n[9/10] Exporting readable analysis Excel report...\n');
run_export_analysis_excel();

%% 10. Pipeline QC summary
fprintf('\n[10/10] Creating pipeline QC summary...\n');
run_pipeline_qc_summary();

%% Optional correlation report
if run_optional_correlation
    fprintf('\n[Optional] Running clean correlation analysis...\n');

    if exist('run_correlation_analysis', 'file') == 2
        run_correlation_analysis();
    else
        warning('run_correlation_analysis.m not found. Skipping optional correlation report.');
    end
else
    fprintf('\n[Optional] Correlation analysis skipped. Set run_optional_correlation = true to run it.\n');
end

fprintf('\n=====================================\n');
fprintf('RUN FULL PIPELINE END\n');
fprintf('=====================================\n');

end
