% w3w_workfactor_vs_radius_km_export.m
% Attacker-adjusted work factor vs radius for multi-point W3W (no KDF)
% Updates:
% 1. Legend is now HORIZONTAL.
% 2. Exports to PDF.

clear; clc;

% ---------------- Parameters ----------------
R_MAX_KM  = 50;
N_SAMPLES = 100000;

% ---------------- Constants -----------------
H_cell = 45.7;     % entropy of one W3W cell (bits)
A_cell = 9;        % cell area (m^2)

% BIP-39 attacker baseline
W_BIP39_years = 1.68e25;
SEC_PER_YEAR  = 365.25*24*3600;
W_BIP39_sec   = W_BIP39_years * SEC_PER_YEAR;

% Empirical GPU SHA-256 rates (H/s)
R_GPU = zeros(1,5);
R_GPU(1) = mean([13025615,13165669,13359177]);
R_GPU(2) = mean([12447492,12189154,12226692]);
R_GPU(3) = mean([11018685,11193300,11193692]);
R_GPU(4) = mean([10690131,10738308,10695015]);
R_GPU(5) = mean([9789362,9797323,9735438]);

% ---------------- Radius vector -------------
r_km = linspace(0, R_MAX_KM, N_SAMPLES);
r_m  = r_km * 1000;
r_m(r_m == 0) = eps;

% ---------------- Local entropy -------------
H_r_raw = log2(pi .* r_m.^2 ./ A_cell);
H_r     = max(0, H_r_raw);

% ---------------- Plot ----------------------
figure('Color', 'w', 'Position', [100, 100, 800, 600]); 
hold on; grid on;

colors = lines(5);
for n = 1:5
    if n == 1
        H_total = H_cell * ones(size(r_km));
    else
        H_total = H_cell + (n-1).*H_r;
    end
    % Attacker work factor
    W_attacker = 2.^H_total ./ R_GPU(n);
    plot(r_km, W_attacker, 'LineWidth', 2, 'Color', colors(n,:));
end

% ---------------- BIP-39 reference ----------
yline(W_BIP39_sec, '--k', 'LineWidth', 2, ...
    'Label', 'BIP-39 attacker work factor', ...
    'LabelHorizontalAlignment', 'left');

% ---------------- Axes ----------------------
set(gca, 'YScale', 'log');
xlabel('Radius r (km)');
ylabel('Attacker work factor (seconds)');
title('Attacker work factor vs. radius for multi-point W3W (no KDF)');
ylim([1e0, 1e50]);
xlim([0, R_MAX_KM]);

% ---------------- LEGEND (Horizontal) -------
legend( ...
    '1 point', '2 points', '3 points', '4 points', '5 points', ...
    'Location', 'north', ...          % Top Center
    'Orientation', 'horizontal');     % Horizontal Stack

% ---------------- EXPORT ----------------
exportgraphics(gcf, 'w3w_workfactor_no_kdf.pdf', 'ContentType', 'vector');
fprintf('\nFigure exported to w3w_workfactor_no_kdf.pdf\n');

% ---------------- Console summary ----------------
fprintf('\nAttacker work factor summary (no KDF):\n');
fprintf('BIP-39 baseline: W ≈ %.3e years (%.3e seconds)\n', ...
    W_BIP39_years, W_BIP39_sec);
fprintf('-------------------------------------------------------------\n');
for n = 1:5
    if n == 1
        H_total = H_cell;
        W_const = 2^H_total / R_GPU(n);
        fprintf('1 point:\n');
        fprintf('  Entropy          : %.1f bits (fixed)\n', H_total);
        fprintf('  Work factor      : %.3e seconds (%.3e years)\n', ...
            W_const, W_const / SEC_PER_YEAR);
        fprintf('  Status           : insufficient (no radius dependence)\n\n');
        continue;
    end
    H_total = H_cell + (n-1).*H_r;
    W_attacker = 2.^H_total ./ R_GPU(n);
    idx = find(W_attacker >= W_BIP39_sec, 1, 'first');
    if isempty(idx)
        W_max = W_attacker(end);
        H_max = H_total(end);
        fprintf('%d points:\n', n);
        fprintf('  Max radius       : %.0f km\n', R_MAX_KM);
        fprintf('  Entropy @ max r  : %.1f bits\n', H_max);
        fprintf('  Work factor @ r  : %.3e seconds (%.3e years)\n', ...
            W_max, W_max / SEC_PER_YEAR);
        fprintf('  Status           : insufficient (below BIP-39)\n\n');
    else
        if idx == 1
            r_cross = r_km(1);
        else
            r1 = r_km(idx-1); r2 = r_km(idx);
            W1 = W_attacker(idx-1); W2 = W_attacker(idx);
            r_cross = r1 + (W_BIP39_sec - W1) * (r2 - r1) / (W2 - W1);
        end
        fprintf('%d points:\n', n);
        fprintf('  Radius required  : %.3f km\n', r_cross);
        fprintf('  Status           : matches BIP-39 work factor\n\n');
    end
end
fprintf('-------------------------------------------------------------\n');