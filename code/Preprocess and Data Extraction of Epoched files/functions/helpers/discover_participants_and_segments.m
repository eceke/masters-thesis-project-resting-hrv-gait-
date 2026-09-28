function discovery = discover_participants_and_segments(cfg)
%DISCOVER_PARTICIPANTS_AND_SEGMENTS Discover participant/sensor/segment structure
% and resolve raw/physical file availability for each expected file.

%% Validate config
if nargin < 1 || isempty(cfg)
    error('discover_participants_and_segments:MissingConfig', ...
        'cfg is required. Call get_preprocessing_config() first.');
end

if ~isfield(cfg, 'paths') || ~isfield(cfg.paths, 'epochs_root')
    error('discover_participants_and_segments:BadConfig', ...
        'cfg.paths.epochs_root is missing.');
end

epochs_root = cfg.paths.epochs_root;

if ~exist(epochs_root, 'dir')
    error('discover_participants_and_segments:MissingRoot', ...
        'Epochs root does not exist: %s', epochs_root);
end

%% Initialize output
discovery = struct();
discovery.generated_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
discovery.epochs_root = epochs_root;
discovery.participants = {};
discovery.records = local_empty_record_struct();
discovery.records = discovery.records([]); % proper empty struct array
discovery.summary = struct();

records_cell = {};

%% Find participant folders
root_listing = dir(epochs_root);
root_listing = root_listing([root_listing.isdir]);
root_names = {root_listing.name};
root_listing = root_listing(~ismember(root_names, {'.', '..'}));

participant_names = {};
for i = 1:numel(root_listing)
    this_name = root_listing(i).name;
    if ~isempty(regexp(this_name, cfg.discovery.participant_regex, 'once'))
        participant_names{end+1} = this_name; %#ok<AGROW>
    end
end

participant_names = sort(participant_names);
discovery.participants = participant_names;

%% Traverse participants / sensors / included segments
for p = 1:numel(participant_names)
    participant_id = participant_names{p};
    participant_path = fullfile(epochs_root, participant_id);

    for s = 1:numel(cfg.sensors)
        sensor_name = cfg.sensors{s};
        sensor_csv_path = fullfile(participant_path, sensor_name, 'csv');
        sensor_exists = exist(sensor_csv_path, 'dir') == 7;

        for seg = 1:numel(cfg.segments.include)
            segment_name = cfg.segments.include{seg};
            segment_path = fullfile(sensor_csv_path, segment_name);
            segment_exists = exist(segment_path, 'dir') == 7;
        
            physical_dir_path = fullfile(segment_path, 'Physical');
            physical_dir_exists = exist(physical_dir_path, 'dir') == 7;
        
            [segment_type, speed_label, walk_task_label] = ...
                local_describe_segment(segment_name);
        
            expected_files_this_sensor = local_expected_files_for_sensor(cfg, sensor_name);
        
            % Initialize per-record collections
            files_info = local_empty_file_info_struct();
            files_info = files_info([]);
        
            raw_existing = {};
            raw_missing = {};
        
            hard_missing = {};
            soft_missing = {};
            log_only_missing = {};
            xml_missing = {};
        
            if sensor_exists && segment_exists
                file_cell = {};
        
                for f = 1:numel(expected_files_this_sensor)
                    expected_name = expected_files_this_sensor{f};
        
                    file_info = resolve_signal_source( ...
                        participant_id, ...
                        segment_name, ...
                        segment_path, ...
                        expected_name);
        
                    file_cell{end+1} = file_info;
        
                    if file_info.raw_exists
                        raw_existing{end+1} = expected_name;
                    else
                        raw_missing{end+1} = expected_name;
                    end
        
                    level = get_file_requirement_level(cfg, sensor_name, expected_name);
        
                    switch level
                        case 'xml'
                            if ~file_info.raw_exists
                                xml_missing{end+1} = expected_name;
                            end
        
                        case 'log_only'
                            if ~file_info.physical_exists
                                log_only_missing{end+1} = expected_name;
                            end
        
                        case 'soft'
                            if ~file_info.physical_exists
                                soft_missing{end+1} = expected_name;
                            end
        
                        case 'hard'
                            if ~file_info.physical_exists
                                hard_missing{end+1} = expected_name;
                            end
        
                        otherwise
                            if ~file_info.physical_exists
                                soft_missing{end+1} = expected_name;
                            end
                    end
                end
        
                if ~isempty(file_cell)
                    files_info = [file_cell{:}];
                end
            end
        
            % Record build
            rec = local_empty_record_struct();
            rec.participant_id = participant_id;
            rec.sensor = sensor_name;
            rec.participant_path = participant_path;
            rec.sensor_csv_path = sensor_csv_path;
            rec.segment_name = segment_name;
            rec.segment_path = segment_path;
            rec.physical_dir_path = physical_dir_path;
        
            rec.exists_sensor_csv = sensor_exists;
            rec.exists_segment = segment_exists;
            rec.exists_physical_dir = physical_dir_exists;
        
            rec.expected_files = expected_files_this_sensor(:)';
            rec.files = files_info;
        
            rec.raw_existing_files = raw_existing;
            rec.raw_missing_files = raw_missing;
        
            rec.hard_missing_files = hard_missing;
            rec.soft_missing_files = soft_missing;
            rec.log_only_missing_files = log_only_missing;
            rec.xml_missing_files = xml_missing;
        
            rec.has_hard_missing = ~isempty(hard_missing);
            rec.has_soft_missing = ~isempty(soft_missing);
            rec.has_log_only_missing = ~isempty(log_only_missing);
            rec.has_xml_missing = ~isempty(xml_missing);
        
            rec.num_expected_files = numel(expected_files_this_sensor);
            rec.num_raw_existing_files = numel(raw_existing);
            rec.num_raw_missing_files = numel(raw_missing);
            rec.num_hard_missing_files = numel(hard_missing);
            rec.num_soft_missing_files = numel(soft_missing);
            rec.num_log_only_missing_files = numel(log_only_missing);
            rec.num_xml_missing_files = numel(xml_missing);
        
            rec.segment_type = segment_type;
            rec.speed_label = speed_label;
            rec.walk_task_label = walk_task_label;
        
            rec.file_status = local_record_status(rec);
        
            records_cell{end+1} = rec;
        end
    end
