function qcPaths = make_qc_plots(confirmedMarkers, dataStruct, epochTable, cfg)
% Create quality control plots for visual verification

    arguments
        confirmedMarkers (:,1) struct
        dataStruct struct
        epochTable table
        cfg (1,1) struct
    end
    
    if ~cfg.qc.createPlots
        qcPaths = {};
        fprintf('[QC] Plot creation disabled in config.\n');
        return;
    end
    
    % Create QC directory
    qcDir = fullfile(cfg.projectRoot, cfg.dir.qcPlots, cfg.participantId);
    if ~exist(qcDir, 'dir')
        mkdir(qcDir);
        fprintf('[QC] Created directory: %s\n', qcDir);
    end
    
    qcPaths = {};
    
    %% 1. OVERVIEW PLOT: All markers on ACC magnitude
    fprintf('[QC] Creating overview plot...\n');
    overviewPath = fullfile(qcDir, sprintf('%s_markers_overview.png', cfg.participantId));
    
    if isfield(dataStruct, 'acc')
        accData = dataStruct.acc.data;
        fsAcc = dataStruct.acc.fs;
        tAcc = (0:size(accData,1)-1)' / fsAcc;
        
        % Calculate magnitude
        accMag = sqrt(sum(accData.^2, 2));
        
        figure('Position', [100, 100, 1400, 600], 'Visible', 'off');
        
        % Plot ACC magnitude
        subplot(2,1,1);
        plot(tAcc, accMag, 'b', 'LineWidth', 0.5);
        hold on;
        
        % Plot markers
        markerTimes = [confirmedMarkers.timeSec];
        for i = 1:length(markerTimes)
            line([markerTimes(i), markerTimes(i)], ylim, ...
                'Color', 'r', 'LineWidth', 1, 'LineStyle', '--');
            text(markerTimes(i), max(ylim)*0.95, sprintf('%d', i), ...
                'Color', 'r', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        end
        
        xlabel('Time (s)');
        ylabel('ACC Magnitude (g)');
        title(sprintf('%s - All Markers Overview (n=%d)', cfg.participantId, length(markerTimes)));
        grid on;
        
        % Plot ECG if available
        if isfield(dataStruct, 'ecg')
            subplot(2,1,2);
            ecgData = dataStruct.ecg.data;
            fsEcg = dataStruct.ecg.fs;
            tEcg = (0:size(ecgData,1)-1)' / fsEcg;
            
            % Plot subset (first 5 minutes for clarity)
            plotDuration = min(300, max(tEcg));
            idx = tEcg <= plotDuration;
            plot(tEcg(idx), ecgData(idx), 'k', 'LineWidth', 0.5);
            
            xlabel('Time (s)');
            ylabel('ECG (mV)');
            title(sprintf('ECG First %.0f seconds', plotDuration));
            grid on;
        end
        
        saveas(gcf, overviewPath);
        close(gcf);
        qcPaths{end+1} = overviewPath;
        fprintf('  Saved: %s\n', overviewPath);
    end
    
    %% 2. INDIVIDUAL MARKER ZOOM PLOTS
    fprintf('[QC] Creating individual marker plots...\n');
    
    markerLabels = {
        'RS_EO1_end';
        'RS_EC_end';
        'RS_EO2_end';
        'BW_1KMH_start';
        'BW_1KMH_end';
        'FWW_1KMH_start';
        'FWW_1KMH_end';
        'BW_4KMH_start';
        'BW_4KMH_end';
        'FWW_4KMH_start';
        'FWW_4KMH_end';
    };
    
    if isfield(dataStruct, 'acc')
        accX = dataStruct.acc.data(:, 1);  % X-axis for detailed view
        fsAcc = dataStruct.acc.fs;
        tAcc = (0:size(accX,1)-1)' / fsAcc;
        
        for i = 1:length(confirmedMarkers)
            markerTime = confirmedMarkers(i).timeSec;
            
            % Zoom window: ±6 seconds
            zoomWindow = 6;  % seconds
            timeRange = [markerTime - zoomWindow, markerTime + zoomWindow];
            
            % Find indices
            idx = tAcc >= timeRange(1) & tAcc <= timeRange(2);
            
            if sum(idx) > 100  % At least 100 samples
                figure('Position', [100, 100, 1200, 400], 'Visible', 'off');
                
                % Plot ACC X
                subplot(1,3,1);
                plot(tAcc(idx), accX(idx), 'b', 'LineWidth', 1.5);
                hold on;
                line([markerTime, markerTime], ylim, 'Color', 'r', 'LineWidth', 2);
                xlabel('Time (s)');
                ylabel('ACC X (g)');
                title(sprintf('Marker %d: %s', i, markerLabels{i}));
                grid on;
                
                % Plot ACC magnitude
                subplot(1,3,2);
                if isfield(dataStruct, 'acc')
                    accMag = sqrt(sum(dataStruct.acc.data(idx, :).^2, 2));
                    plot(tAcc(idx), accMag, 'g', 'LineWidth', 1.5);
                    hold on;
                    line([markerTime, markerTime], ylim, 'Color', 'r', 'LineWidth', 2);
                    xlabel('Time (s)');
                    ylabel('ACC Magnitude (g)');
                    title('ACC Magnitude');
                    grid on;
                end
                
                % Plot gyro if available
                subplot(1,3,3);
                if isfield(dataStruct, 'angularrate')
                    gyroData = dataStruct.angularrate.data(idx, :);
                    plot(tAcc(idx), gyroData(:, 1), 'r', 'DisplayName', 'Gyro X');
                    hold on;
                    plot(tAcc(idx), gyroData(:, 2), 'g', 'DisplayName', 'Gyro Y');
                    plot(tAcc(idx), gyroData(:, 3), 'b', 'DisplayName', 'Gyro Z');
                    line([markerTime, markerTime], ylim, 'Color', 'k', 'LineWidth', 2, 'DisplayName', 'Marker');
                    xlabel('Time (s)');
                    ylabel('Angular Rate (dps)');
                    title('Gyro XYZ');
                    legend('show', 'Location', 'best');
                    grid on;
                end
                
                % Save figure
                markerPath = fullfile(qcDir, sprintf('%s_marker_%02d_%s.png', ...
                    cfg.participantId, i, markerLabels{i}));
                saveas(gcf, markerPath);
                close(gcf);
                qcPaths{end+1} = markerPath;
                
                if cfg.advanced.verbose && mod(i, 3) == 0
                    fprintf('  Created %d/%d marker plots\n', i, length(confirmedMarkers));
                end
            end
        end
        fprintf('  Created %d individual marker plots\n', length(confirmedMarkers));
    end
    
    %% 3. SEGMENT DURATION BAR PLOT
    fprintf('[QC] Creating segment duration plot...\n');
    
    if height(epochTable) > 0
        figure('Position', [100, 100, 1000, 500], 'Visible', 'off');
        
        subplot(1,2,1);
        durations = epochTable.durationSec;
        bar(durations);
        xlabel('Segment Index');
        ylabel('Duration (s)');
        title(sprintf('%s - Segment Durations', cfg.participantId));
        xticks(1:height(epochTable));
        xticklabels(epochTable.segmentName);
        xtickangle(45);
        grid on;
        
        % Add duration values on bars
        for i = 1:length(durations)
            text(i, durations(i) + max(durations)*0.02, ...
                sprintf('%.0fs', durations(i)), ...
                'HorizontalAlignment', 'center', 'FontSize', 9);
        end
        
        % Segment timeline
        subplot(1,2,2);
        colors = lines(height(epochTable));
        for i = 1:height(epochTable)
            rectangle('Position', [epochTable.startSec(i), i-0.4, ...
                epochTable.durationSec(i), 0.8], ...
                'FaceColor', colors(i,:), 'EdgeColor', 'k');
            text(epochTable.startSec(i) + epochTable.durationSec(i)/2, i, ...
                epochTable.segmentName{i}, ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        end
        xlabel('Time (s)');
        ylabel('Segment');
        title('Segment Timeline');
        ylim([0, height(epochTable)+1]);
        grid on;
        
        segmentPath = fullfile(qcDir, sprintf('%s_segments_summary.png', cfg.participantId));
        saveas(gcf, segmentPath);
        close(gcf);
        qcPaths{end+1} = segmentPath;
        fprintf('  Saved: %s\n', segmentPath);
    end
    
    %% 4. MARKER CONFIDENCE HISTOGRAM
    fprintf('[QC] Creating confidence plot...\n');
    
    figure('Position', [100, 100, 800, 400], 'Visible', 'off');
    
    subplot(1,2,1);
    confidences = [confirmedMarkers.selectConfidence];
    bar(confidences);
    xlabel('Marker Index');
    ylabel('Confidence');
    title('Marker Confidences');
    ylim([0, 1]);
    grid on;
    
    % Mark manual overrides
    if isfield(confirmedMarkers, 'manualOverride')
        manualIdx = find([confirmedMarkers.manualOverride]);
        hold on;
        scatter(manualIdx, confidences(manualIdx), 100, 'r', 'filled', '^');
        legend('Auto', 'Manual', 'Location', 'best');
    end
    
    subplot(1,2,2);
    hist(confidences, 10);
    xlabel('Confidence');
    ylabel('Count');
    title('Confidence Distribution');
    grid on;
    
    confidencePath = fullfile(qcDir, sprintf('%s_marker_confidences.png', cfg.participantId));
    saveas(gcf, confidencePath);
    close(gcf);
    qcPaths{end+1} = confidencePath;
    fprintf('  Saved: %s\n', confidencePath);
    
    fprintf('[QC] QC plots completed. Total: %d plots in %s\n', length(qcPaths), qcDir);
end