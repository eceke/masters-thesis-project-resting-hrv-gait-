function cfg = config_heart(participantId)
%Configuration parameters for the project.
    
    arguments
        participantId (1,:) char = 'VP04'  % Default, change the participant from here
    end
    cfg = struct();
    
    % === 1. PROJECT STRUCTURE ===
    cfg.projectRoot = 'Pertuba';
    
    % Subfolders
    cfg.dir.raw = 'Raw';
    cfg.rawSubfolder = 'Heart';
    cfg.dir.docs = 'Docs';
    cfg.dir.logs = 'Logs';
    cfg.dir.epochs = 'Epochs';
    cfg.dir.qcPlots = 'QC_Plots';
    
    % === 2. PARTICIPANT AND DEVICE INFORMATION ===
    cfg.participantId = participantId;
    cfg.device = 'Heart';
    
    % === 3. MARKER TEMPLATE ===
    cfg.expectedMarkerCount = 11;
    
    cfg.segmentNames = {
        'RS_EO1';
        'RS_EC';
        'RS_EO2';
        'BW_1KMH';
        'FWW_1KMH';
        'BW_4KMH';
        'FWW_4KMH';
        };
    
    cfg.hasTableSegment = true;

    % Segment-marker mapping
    cfg.segmentMarkerMap = containers.Map();
    cfg.segmentMarkerMap('RS_EO1')  = 1;
    cfg.segmentMarkerMap('RS_EC')   = 2;
    cfg.segmentMarkerMap('RS_EO2')  = 3;
    cfg.segmentMarkerMap('BW_1KMH') = [4, 5];
    cfg.segmentMarkerMap('FWW_1KMH')= [6, 7];
    cfg.segmentMarkerMap('BW_4KMH') = [8, 9];
    cfg.segmentMarkerMap('FWW_4KMH')= [10, 11];
    
    % ===================================================
    % === 4. DETECT PARAMETERS (CANDIDATE FINDING) ===
    cfg.detect = struct();
    cfg.detect.acc = struct();
    cfg.detect.acc.useMagnitude = true;
    cfg.detect.acc.refineAxis = 'X';
    
    % Marker candidate detection parameters
    cfg.detect.minProminenceFactor = 0.10;  % Low threshold
    cfg.detect.minWidthSeconds = 0.3;
    cfg.detect.maxWidthSeconds = 6.0;
    cfg.detect.mergeThreshold = 4.0;  % Combine the closest candidates
    
    % Signal processing
    cfg.detect.smoothWindow = 0.3;
    
    % ===================================================
    % === 5. SELECT PARAMETERS (CHOOSING) ===
    cfg.select = struct();
    cfg.select.minConfidence = 0.2;
    cfg.select.sequenceTolerance = 60.0;
    cfg.select.allowMissingMarkers = false;
    
    % Selection scoring weights
    cfg.select.weights = struct();
    cfg.select.weights.symmetricProminence = 1.0;
    cfg.select.weights.dipDuration = 0.3;
    cfg.select.weights.gyroPattern = 0.4;
    cfg.select.weights.neighborPenalty = 0.3;
    cfg.select.weights.balanceScore = 0.5;
    
    % Gyro confirmation
    cfg.select.gyro = struct();
    cfg.select.gyro.useForValidation = true;
    cfg.select.gyro.windowSeconds = 2.0;
    cfg.select.gyro.confidenceBoost = 0.3;
    
    % Selection algorithm
    cfg.select.timePenaltyWeights = struct(...
        'strict', [1, 2, 3], ...
        'flexible', [3, 4, 7, 8], ...
        'normal', [4, 5, 5, 6, 6, 7, 8, 9, 9, 10, 10, 11] ...
    );
    
    % === 6. INTERACTIVE VERIFICATION PARAMETERS ===
    cfg.interactive = struct();
    cfg.interactive.maxIterations = 3;     % Max correction round
    cfg.interactive.searchWindow = 1.0;    % ±1 second candidate search
    cfg.interactive.verbose = true;        % Detailed messages

    % === 7. EPOCH CUTTING PARAMETERS ===
    cfg.epoch = struct();
    cfg.epoch.expectedDuration = struct();
    cfg.epoch.expectedDuration.RS = 300;
    cfg.epoch.expectedDuration.BW = 120;
    cfg.epoch.expectedDuration.FWW = 180;
    cfg.epoch.bufferBefore = 2.0;
    cfg.epoch.bufferAfter = 2.0;
    

    % === 8. OUTPUT FORMATS ===
    cfg.output = struct();
    cfg.output.saveMat = true;           % Save .mat files
    cfg.output.saveCsv = true;           % Save CSV files
    cfg.output.csvSubfolder = 'csv';     % Subfolder for CSVs
    cfg.output.matVersion = '-v7.3';     % For large files
    cfg.output.fileNameFormat = '%s_%s'; % VP01_RS_EO1
    
    % Which channels to save (from XML ids)
    cfg.output.channelsToSave = {
        'ecg'                    % 1024 Hz
        'acc'                    % 64 Hz
        'angularrate'            % 64 Hz
        'press'                  % 8 Hz
        'hr_live'                % 0.0167 Hz
        'nn_live'                % 1024 Hz
        'bpmbxb_live'            % 1024 Hz
        'hrvrmssd_live'          % 0.0167 Hz
        'temp'                   % 1 Hz
        'charging'               % Charging status
        'hrvisvalid_live'
        'movementacceleration_live'
        'stateofcharge'          % Battery charge level
        'stepcount_live'         % Step count
        'tempmean_live'          % Mean temperature
    };

    
    % === 9. LOG and QC ===
    cfg.log = struct();
    cfg.log.fileName = 'EpochLog.xlsx';
    
    cfg.qc = struct();
    cfg.qc.createPlots = true;
    cfg.qc.dpi = 150;
    
    % === 10. ADVANCED SETTINGS ===
    cfg.advanced = struct();
    cfg.advanced.parallelProcessing = false;
    cfg.advanced.verbose = true;
    cfg.advanced.saveIntermediate = false;


    % === QC PLOTS ===
    cfg.qc = struct();
    cfg.qc.createPlots = true;      % Enable QC plots
    cfg.qc.dpi = 150;               % Figure resolution
    cfg.qc.zoomWindow = 6;          % ±6 seconds around markers
    cfg.qc.maxOverviewMinutes = 10; % Show first 10 minutes in overview
    
end