end

if ~isempty(records_cell)
    discovery.records = [records_cell{:}];
end

%% Summary
num_records = numel(discovery.records);

summary = struct();
summary.total_participants = numel(participant_names);
summary.total_records = num_records;
summary.total_expected_segment_contexts = ...
    numel(participant_names) * numel(cfg.sensors) * numel(cfg.segments.include);

summary.complete_contexts = 0;
summary.soft_missing_contexts = 0;
summary.hard_missing_contexts = 0;

summary.missing_sensor_csv_contexts = 0;
summary.missing_segment_contexts = 0;
summary.missing_physical_dir_contexts = 0;
summary.missing_raw_file_contexts = 0;

summary.total_missing_raw_files = 0;
summary.total_missing_hard_files = 0;
summary.total_missing_soft_files = 0;
summary.total_missing_log_only_files = 0;
summary.total_missing_xml_files = 0;

for i = 1:num_records
    rec = discovery.records(i);

    switch rec.file_status
        case 'complete'
            summary.complete_contexts = summary.complete_contexts + 1;

        case 'soft_missing_only'
            summary.soft_missing_contexts = summary.soft_missing_contexts + 1;

        case 'hard_missing'
            summary.hard_missing_contexts = summary.hard_missing_contexts + 1;

        case 'missing_sensor_csv_folder'
            summary.missing_sensor_csv_contexts = summary.missing_sensor_csv_contexts + 1;

        case 'missing_segment_folder'
            summary.missing_segment_contexts = summary.missing_segment_contexts + 1;

        case 'missing_physical_dir'
            summary.missing_physical_dir_contexts = summary.missing_physical_dir_contexts + 1;

        case 'missing_raw_file'
            summary.missing_raw_file_contexts = summary.missing_raw_file_contexts + 1;
    end

    summary.total_missing_raw_files = summary.total_missing_raw_files + rec.num_raw_missing_files;
    summary.total_missing_hard_files = summary.total_missing_hard_files + rec.num_hard_missing_files;
    summary.total_missing_soft_files = summary.total_missing_soft_files + rec.num_soft_missing_files;
    summary.total_missing_log_only_files = summary.total_missing_log_only_files + rec.num_log_only_missing_files;
    summary.total_missing_xml_files = summary.total_missing_xml_files + rec.num_xml_missing_files;
end

discovery.summary = summary;

