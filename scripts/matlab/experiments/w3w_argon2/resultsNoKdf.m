% GeoVault Raw Baseline: SHA-256 Only (With Colored Security Zones)
clear; clc;

% --- Empirical Constants ---
R_SHA256 = 1.32e7;     % Raw SHA-256 H/s
T1 = 1e10;             % Transition to Human-Scale Secure
BIP39_VAL = 1e32;      % BIP-39 Standard

% Spatial Model (n=1 to 5)
H_spatial_bits = [45.7, 72.5, 99.3, 126.1, 152.9]; 
n_points = 1:5;
W_spatial = (2.^H_spatial_bits) ./ R_SHA256;

% Linguistic Model (L=4 to 24)
L_chars = 4:2:24;
H_pwd_bits = L_chars * log2(94); 
W_pwd = (2.^H_pwd_bits) ./ R_SHA256;

% --- Plotting ---
figure('Color', 'w', 'Position', [100, 100, 1000, 700]);
ax_x_min = 1e-2; ax_x_max = 1e45;
hold on;

% 1. DRAW COLORED PANES (Security Zones)
% Red: Insecure
patch([ax_x_min T1 T1 ax_x_min], [0 0 30 30], [1 0.9 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off');
% Yellow: Human-Scale Secure
patch([T1 BIP39_VAL BIP39_VAL T1], [0 0 30 30], [1 1 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off');
% Green: Super Secure (BIP-39)
patch([BIP39_VAL ax_x_max ax_x_max BIP39_VAL], [0 0 30 30], [0.9 1 0.9], 'EdgeColor', 'none', 'HandleVisibility', 'off');

% 2. PLOT DATA
yyaxis left
h1 = semilogx(W_spatial, n_points, '-o', 'LineWidth', 3, 'MarkerSize', 8, 'Color', [0 0.45 0.74], 'MarkerFaceColor', [0 0.45 0.74]);
ylabel('Number of Spatial Points (n)', 'FontSize', 12, 'FontWeight', 'bold');
ax = gca; 
ax.YLim = [0.8 5.2]; ax.YTick = 1:5; ax.YColor = [0 0.2 0.4];

yyaxis right
h2 = semilogx(W_pwd, L_chars, '--s', 'LineWidth', 2.5, 'MarkerSize', 8, 'Color', [0.47 0.67 0.19], 'MarkerFaceColor', [0.47 0.67 0.19]);
ylabel('Random Password Length (Characters)', 'FontSize', 12, 'FontWeight', 'bold');
ax.YLim = [4 26]; ax.YTick = 4:2:26; ax.YColor = [0.2 0.4 0];

% 3. FORMATTING & LABELS
set(gca, 'XScale', 'log');
xlabel('Attacker Work Factor (Seconds, log_{10})', 'FontSize', 12, 'FontWeight', 'bold');
title('Raw Baseline: No KDF Hardening (SHA-256 Only)', 'FontSize', 14, 'FontWeight', 'bold');

% Ensure grid is visible and drawn on top of patches
grid on; 
grid minor;
set(gca, 'Layer', 'top'); 

xlim([ax_x_min ax_x_max]);

% Zone Annotations
text(1e4, 4.8, 'INSECURE ZONE', 'Color', [0.7 0 0], 'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'center');
text(1e21, 4.8, 'HUMAN-SCALE SECURE', 'Color', [0.6 0.5 0], 'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'center');
text(1e38, 4.8, 'SUPER SECURE (BIP-39)', 'Color', [0 0.5 0], 'FontWeight', 'bold', 'FontSize', 11, 'HorizontalAlignment', 'center');

% Move Legend to Upper Left
legend([h1, h2], {'w3w Points (Spatial)', 'Random Password (Linguistic)'}, 'Location', 'northwest');

hold off;