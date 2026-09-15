%% Industrial Digital Twin Framework - Main Entry Point
%
%  This script sets up the MATLAB path for the Industrial Digital Twin
%  framework and provides a starting point for using the library.
%
%  Usage:
%    1. Open MATLAB
%    2. Navigate to the IndustrialDigitalTwin/ directory
%    3. Run this script: >> main
%    4. All library classes are now available
%
%  To run tests:
%    >> results = runtests('tests', 'IncludeSubfolders', true);
%    >> disp(results);
%
%  To run examples:
%    >> TankExample

clear;
clc;

fprintf('\n');
fprintf('=============================================\n');
fprintf('    INDUSTRIAL DIGITAL TWIN FRAMEWORK\n');
fprintf('    Phase 1: Core + Tank\n');
fprintf('=============================================\n\n');

% Get the project root directory
projectRoot = fileparts(mfilename('fullpath'));

% Add library paths
addpath(fullfile(projectRoot, 'library', 'core'));
addpath(fullfile(projectRoot, 'library', 'process'));
addpath(fullfile(projectRoot, 'examples'));

fprintf('Library paths added.\n\n');

% Display available classes
fprintf('Available classes:\n');
fprintf('  IndustrialObject  (abstract base)\n');
fprintf('  Equipment         (abstract equipment base)\n');
fprintf('  ETank             (cylindrical tank model)\n\n');

fprintf('Quick start:\n');
fprintf('  Tank101 = ETank("ID","Tank101","Diameter",5,"Height",10,...\n');
fprintf('      "InitialLevel",3,"Density",998);\n');
fprintf('  Tank101.setFlows(0.5, 0.2);\n');
fprintf('  Tank101.update(0.1);\n');
fprintf('  disp(Tank101.getTags());\n\n');

fprintf('Run tests:\n');
fprintf('  results = runtests(''tests'', ''IncludeSubfolders'', true);\n\n');

fprintf('Run example:\n');
fprintf('  TankExample\n\n');