%% Console summary
if isfield(cfg, 'flags') && isfield(cfg.flags, 'verbose_console') && cfg.flags.verbose_console
    fprintf('\n=== DISCOVERY SUMMARY ===\n');
    fprintf('Epoch root: %s\n', discovery.epochs_root);
    fprintf('Participants found: %d\n', discovery.summary.total_participants);
    fprintf('Total participant/sensor/segment contexts: %d\n', discovery.summary.total_records);
    fprintf('Complete contexts: %d\n', discovery.summary.complete_contexts);
    fprintf('Soft-missing-only contexts: %d\n', discovery.summary.soft_missing_contexts);
    fprintf('Hard-missing contexts: %d\n', discovery.summary.hard_missing_contexts);
    fprintf('Missing sensor csv contexts: %d\n', discovery.summary.missing_sensor_csv_contexts);
    fprintf('Missing segment contexts: %d\n', discovery.summary.missing_segment_contexts);
    fprintf('Missing Physical dir contexts: %d\n', discovery.summary.missing_physical_dir_contexts);
    fprintf('Contexts with missing raw files: %d\n', discovery.summary.missing_raw_file_contexts);
    fprintf('Total missing raw files: %d\n', discovery.summary.total_missing_raw_files);
    fprintf('Total missing HARD files: %d\n', discovery.summary.total_missing_hard_files);
    fprintf('Total missing SOFT files: %d\n', discovery.summary.total_missing_soft_files);
    fprintf('Total missing LOG-ONLY files: %d\n', discovery.summary.total_missing_log_only_files);
    fprintf('Total missing XML files: %d\n', discovery.summary.total_missing_xml_files);
end

%% Save discovery log
try
    local_save_discovery_log(discovery, cfg);
catch ME
    warning('discover_participants_and_segments:LogWriteFailed', ...
        'Discovery completed, but discovery log could not be written: %s', ME.message);
end

end

%% ------------------------------------------------------------------------
function rec = local_empty_record_struct()
% Fixed-field record template to avoid struct mismatch errors.

rec = struct( ...
    'participant_id', '', ...
    'sensor', '', ...
    'participant_path', '', ...
    'sensor_csv_path', '', ...
    'segment_name', '', ...
    'segment_path', '', ...
    'physical_dir_path', '', ...
    'exists_sensor_csv', false, ...
    'exists_segment', false, ...
    'exists_physical_dir', false, ...
    'expected_files', {{}}, ...
    'files', local_empty_file_info_struct(), ...
    'raw_existing_files', {{}}, ...
    'raw_missing_files', {{}}, ...
    'hard_missing_files', {{}}, ...
    'soft_missing_files', {{}}, ...
    'log_only_missing_files', {{}}, ...
    'xml_missing_files', {{}}, ...
    'has_hard_missing', false, ...
    'has_soft_missing', false, ...
    'has_log_only_missing', false, ...
    'has_xml_missing', false, ...
    'num_expected_files', 0, ...
    'num_raw_existing_files', 0, ...
    'num_raw_missing_files', 0, ...
    'num_hard_missing_files', 0, ...
    'num_soft_missing_files', 0, ...
    'num_log_only_missing_files', 0, ...
    'num_xml_missing_files', 0, ...
    'file_status', '', ...
    'segment_type', '', ...
    'speed_label', '', ...
    'walk_task_label', '');
end

%% ------------------------------------------------------------------------
function fi = local_empty_file_info_struct()
% Fixed-field file-info template.

fi = struct( ...
    'expected_name', '', ...
    'raw_path', '', ...
    'raw_exists', false, ...
    'physical_path', '', ...
    'physical_exists', false, ...
    'preferred_source', '', ...
    'preferred_path', '', ...
    'status', '');
end

%% ------------------------------------------------------------------------
function status = local_record_status(rec)
% Determine final record status according to requirement rules.

if ~rec.exists_sensor_csv
    status = 'missing_sensor_csv_folder';
    return;
end

if ~rec.exists_segment
    status = 'missing_segment_folder';
    return;
end

if ~rec.exists_physical_dir
    status = 'missing_physical_dir';
    return;
end

% Missing any raw file is still a structural problem
if rec.num_raw_missing_files > 0
    status = 'missing_raw_file';
    return;
end

% XML missing is also structural because metadata is required
if rec.num_xml_missing_files > 0
    status = 'missing_raw_file';
    return;
end

if rec.has_hard_missing
    status = 'hard_missing';
    return;
end

if rec.has_soft_missing
    status = 'soft_missing_only';
    return;
end

status = 'complete';
end

%% ------------------------------------------------------------------------
function [segment_type, speed_label, walk_task_label] = local_describe_segment(segment_name)

