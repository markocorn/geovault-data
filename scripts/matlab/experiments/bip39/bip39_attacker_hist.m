% bip39_gpu_defender_hist.m
% Reads RAW Hashcat benchmark CSV (from bip39_gpu_hashcat_raw.csv),
% converts SpeedNum+SpeedUnit -> hashes/s, scales 999->2048, computes
% time per BIP-39 check (ms), prints N + stats, and draws a histogram.
%
% Input CSV columns expected:
%   Timestamp,Run,DeviceFilter,Workload,SpeedLine,SpeedNum,SpeedUnit

clear; clc;

% ---- Configure ----
csvFile = "bip39_gpu_hashcat_raw.csv";  % <-- your raw file
iters_hashcat = 999;                   % hashcat benchmark iterations for mode 12100 (as shown in output)
iters_bip39   = 2048;                  % BIP-39 cost

% ---- Load ----
T = readtable(csvFile, 'TextType','string');

% ---- Extract & sanitize speed ----
speedNum = T.SpeedNum;
if ~isnumeric(speedNum)
    speedNum = str2double(string(speedNum));
end
speedUnit = string(T.SpeedUnit);

% Drop invalid rows
valid = ~isnan(speedNum) & speedNum > 0 & strlength(speedUnit) > 0;
speedNum = speedNum(valid);
speedUnit = speedUnit(valid);

% ---- Convert unit to multiplier ----
mult = nan(size(speedNum));
mult(speedUnit == "H/s")  = 1;
mult(speedUnit == "kH/s") = 1e3;
mult(speedUnit == "MH/s") = 1e6;
mult(speedUnit == "GH/s") = 1e9;

% If any unexpected units appear, fail loudly (better than silently wrong)
if any(isnan(mult))
    bad = unique(speedUnit(isnan(mult)));
    error("Unexpected SpeedUnit(s): %s", strjoin(bad, ", "));
end

% ---- Throughput and time ----
R999  = speedNum .* mult;                        % hashes/s at hashcat's iteration count
R2048 = R999 .* (iters_hashcat / iters_bip39);   % scaled to BIP-39 2048 iters
time_ms = 1000 ./ R2048;                         % ms per BIP-39 check

% ---- N and stats ----
N = numel(time_ms);
mu  = mean(time_ms);
sig = std(time_ms);              % sample std
med = median(time_ms);
p = prctile(time_ms, [90 95 99]);

fprintf("File: %s\n", csvFile);
fprintf("N samples          : %d\n", N);
fprintf("Mean time (ms)     : %.6f\n", mu);
fprintf("Std dev (ms)       : %.6f\n", sig);
fprintf("Median time (ms)   : %.6f\n", med);
fprintf("P90/P95/P99 (ms)   : %.6f  %.6f  %.6f\n", p(1), p(2), p(3));
fprintf("Mean throughput    : %.3f checks/s\n", mean(R2048));

% ---- Histogram ----
figure;
histogram(time_ms, 'BinMethod', 'fd'); % good default for skewed data
grid on;
xlabel("Time per BIP-39 check (ms)  [scaled from hashcat]");
ylabel("Count");
title(sprintf("GPU PBKDF2 Defender-Cost Histogram (N=%d)", N), 'Interpreter','none');

% Overlay median + P95 + P99 (more meaningful than mean±std for skew)
hold on;
yl = ylim;
xline(med, '-', sprintf(' median=%.4f', med), 'LabelVerticalAlignment','middle');
xline(p(2), '--', sprintf(' P95=%.4f', p(2)), 'LabelVerticalAlignment','middle');
xline(p(3), '--', sprintf(' P99=%.4f', p(3)), 'LabelVerticalAlignment','middle');
ylim(yl);
hold off;
