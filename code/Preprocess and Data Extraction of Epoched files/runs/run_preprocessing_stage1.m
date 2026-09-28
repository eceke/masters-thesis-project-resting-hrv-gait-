function run_preprocessing_stage1()
%RUN_PREPROCESSING_STAGE1 Batch preprocessing for all non-ECG signals.
%
% ECG is intentionally excluded and will be handled separately in Stage 2.

clc;

fprintf('\n=====================================\n');
fprintf('RUN PREPROCESSING STAGE 1 START\n');
fprintf('=====================================\n');

addpath(genpath(fileparts(fileparts(mfilename('fullpath')))));

cfg = get_preprocessing_config();
discovery = discover_participants_and_segments(cfg);

stage1_functions_by_sensor = struct();

stage1_functions_by_sensor.Heart = { ...
    'temp',                  @clean_temp; ...
    'hr_live',               @clean_hr; ...
    'hrvrmssd_live',         @clean_hrvrmssd; ...
    'nn_live',               @clean_nn; ...
    'bpmbxb_live',           @clean_bpmbxb; ...
    'acc',                   @clean_acc; ...
    'angularrate',           @clean_angularrate; ...
    'movementacceleration',  @clean_movementacceleration; ...
    'stepcount',             @clean_stepcount; ...
    'press',                 @clean_press; ...
    'tempmean',              @clean_tempmean};

stage1_functions_by_sensor.Hip = { ...
    'temp',                  @clean_temp; ...
    'acc',                   @clean_acc; ...
    'angularrate',           @clean_angularrate; ...
    'movementacceleration',  @clean_movementacceleration; ...
    'stepcount',             @clean_stepcount; ...
    'press',                 @clean_press; ...
    'tempmean',              @clean_tempmean};

all_summary_rows = {};
all_qc_rows = {};
error_rows = {};

for r = 1:numel(discovery.records)

    rec = discovery.records(r);

    fprintf('\n-------------------------------------\n');
    fprintf('%s | %s | %s | status=%s\n', ...
        rec.participant_id, rec.sensor, rec.segment_name, rec.file_status);
    
    stage1_functions = stage1_functions_by_sensor.(rec.sensor);
    for f = 1:size(stage1_functions, 1)

        signal_name = stage1_functions{f,1};
        cleaner_fun = stage1_functions{f,2};

        fprintf('  Processing %-25s ... ', signal_name);

        try
            out = cleaner_fun(cfg, rec);

            % Save individual outputs
            save_stage1_output(cfg, rec, signal_name, out);

            % Collect summary
            summary_row = local_struct_to_row(out.summary);
            summary_row.participant_id = string(rec.participant_id);
            summary_row.sensor = string(rec.sensor);
            summary_row.segment_name = string(rec.segment_name);
            summary_row.segment_type = string(rec.segment_type);
            summary_row.file_status = string(rec.file_status);
            summary_row.signal_name = string(signal_name);

            all_summary_rows{end+1} = summary_row; %#ok<AGROW>

            % Collect QC
            qc_row = local_struct_to_row(out.qc);
            qc_row.participant_id = string(rec.participant_id);
            qc_row.sensor = string(rec.sensor);
            qc_row.segment_name = string(rec.segment_name);
            qc_row.segment_type = string(rec.segment_type);
            qc_row.file_status = string(rec.file_status);
            qc_row.signal_name = string(signal_name);

            all_qc_rows{end+1} = qc_row; %#ok<AGROW>

            fprintf('OK\n');

        catch ME
            fprintf('ERROR\n');

            err = struct();
            err.participant_id = string(rec.participant_id);
            err.sensor = string(rec.sensor);
            err.segment_name = string(rec.segment_name);
            err.segment_type = string(rec.segment_type);
            err.file_status = string(rec.file_status);
            err.signal_name = string(signal_name);
            err.error_identifier = string(ME.identifier);
            err.error_message = string(ME.message);

            error_rows{end+1} = err; %#ok<AGROW>

            if ~cfg.flags.continue_on_processing_error
                rethrow(ME);
            end
        end
    end
end

%% Save master summary table
if ~isempty(all_summary_rows)
    summary_table = local_rows_to_table(all_summary_rows);
    summary_file = fullfile(cfg.paths.features_root, 'stage1_signal_summaries_long.csv');
    writetable(summary_table, summary_file);
    fprintf('\nSaved summary table:\n%s\n', summary_file);
else
    fprintf('\nNo summary rows generated.\n');
end

%% Save master QC table
if ~isempty(all_qc_rows)
    qc_table = local_rows_to_table(all_qc_rows);
    qc_file = fullfile(cfg.paths.qc_root, 'stage1_qc_long.csv');
    writetable(qc_table, qc_file);
    fprintf('\nSaved QC table:\n%s\n', qc_file);
else
    fprintf('\nNo QC rows generated.\n');
end

%% Save processing error table
if ~isempty(error_rows)
    error_table = local_rows_to_table(error_rows);
    error_file = cfg.logging.processing_error_log;
    writetable(error_table, error_file);
    fprintf('\nSaved processing error table:\n%s\n', error_file);
else
    fprintf('\nNo processing errors.\n');
end

fprintf('\n=====================================\n');
fprintf('RUN PREPROCESSING STAGE 1 END\n');
fprintf('=====================================\n');

end

%% ========================================================================
function save_stage1_output(cfg, rec, signal_name, out)
%SAVE_STAGE1_OUTPUT Save flagged/cleaned/summary/QC files for one context.

out_dir = fullfile( ...
    cfg.paths.output_root, ...
    rec.participant_id, ...
    rec.sensor, ...
    rec.segment_name, ...
    signal_name);

if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

base_name = sprintf('%s_%s_%s_%s', ...
    rec.participant_id, rec.sensor, rec.segment_name, signal_name);

if cfg.flags.save_flagged_versions && istable(out.flagged_table) && ~isempty(out.flagged_table)
    flagged_file = fullfile(out_dir, [base_name '_flagged.csv']);
    writetable(out.flagged_table, flagged_file);
end

if cfg.flags.save_cleaned_versions && istable(out.cleaned_table) && ~isempty(out.cleaned_table)
    cleaned_file = fullfile(out_dir, [base_name '_cleaned.csv']);
    writetable(out.cleaned_table, cleaned_file);
end

summary_table = struct2table(local_struct_to_row(out.summary));
summary_file = fullfile(out_dir, [base_name '_summary.csv']);
writetable(summary_table, summary_file);

qc_table = struct2table(local_struct_to_row(out.qc));
qc_file = fullfile(out_dir, [base_name '_qc.csv']);
writetable(qc_table, qc_file);

end

%% ========================================================================
function row = local_struct_to_row(s)
%LOCAL_STRUCT_TO_ROW Convert scalar struct to table-safe scalar struct.

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
%LOCAL_ROWS_TO_TABLE Convert heterogeneous scalar structs to one table.

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