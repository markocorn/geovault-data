% defender_sha256_overlay_stairs_with_percentiles.m
% Journal-ready overlay histogram using STAIRS (legend colors guaranteed)
% + Percentile calculations per points count (printed to console, optional CSV)
%
% Reads CSVs:
%   defender_sha256_cumulative_1points_raw.csv ... 5points_raw.csv
% Expected columns: Run,Points,InputLen_bytes,Time_ms

clear; clc; close all;

% ---- Files to read ----
pointCounts = 1:5;
prefix = "defender_sha256_cumulative_";
suffix = "points_raw.csv";

% ---- Journal-quality style ----
FONT_NAME        = 'Helvetica';
AXIS_FONT_SIZE   = 14;
TITLE_FONT_SIZE  = 16;
LEGEND_FONT_SIZE = 12;
LINE_WIDTH       = 1.6;

FIG_WIDTH_CM  = 16;
FIG_HEIGHT_CM = 10;

set(groot, 'defaultAxesFontName', FONT_NAME);
set(groot, 'defaultTextFontName', FONT_NAME);
set(groot, 'defaultLineLineWidth', LINE_WIDTH);

% ---- Binning ----
binWidthMs = 0.01;

% ---- Percentiles to compute ----
pctList = [50 90 95 99 99.9];

% Optional: write percentile table to CSV (set true/false)
WRITE_PERCENTILES_CSV = false;
percentilesCsvName = "sha256_percentiles.csv";

% ---- Read data ----
allTimes = {};
labels   = {};
metaPts  = [];
metaLen  = [];

for p = pointCounts
    file = prefix + string(p) + suffix;
    if ~isfile(file)
        warning("File not found: %s (skipping)", file);
        continue;
    end

    T = readtable(file);

    timeVar = find(strcmpi(T.Properties.VariableNames, "Time_ms"), 1);
    lenVar  = find(strcmpi(T.Properties.VariableNames, "InputLen_bytes"), 1);
    ptsVar  = find(strcmpi(T.Properties.VariableNames, "Points"), 1);

    if isempty(timeVar)
        error("Time_ms column not found in %s", file);
    end

    times = T{:, timeVar};

    inputLen = NaN;
    if ~isempty(lenVar), inputLen = T{1, lenVar}; end
    pointsInFile = p;
    if ~isempty(ptsVar), pointsInFile = T{1, ptsVar}; end

    allTimes{end+1} = times; %#ok<SAGROW>
    labels{end+1}   = sprintf('%d points (%d bytes)', pointsInFile, inputLen);

    metaPts(end+1,1) = pointsInFile; %#ok<SAGROW>
    metaLen(end+1,1) = inputLen; %#ok<SAGROW>
end

if isempty(allTimes)
    error("No CSV files were loaded. Check filenames/paths.");
end

% ---- Percentile calculations ----
% Build a results table: one row per points count
nSets = numel(allTimes);
pctVals = nan(nSets, numel(pctList));
meanVals = nan(nSets,1);
stdVals  = nan(nSets,1);
nVals    = nan(nSets,1);

for k = 1:nSets
    times = allTimes{k};
    times = times(~isnan(times));

    nVals(k) = numel(times);
    meanVals(k) = mean(times);
    stdVals(k)  = std(times);

    % prctile expects percentages (0-100)
    pctVals(k,:) = prctile(times, pctList);
end

% Print nicely to Command Window
fprintf("\n=== SHA-256 Timing Percentiles (ms) ===\n");
fprintf("Percentiles: %s\n\n", strjoin(string(pctList), ", "));

for k = 1:nSets
    fprintf("%s | N=%d | mean=%.6f | std=%.6f\n", labels{k}, nVals(k), meanVals(k), stdVals(k));
    for j = 1:numel(pctList)
        fprintf("  P%-5g = %.6f ms\n", pctList(j), pctVals(k,j));
    end
    fprintf("\n");
end

% Optional: save percentiles to CSV
if WRITE_PERCENTILES_CSV
    % Create column names like P50, P90, ...
    pctColNames = "P" + replace(string(pctList), ".", "_");
    R = table(metaPts, metaLen, nVals, meanVals, stdVals, 'VariableNames', ...
        {'Points','InputLen_bytes','N','Mean_ms','Std_ms'});

    for j = 1:numel(pctList)
        R.(pctColNames(j)) = pctVals(:,j);
    end

    writetable(R, percentilesCsvName);
    fprintf("Percentiles CSV written: %s\n", percentilesCsvName);
end

% ---- Shared bin edges across all datasets ----
allConcat = vertcat(allTimes{:});
edges = min(allConcat):binWidthMs:max(allConcat);
centers = edges(1:end-1) + diff(edges)/2;

% ---- Plot overlay (STAIRS) ----
figure('Name','SHA-256 timing distributions (normalized overlay)');
set(gcf, 'Units','centimeters', ...
         'Position',[2 2 FIG_WIDTH_CM FIG_HEIGHT_CM], ...
         'PaperUnits','centimeters', ...
         'PaperSize',[FIG_WIDTH_CM FIG_HEIGHT_CM], ...
         'PaperPositionMode','auto');

hold on;

h = gobjects(nSets, 1); % line handles for legend

for k = 1:nSets
    counts = histcounts(allTimes{k}, edges, 'Normalization', 'probability');
    h(k) = stairs(centers, counts, 'LineWidth', LINE_WIDTH);
end

% ---- Axes formatting ----
grid on;
ax = gca;
ax.FontSize = AXIS_FONT_SIZE;
ax.LineWidth = 1.2;
ax.TickDir = 'out';

xlabel('Time per SHA-256 (ms)', 'FontSize', AXIS_FONT_SIZE);
ylabel('Probability', 'FontSize', AXIS_FONT_SIZE);

title('SHA-256 timing distributions (normalized overlay)', ...
      'FontSize', TITLE_FONT_SIZE, 'FontWeight','normal');

lgd = legend(h, labels, 'Location','northeast');
lgd.FontSize = LEGEND_FONT_SIZE;
lgd.Box = 'on';

hold off;

% ---- Export (optional) ----
% print(gcf, 'sha256_hist_overlay.pdf', '-dpdf', '-painters');
% print(gcf, 'sha256_hist_overlay.png', '-dpng', '-r600');
