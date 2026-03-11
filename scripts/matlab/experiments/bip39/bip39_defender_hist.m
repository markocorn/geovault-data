% defender_histogram.m
% Reads raw CSV results from your defender benchmark and plots a histogram.
% Works for both:
%   CPU CSV: Run,Time_ms
%   GPU CSV: Run,R999_hashes_per_s,R2048_hashes_per_s,Time_ms_per_check
%
% It will automatically pick the right column:
%   - If Time_ms exists -> use it
%   - Else if Time_ms_per_check exists -> use it
%
% Also prints mean/std and overlays them on the plot.

clear; clc;

% ---- Configure ----
csvFile = "bip39_cpu_raw_results.csv";     % <-- change to your file
% csvFile = "bip39_gpu_pbkdf2_raw_results.csv";

% ---- Load ----
T = readtable(csvFile);

% ---- Detect the time column ----
if any(strcmpi(T.Properties.VariableNames, "Time_ms"))
    time_ms = T.Time_ms;
    label = "Time per check (ms)";
elseif any(strcmpi(T.Properties.VariableNames, "Time_ms_per_check"))
    time_ms = T.Time_ms_per_check;
    label = "Time per check (ms)";
else
    error("Could not find Time_ms or Time_ms_per_check column in %s", csvFile);
end

% Ensure numeric column (sometimes imported as cell/string)
if ~isnumeric(time_ms)
    time_ms = str2double(string(time_ms));
end

time_ms = time_ms(~isnan(time_ms)); % drop any NaNs

% ---- Stats ----
mu  = mean(time_ms);
sig = std(time_ms);      % sample std (N-1)
tps = 1000 / mu;

fprintf("File: %s\n", csvFile);
fprintf("N samples          : %d\n", numel(time_ms));
fprintf("Mean time (ms)     : %.6f\n", mu);
fprintf("Std dev (ms)       : %.6f\n", sig);
fprintf("Throughput (1/s)   : %.2f checks/s\n", tps);

% ---- Plot histogram ----
figure;
histogram(time_ms, 'BinMethod', 'fd'); % Freedman–Diaconis rule (good default)
grid on;
xlabel(label);
ylabel("Count");
title(sprintf("Defender Benchmark Histogram (%s)", csvFile), 'Interpreter','none');

% ---- Overlay mean & std lines ----
hold on;
yl = ylim;

xline(mu, '-', sprintf(' mean = %.4f ms', mu), ...
    'LabelOrientation','horizontal', 'LabelVerticalAlignment','middle');

xline(mu - sig, '--', sprintf(' -1σ = %.4f', mu - sig), ...
    'LabelOrientation','horizontal', 'LabelVerticalAlignment','middle');

xline(mu + sig, '--', sprintf(' +1σ = %.4f', mu + sig), ...
    'LabelOrientation','horizontal', 'LabelVerticalAlignment','middle');

ylim(yl);
hold off;

[h,p] = lillietest(time_ms);   % Kolmogorov–Smirnov
[h2,p2] = jbtest(time_ms);     % Jarque–Bera

median(time_ms)
prctile(time_ms,[50 90 95 99])


