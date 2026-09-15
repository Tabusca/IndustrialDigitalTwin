%% InstrumentationExample
%
%  Demonstrates the use of transmitters to monitor a process.
%  Shows:
%    - Adding sensors to equipment
%    - Noise and calibration drift
%    - Fault injection (Signal Loss, Freeze)
%    - Difference between "ground truth" and "measured" values

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================\n');
fprintf('       INSTRUMENTATION EXAMPLE\n');
fprintf('============================================\n\n');

% Add paths
thisDir = fileparts(mfilename('fullpath'));
projectRoot = fullfile(thisDir, '..');
addpath(fullfile(projectRoot, 'library', 'core'));
addpath(fullfile(projectRoot, 'library', 'process'));
addpath(fullfile(projectRoot, 'library', 'instrumentation'));

%% 1. CREATE COMPONENTS

fprintf('Creating equipment and sensors...\n');

% Process Equipment
Tank1 = ETank("ID", "T101", "Diameter", 5, "Height", 10, "InitialLevel", 8);
Pump1 = EPump("ID", "P101", "RatedFlow", 0.5, "RatedHead", 20, "RatedSpeed", 3000);
CV1   = EControlValve("ID", "CV101", "Characteristic", "linear");

% Instrumentation
% Level Transmitter on Tank1 (Range 0-10m, slightly noisy)
LT101 = ELevelTransmitter("ID", "LT101", "Target", Tank1, ...
    "RangeMin", 0, "RangeMax", 10, "NoiseStdDev", 0.05);

% Flow Transmitter on Pump1 (Range 0-1.0 m3/s)
FT101 = EFlowTransmitter("ID", "FT101", "Target", Pump1, ...
    "RangeMin", 0, "RangeMax", 1.0, "NoiseStdDev", 0.01);

fprintf('System: T101 -> P101 -> CV101\n');
fprintf('Sensors: LT101 (Level), FT101 (Flow)\n\n');

%% 2. SIMULATION SETUP

dt = 0.1;
simTime = 100;
time = 0:dt:simTime;
N = length(time);

% Data arrays
trueLevel = zeros(1, N);
measLevel = zeros(1, N);
ltSignal  = zeros(1, N);

trueFlow = zeros(1, N);
measFlow = zeros(1, N);

%% 3. RUN SIMULATION

fprintf('Running simulation...\n');

Pump1.start();
CV1.setCommand(50); % Open valve to 50%

for k = 1:N
    t = time(k);
    
    % --- Fault Sequence ---
    if t == 30
        fprintf('  [t=%.1fs] INJECTING: FT101 Calibration Drift (+20%% span)\n', t);
        FT101.injectFault("CalibrationLoss");
    end
    if t == 50
        fprintf('  [t=%.1fs] INJECTING: LT101 Frozen Signal\n', t);
        LT101.injectFault("FrozenSignal");
    end
    if t == 70
        fprintf('  [t=%.1fs] INJECTING: LT101 Signal Loss (Cable Break)\n', t);
        LT101.injectFault("SignalLoss"); % overrides frozen
    end
    
    % --- Process Update ---
    Pump1.update(dt);
    CV1.update(dt);
    
    % Simplified flow model: Pump flow modulated by CV
    if Pump1.Outputs.Running
        flow = 0.5 * CV1.Outputs.Position;
    else
        flow = 0;
    end
    
    % Feed actual flow back to pump for power/head calculation
    Pump1.setInput("FlowRate", flow);
    
    Tank1.setFlows(0, flow);
    Tank1.update(dt);
    
    % --- Sensor Update ---
    LT101.update(dt);
    FT101.update(dt);
    
    % --- Record data ---
    trueLevel(k) = Tank1.Outputs.Level;
    measLevel(k) = LT101.Outputs.MeasuredValue;
    ltSignal(k)  = LT101.Outputs.ElectricalSignal;
    
    trueFlow(k)  = flow;
    measFlow(k)  = FT101.Outputs.MeasuredValue;
end

fprintf('Simulation complete.\n\n');

%% 4. PLOTS

figure('Name', 'Instrumentation Data', 'Position', [100 100 900 600]);

% Tank Level Plot
subplot(3,1,1);
plot(time, trueLevel, 'k--', 'LineWidth', 1.5); hold on;
plot(time, measLevel, 'b-', 'LineWidth', 1.0);
ylabel('Level [m]');
title('LT101 vs True Tank Level');
legend('True Level (State)', 'Measured Level (Transmitter)');
grid on;
% Highlight faults
xline(50, 'r:', 'LT101 Freeze');
xline(70, 'r:', 'LT101 Loss');

% Electrical Signal Plot
subplot(3,1,2);
plot(time, ltSignal, 'm-', 'LineWidth', 1.5);
ylabel('Current [mA]');
title('LT101 Electrical Signal (4-20mA loop)');
ylim([-1 22]);
grid on;

% Flow Plot
subplot(3,1,3);
plot(time, trueFlow, 'k--', 'LineWidth', 1.5); hold on;
plot(time, measFlow, 'g-', 'LineWidth', 1.0);
xlabel('Time [s]');
ylabel('Flow [m3/s]');
title('FT101 vs True Pump Flow');
legend('True Flow', 'Measured Flow');
grid on;
xline(30, 'r:', 'FT101 Cal. Drift');

fprintf('\n============================================\n');
fprintf('       EXAMPLE COMPLETE\n');
fprintf('============================================\n\n');
