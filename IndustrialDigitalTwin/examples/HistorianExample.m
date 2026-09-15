%% HistorianExample
%
%  Demonstrates the Tag Database and Historian features.
%  Shows:
%    - Registering multiple equipment objects
%    - Global tag scanning
%    - Logging historical data to a timetable
%    - Retrieving and plotting from timetables

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================\n');
fprintf('       HISTORIAN & TAG DATABASE EXAMPLE\n');
fprintf('============================================\n\n');

% Add paths
thisDir = fileparts(mfilename('fullpath'));
projectRoot = fullfile(thisDir, '..');
addpath(fullfile(projectRoot, 'library', 'core'));
addpath(fullfile(projectRoot, 'library', 'process'));
addpath(fullfile(projectRoot, 'library', 'instrumentation'));
addpath(fullfile(projectRoot, 'library', 'historian'));

%% 1. CREATE COMPONENTS & SERVER

fprintf('Creating equipment and Database...\n');

% Process Equipment
Tank1 = ETank("ID", "T101", "Diameter", 5, "Height", 10, "InitialLevel", 8);
Pump1 = EPump("ID", "P101", "RatedFlow", 0.5, "RatedHead", 20, "RatedSpeed", 3000);

% Sensors
LT101 = ELevelTransmitter("ID", "LT101", "Target", Tank1, "RangeMax", 10, "NoiseStdDev", 0.05);
FT101 = EFlowTransmitter("ID", "FT101", "Target", Pump1, "RangeMax", 1.0, "NoiseStdDev", 0.01);

% Tag Database (Plant Server)
db = ETagDatabase();
db.register(Tank1);
db.register(Pump1);
db.register(LT101);
db.register(FT101);

% Historian
% We will log everything (default)
historian = EHistorian(db, "BufferSize", 1000);

%% 2. RUN SIMULATION

fprintf('Running simulation and logging data...\n');

dt = 0.5;
simTime = 50;
time = 0:dt:simTime;
N = length(time);

Pump1.start();

for k = 1:N
    t = time(k);
    
    % Physics
    Pump1.update(dt);
    
    flow = 0;
    if Pump1.Outputs.Running
        flow = Pump1.Parameters.Rated.Flow * (Pump1.Outputs.Speed / Pump1.Parameters.Rated.Speed);
    end
    
    Pump1.setInput("FlowRate", flow);
    Tank1.setFlows(0, flow);
    Tank1.update(dt);
    
    % Sensors
    LT101.update(dt);
    FT101.update(dt);
    
    % --- SCADA / HISTORIAN LAYER ---
    % 1. Scan all data into database
    db.scanAll();
    
    % 2. Log data to historian
    historian.log();
end

fprintf('Simulation complete. %d records logged.\n\n', historian.CurrentIndex);

%% 3. DATA RETRIEVAL & ANALYSIS

fprintf('Retrieving Timetables from Historian...\n');

% Retrieve timetables
ttLevel = historian.getHistory("LT101.PV");
ttFlow  = historian.getHistory("FT101.PV");
ttSpeed = historian.getHistory("P101.SPEED");

% Display head of level timetable
disp('Top 5 rows of Level History:');
disp(head(ttLevel, 5));

%% 4. PLOTS

figure('Name', 'Historian Data', 'Position', [100 100 800 600]);

subplot(3,1,1);
% Plot using timetable directly!
plot(ttLevel.Time, ttLevel.Value, 'b-', 'LineWidth', 1.5);
ylabel('Level [m]');
title('Historical Data: LT101.PV (Level)');
grid on;

subplot(3,1,2);
plot(ttFlow.Time, ttFlow.Value, 'g-', 'LineWidth', 1.5);
ylabel('Flow [m3/s]');
title('Historical Data: FT101.PV (Flow)');
grid on;

subplot(3,1,3);
plot(ttSpeed.Time, ttSpeed.Value, 'k-', 'LineWidth', 1.5);
ylabel('Speed [rpm]');
title('Historical Data: P101.SPEED (Pump Speed)');
grid on;

fprintf('\n============================================\n');
fprintf('       EXAMPLE COMPLETE\n');
fprintf('============================================\n\n');