switch upper(segment_name)
    case {'RS_EO1', 'RS_EC', 'RS_EO2'}
        segment_type = 'rest';
        speed_label = '';
        walk_task_label = '';

    case 'BW_1KMH'
        segment_type = 'walk';
        speed_label = '1KMH';
        walk_task_label = 'Baseline';

    case 'BW_4KMH'
        segment_type = 'walk';
        speed_label = '4KMH';
        walk_task_label = 'Baseline';

    case 'FWW_1KMH'
        segment_type = 'walk';
        speed_label = '1KMH';
        walk_task_label = 'FW';

    case 'FWW_4KMH'
        segment_type = 'walk';
        speed_label = '4KMH';
        walk_task_label = 'FW';

    otherwise
        segment_type = 'unknown';
        speed_label = '';
        walk_task_label = '';
end

end

%% ------------------------------------------------------------------------
function local_save_discovery_log(discovery, cfg)

if ~exist(cfg.paths.logs_root, 'dir')
    mkdir(cfg.paths.logs_root);
end

n = numel(discovery.records);

participant_id = strings(n,1);
sensor = strings(n,1);
segment_name = strings(n,1);
segment_type = strings(n,1);
speed_label = strings(n,1);
walk_task_label = strings(n,1);
file_status = strings(n,1);

exists_sensor_csv = false(n,1);
exists_segment = false(n,1);
exists_physical_dir = false(n,1);

num_expected_files = zeros(n,1);
num_raw_existing_files = zeros(n,1);
num_raw_missing_files = zeros(n,1);
num_hard_missing_files = zeros(n,1);
num_soft_missing_files = zeros(n,1);
num_log_only_missing_files = zeros(n,1);
num_xml_missing_files = zeros(n,1);

raw_missing_files = strings(n,1);
hard_missing_files = strings(n,1);
soft_missing_files = strings(n,1);
log_only_missing_files = strings(n,1);
xml_missing_files = strings(n,1);

segment_path = strings(n,1);
physical_dir_path = strings(n,1);

for i = 1:n
    rec = discovery.records(i);

    participant_id(i) = string(rec.participant_id);
    sensor(i) = string(rec.sensor);
    segment_name(i) = string(rec.segment_name);
    segment_type(i) = string(rec.segment_type);
    speed_label(i) = string(rec.speed_label);
    walk_task_label(i) = string(rec.walk_task_label);
    file_status(i) = string(rec.file_status);

    exists_sensor_csv(i) = rec.exists_sensor_csv;
    exists_segment(i) = rec.exists_segment;
    exists_physical_dir(i) = rec.exists_physical_dir;

    num_expected_files(i) = rec.num_expected_files;
    num_raw_existing_files(i) = rec.num_raw_existing_files;
    num_raw_missing_files(i) = rec.num_raw_missing_files;
    num_hard_missing_files(i) = rec.num_hard_missing_files;
    num_soft_missing_files(i) = rec.num_soft_missing_files;
    num_log_only_missing_files(i) = rec.num_log_only_missing_files;
    num_xml_missing_files(i) = rec.num_xml_missing_files;

    raw_missing_files(i) = string(strjoin(rec.raw_missing_files, '; '));
    hard_missing_files(i) = string(strjoin(rec.hard_missing_files, '; '));
    soft_missing_files(i) = string(strjoin(rec.soft_missing_files, '; '));
    log_only_missing_files(i) = string(strjoin(rec.log_only_missing_files, '; '));
    xml_missing_files(i) = string(strjoin(rec.xml_missing_files, '; '));

    segment_path(i) = string(rec.segment_path);
    physical_dir_path(i) = string(rec.physical_dir_path);
end

T = table( ...
    participant_id, ...
    sensor, ...
    segment_name, ...
    segment_type, ...
    speed_label, ...
    walk_task_label, ...
    file_status, ...
    exists_sensor_csv, ...
    exists_segment, ...
    exists_physical_dir, ...
    num_expected_files, ...
    num_raw_existing_files, ...
    num_raw_missing_files, ...
    num_hard_missing_files, ...
    num_soft_missing_files, ...
    num_log_only_missing_files, ...
    num_xml_missing_files, ...
    raw_missing_files, ...
    hard_missing_files, ...
    soft_missing_files, ...
    log_only_missing_files, ...
    xml_missing_files, ...
    segment_path, ...
    physical_dir_path);

writetable(T, cfg.logging.discovery_log_file);

end


%% ------------------------------------------------------------------------
function expected_files = local_expected_files_for_sensor(cfg, sensor_name)

if isfield(cfg.files, 'expected_by_sensor') && ...
        isfield(cfg.files.expected_by_sensor, sensor_name)

    expected_files = cfg.files.expected_by_sensor.(sensor_name);

else
    expected_files = cfg.files.expected;
end

end