function run_clean_ecg_all()
%RUN_CLEAN_ECG_ALL Run clean_ecg.m for all Heart contexts and save ECG summary.
%
% This creates the ECG summary file expected by build_full_master_table:
% Output/QC/ECG Tests/test_clean_ecg_all_summary.csv


fprintf('\n=====================================\n');
fprintf('RUN CLEAN ECG ALL START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();
discovery = discover_participants_and_segments(cfg);

out_dir = fullfile(cfg.paths.qc_root, 'ECG Tests');

if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

summary_rows = {};
qc_rows = {};
error_rows = {};

for i = 1:numel(discovery.records)

    rec = discovery.records(i);

    % ECG should only be processed for Heart.
    if ~strcmpi(rec.sensor, 'Heart')
        continue;
    end

    fprintf('\n--------------------------------------\n');
    fprintf('Processing ECG: %s | %s | %s\n', ...
        rec.participant_id, rec.sensor, rec.segment_name);

    try
        out = clean_ecg(cfg, rec);

        % Save individual ECG output files
        local_save_ecg_output(cfg, rec, out);

        % Summary row
        summary_row = local_struct_to_row(out.summary);
        summary_row.participant_id = string(rec.participant_id);
        summary_row.sensor = string(rec.sensor);
        summary_row.segment_name = string(rec.segment_name);
        summary_row.segment_type = string(rec.segment_type);
        summary_row.file_status = string(rec.file_status);
        summary_row.signal_name = string('ecg');
        summary_row.ran_successfully = true;

        summary_rows{end+1} = summary_row; %#ok<AGROW>

        % QC row
        qc_row = local_struct_to_row(out.qc);
        qc_row.participant_id = string(rec.participant_id);
        qc_row.sensor = string(rec.sensor);
        qc_row.segment_name = string(rec.segment_name);
        qc_row.segment_type = string(rec.segment_type);
        qc_row.file_status = string(rec.file_status);
        qc_row.signal_name = string('ecg');
        qc_row.ran_successfully = true;

        qc_rows{end+1} = qc_row; %#ok<AGROW>

        fprintf('OK\n');

    catch ME
        fprintf('ERROR: %s\n', ME.message);

        err = struct();
        err.participant_id = string(rec.participant_id);
        err.sensor = string(rec.sensor);
        err.segment_name = string(rec.segment_name);
        err.segment_type = string(rec.segment_type);
        err.file_status = string(rec.file_status);
        err.signal_name = string('ecg');
        err.error_identifier = string(ME.identifier);
        err.error_message = string(ME.message);

        error_rows{end+1} = err; %#ok<AGROW>

        if isfield(cfg, 'flags') && isfield(cfg.flags, 'continue_on_processing_error')
            if ~cfg.flags.continue_on_processing_error
                rethrow(ME);
            end
        end
    end
end

%% Save ECG summary table
if ~isempty(summary_rows)
    summary_table = local_rows_to_table(summary_rows);

    summary_file = fullfile(out_dir, 'test_clean_ecg_all_summary.csv');
    writetable(summary_table, summary_file);

    fprintf('\nSaved ECG summary table:\n%s\n', summary_file);
else
    fprintf('\nNo ECG summary rows generated.\n');
end

%% Save ECG QC table
if ~isempty(qc_rows)
    qc_table = local_rows_to_table(qc_rows);

    qc_file = fullfile(out_dir, 'test_clean_ecg_all_qc.csv');
    writetable(qc_table, qc_file);

    fprintf('\nSaved ECG QC table:\n%s\n', qc_file);
else
    fprintf('\nNo ECG QC rows generated.\n');
end

%% Save ECG error table
if ~isempty(error_rows)
    error_table = local_rows_to_table(error_rows);

    error_file = fullfile(out_dir, 'test_clean_ecg_all_errors.csv');
    writetable(error_table, error_file);

    fprintf('\nSaved ECG error table:\n%s\n', error_file);
else
    fprintf('\nNo ECG processing errors.\n');
end

fprintf('\n=====================================\n');
fprintf('RUN CLEAN ECG ALL END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function local_save_ecg_output(cfg, rec, out)

out_dir = fullfile( ...
    cfg.paths.output_root, ...
    rec.participant_id, ...
    rec.sensor, ...
    rec.segment_name, ...
    'ecg');

if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

base_name = sprintf('%s_%s_%s_ecg', ...
    rec.participant_id, rec.sensor, rec.segment_name);

if isfield(out, 'ecg_sample_table') && istable(out.ecg_sample_table) && ~isempty(out.ecg_sample_table)
    writetable(out.ecg_sample_table, fullfile(out_dir, [base_name '_sample_table.csv']));
end

if isfield(out, 'rr_cleaned_table') && istable(out.rr_cleaned_table) && ~isempty(out.rr_cleaned_table)
    writetable(out.rr_cleaned_table, fullfile(out_dir, [base_name '_rr_cleaned.csv']));
end

if isfield(out, 'summary') && ~isempty(out.summary)
    summary_table = struct2table(local_struct_to_row(out.summary));
    writetable(summary_table, fullfile(out_dir, [base_name '_summary.csv']));
end

if isfield(out, 'qc') && ~isempty(out.qc)
    qc_table = struct2table(local_struct_to_row(out.qc));
    writetable(qc_table, fullfile(out_dir, [base_name '_qc.csv']));
end

end

%% ========================================================================
function row = local_struct_to_row(s)

row = struct();

if isempty(s)
    return;
end

names = fieldnames(s);

for i = 1:numel(names)
    field = names{i};
    value = s.(field);

    if ischar(value)
        row.(field) = string(value);

    elseif isstring(value)
        if isscalar(value)
            row.(field) = value;
        else
            row.(field) = strjoin(value, " | ");
        end

    elseif islogical(value)
        if isscalar(value)
            row.(field) = value;
        else
            row.(field) = string(mat2str(value));
        end

    elseif isnumeric(value)
        if isscalar(value)
            row.(field) = value;
        else
            row.(field) = string(mat2str(value));
        end

    elseif iscell(value)
        try
            row.(field) = string(strjoin(value, ' | '));
        catch
            row.(field) = string('[cell]');
        end

    else
        row.(field) = string('[unsupported]');
    end
end

end

%% ========================================================================
function T = local_rows_to_table(rows)

all_fields = {};

for i = 1:numel(rows)
    all_fields = union(all_fields, fieldnames(rows{i}), 'stable');
end

normalized = cell(size(rows));

for i = 1:numel(rows)
    s = rows{i};

    for f = 1:numel(all_fields)
        field = all_fields{f};

        if ~isfield(s, field)
            s.(field) = missing;
        end
    end

    normalized{i} = orderfields(s, all_fields);
end

T = struct2table([normalized{:}]);

end