classdef ETankTest < matlab.unittest.TestCase
    % ETankTest  Comprehensive test suite for the ETank class.
    %
    %   This test class validates:
    %     - Construction and parameter validation
    %     - Static behavior (zero flow, steady state)
    %     - Dynamic behavior (filling, emptying, multi-phase)
    %     - Physical limits (clamping at 0 and Height)
    %     - Volume/mass conservation
    %     - Alarm activation and deactivation
    %     - Leakage fault with physical effects
    %     - Sensor failure (NaN outputs, unaffected State)
    %     - Reset behavior
    %     - Tag table structure and values
    %     - Multiple independent instances
    %     - Base class (IndustrialObject/Equipment) interface
    %
    %   Run with:
    %     results = runtests('ETankTest');
    %     disp(results);


    methods (TestClassSetup)

        function addProjectPaths(~)
            % Add library directories to MATLAB path
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
        end

    end


    % ================================================================
    %  CONSTRUCTION TESTS
    % ================================================================

    methods (Test)

        function testValidConstruction(testCase)
            % Verify basic construction with all required parameters

            Tank101 = ETank( ...
                "ID", "Tank101", ...
                "Diameter", 5, ...
                "Height", 10, ...
                "InitialLevel", 3, ...
                "Density", 998);

            testCase.verifyEqual(Tank101.ID, "Tank101");
            testCase.verifyEqual(Tank101.Type, "Tank");
            testCase.verifyEqual(Tank101.State.Level, 3);
            testCase.verifyEqual(Tank101.Parameters.Geometry.Diameter, 5);
            testCase.verifyEqual(Tank101.Parameters.Geometry.Height, 10);
            testCase.verifyEqual(Tank101.Parameters.Fluid.Density, 998);
        end


        function testConstructionDefaults(testCase)
            % Verify default values for optional parameters

            Tank101 = ETank( ...
                "ID", "Tank101", ...
                "Diameter", 5, ...
                "Height", 10);

            % Default InitialLevel = 0
            testCase.verifyEqual(Tank101.State.Level, 0);

            % Default Density = 998 kg/m^3
            testCase.verifyEqual(Tank101.Parameters.Fluid.Density, 998);
        end


        function testComputedGeometry(testCase)
            % Verify that Area and MaxVolume are computed correctly

            D = 4; H = 8;
            Tank101 = ETank("ID", "T1", "Diameter", D, "Height", H);

            expectedArea = pi * D^2 / 4;
            expectedMaxVol = expectedArea * H;

            testCase.verifyEqual(Tank101.Parameters.Geometry.Area, ...
                expectedArea, 'RelTol', 1e-12);
            testCase.verifyEqual(Tank101.Parameters.Geometry.MaxVolume, ...
                expectedMaxVol, 'RelTol', 1e-12);
        end


        function testCustomAlarmLimits(testCase)
            % Verify that custom alarm limits override defaults

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "LevelLL", 0.5, "LevelL", 1.0, ...
                "LevelH", 8.5, "LevelHH", 9.5);

            testCase.verifyEqual(Tank101.Parameters.Limits.LL, 0.5);
            testCase.verifyEqual(Tank101.Parameters.Limits.L, 1.0);
            testCase.verifyEqual(Tank101.Parameters.Limits.H, 8.5);
            testCase.verifyEqual(Tank101.Parameters.Limits.HH, 9.5);
        end


        function testDefaultAlarmLimits(testCase)
            % Verify default alarm limits are percentage of Height

            H = 10;
            Tank101 = ETank("ID", "T1", "Diameter", 5, "Height", H);

            testCase.verifyEqual(Tank101.Parameters.Limits.LL, 0.10 * H);
            testCase.verifyEqual(Tank101.Parameters.Limits.L, 0.20 * H);
            testCase.verifyEqual(Tank101.Parameters.Limits.H, 0.80 * H);
            testCase.verifyEqual(Tank101.Parameters.Limits.HH, 0.90 * H);
        end


        function testInvalidInitialLevel(testCase)
            % InitialLevel > Height must error

            testCase.verifyError(@() ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 15), ...
                "ETank:InvalidInitialLevel");
        end


        function testInvalidAlarmLimitOrder(testCase)
            % Alarm limits must satisfy LL < L < H < HH

            testCase.verifyError(@() ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "LevelLL", 5, "LevelL", 3, ...
                "LevelH", 8, "LevelHH", 9), ...
                "ETank:InvalidAlarmLimits");
        end

    end


    % ================================================================
    %  STATIC BEHAVIOR TESTS
    % ================================================================

    methods (Test)

        function testZeroFlow(testCase)
            % Level must remain constant with zero flow

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            initialLevel = Tank101.State.Level;

            for k = 1:600
                Tank101.update(0.1);
            end

            testCase.verifyEqual(Tank101.State.Level, initialLevel, ...
                'AbsTol', 1e-12);
        end


        function testSteadyState(testCase)
            % Level must remain constant when Qin = Qout

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.setFlows(0.5, 0.5);

            initialLevel = Tank101.State.Level;

            for k = 1:600
                Tank101.update(0.1);
            end

            testCase.verifyEqual(Tank101.State.Level, initialLevel, ...
                'AbsTol', 1e-12);
        end

    end


    % ================================================================
    %  DYNAMIC BEHAVIOR TESTS
    % ================================================================

    methods (Test)

        function testFilling(testCase)
            % Level must increase when Qin > Qout

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 0);

            Tank101.setFlows(0.5, 0);

            for k = 1:100
                Tank101.update(0.1);
            end

            testCase.verifyGreaterThan(Tank101.State.Level, 0);
        end


        function testEmptying(testCase)
            % Level must decrease when Qout > Qin

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 8);

            Tank101.setFlows(0, 0.5);

            for k = 1:100
                Tank101.update(0.1);
            end

            testCase.verifyLessThan(Tank101.State.Level, 8);
        end


        function testGeometryEffect(testCase)
            % Smaller diameter tank fills faster under same flow

            TankSmall = ETank("ID", "Small", "Diameter", 2, "Height", 10);
            TankLarge = ETank("ID", "Large", "Diameter", 5, "Height", 10);

            TankSmall.setFlows(0.5, 0);
            TankLarge.setFlows(0.5, 0);

            for k = 1:100
                TankSmall.update(0.1);
                TankLarge.update(0.1);
            end

            testCase.verifyGreaterThan(TankSmall.State.Level, ...
                TankLarge.State.Level);
        end


        function testFillHoldDrain(testCase)
            % Multi-phase operation: level rises, holds, then falls

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 0);

            dt = 0.1;
            levels = zeros(1, 1800);

            for k = 1:1800
                t = (k-1) * dt;

                if t < 60
                    Tank101.setFlows(0.5, 0.1);
                elseif t < 120
                    Tank101.setFlows(0.2, 0.2);
                else
                    Tank101.setFlows(0.1, 0.5);
                end

                Tank101.update(dt);
                levels(k) = Tank101.State.Level;
            end

            % Peak should be above start
            testCase.verifyGreaterThan(max(levels), levels(1));
            % End should be below peak
            testCase.verifyLessThan(levels(end), max(levels));
        end


        function testDifferentInitialConditions(testCase)
            % Different initial levels are maintained independently

            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 2);
            T2 = ETank("ID", "T2", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 7);

            testCase.verifyEqual(T1.State.Level, 2);
            testCase.verifyEqual(T2.State.Level, 7);
        end

    end


    % ================================================================
    %  PHYSICAL LIMITS TESTS
    % ================================================================

    methods (Test)

        function testLevelLowerBound(testCase)
            % Level must not go below zero

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 1);

            Tank101.setFlows(0, 10);

            for k = 1:200
                Tank101.update(0.1);
            end

            testCase.verifyEqual(Tank101.State.Level, 0);
            testCase.verifyTrue(Tank101.Outputs.IsEmpty);
        end


        function testLevelUpperBound(testCase)
            % Level must not exceed Height

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 9);

            Tank101.setFlows(10, 0);

            for k = 1:200
                Tank101.update(0.1);
            end

            testCase.verifyEqual(Tank101.State.Level, 10);
            testCase.verifyTrue(Tank101.Outputs.IsFull);
        end


        function testNegativeQinError(testCase)
            % Negative Qin must raise an error

            Tank101 = ETank("ID", "T1", "Diameter", 5, "Height", 10);

            testCase.verifyError(@() Tank101.setFlows(-1, 0), ...
                "ETank:NegativeFlow");
        end


        function testNegativeQoutError(testCase)
            % Negative Qout must raise an error

            Tank101 = ETank("ID", "T1", "Diameter", 5, "Height", 10);

            testCase.verifyError(@() Tank101.setFlows(0, -1), ...
                "ETank:NegativeFlow");
        end

    end


    % ================================================================
    %  VOLUME CONSERVATION TEST
    % ================================================================

    methods (Test)

        function testVolumeConservation(testCase)
            % ΔV must equal ∫(Qin - Qout)dt when no clamping occurs
            %
            % Uses a very tall tank (Height=100 m) to avoid hitting
            % physical limits during the test.

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 100, ...
                "InitialLevel", 2);

            Qin = 0.5;
            Qout = 0.2;
            dt = 0.1;
            simTime = 10;

            initialVolume = Tank101.State.Volume;

            Tank101.setFlows(Qin, Qout);

            for k = 1:(simTime / dt)
                Tank101.update(dt);
            end

            expectedVolume = initialVolume + (Qin - Qout) * simTime;
            volumeError = abs(Tank101.State.Volume - expectedVolume);

            testCase.verifyLessThan(volumeError, 1e-10);
        end


        function testVolumeConsistency(testCase)
            % Volume must equal Area * Level at all times

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 3);

            A = Tank101.Parameters.Geometry.Area;

            Tank101.setFlows(0.5, 0.2);

            for k = 1:100
                Tank101.update(0.1);

                expectedVol = A * Tank101.State.Level;
                testCase.verifyEqual(Tank101.State.Volume, ...
                    expectedVol, 'AbsTol', 1e-12);
            end
        end

    end


    % ================================================================
    %  ALARM TESTS
    % ================================================================

    methods (Test)

        function testAlarmLLActivation(testCase)
            % LL alarm activates when level drops below LL setpoint

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            % Initially no LL alarm (level=5, LL=1.0)
            testCase.verifyFalse(Tank101.Alarms.LEVEL_LL);

            % Drain to below LL
            Tank101.setFlows(0, 2);
            for k = 1:500
                Tank101.update(0.1);
            end

            testCase.verifyTrue(Tank101.Alarms.LEVEL_LL);
            testCase.verifyTrue(Tank101.Alarms.LEVEL_L);
        end


        function testAlarmHHActivation(testCase)
            % HH alarm activates when level rises above HH setpoint

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            % Initially no HH alarm (level=5, HH=9.0)
            testCase.verifyFalse(Tank101.Alarms.LEVEL_HH);

            % Fill to above HH
            Tank101.setFlows(2, 0);
            for k = 1:500
                Tank101.update(0.1);
            end

            testCase.verifyTrue(Tank101.Alarms.LEVEL_HH);
            testCase.verifyTrue(Tank101.Alarms.LEVEL_H);
        end


        function testAlarmClearOnRecovery(testCase)
            % Alarms clear when level returns to normal range

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 0);

            % Start empty → LL/L alarms active
            testCase.verifyTrue(Tank101.Alarms.LEVEL_LL);
            testCase.verifyTrue(Tank101.Alarms.LEVEL_L);

            % Fill to mid-range. Area = pi*25/4 ≈ 19.63 m².
            % Need level > L = 2.0 m → need > 39.27 m³ of net inflow.
            % At Qin=5 m³/s for 500 steps of 0.1s = 50s → 250 m³ → level ≈ 12.7 m
            % (clamped to 10). Use moderate flow for realistic test.
            Tank101.setFlows(2, 0);
            for k = 1:500
                Tank101.update(0.1);
            end

            % Level should now be well above L (2.0)
            testCase.verifyFalse(Tank101.Alarms.LEVEL_LL);
            testCase.verifyFalse(Tank101.Alarms.LEVEL_L);
            testCase.verifyFalse(Tank101.Alarms.LEVEL_H);
            testCase.verifyFalse(Tank101.Alarms.LEVEL_HH);
        end


        function testStatusTransitions(testCase)
            % Status reflects alarm and fault severity

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            % Mid-level, no faults → OK
            testCase.verifyEqual(Tank101.Status, "OK");

            % Drain to alarm zone. Area ≈ 19.63 m².
            % Need level < L = 2.0 m → need to remove > 58.9 m³.
            % At Qout=2 m³/s for 500 steps of 0.1s = 50s → remove 100 m³.
            % Level drop ≈ 5.09 m → final ≈ -0.09 → clamped to 0.
            Tank101.setFlows(0, 2);
            for k = 1:500
                Tank101.update(0.1);
            end
            % Level should be at 0 (empty) → LL alarm → CRITICAL
            testCase.verifyTrue(Tank101.Status == "WARNING" ...
                || Tank101.Status == "CRITICAL");

            % Inject fault → FAULTED takes priority
            Tank101.injectFault("Leakage");
            Tank101.update(0.1);
            testCase.verifyEqual(Tank101.Status, "FAULTED");

            % Clear fault → status based on alarms
            Tank101.clearFault("Leakage");
            Tank101.update(0.1);
            testCase.verifyTrue(Tank101.Status ~= "FAULTED");
        end

    end


    % ================================================================
    %  LEAKAGE FAULT TESTS
    % ================================================================

    methods (Test)

        function testLeakageCausesFasterDrain(testCase)
            % A tank with leakage drains faster than one without

            % Tank without leakage
            TankOK = ETank( ...
                "ID", "OK", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 8);

            % Tank with leakage
            TankLeak = ETank( ...
                "ID", "Leak", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 8);
            TankLeak.injectFault("Leakage");

            % Same outflow for both
            TankOK.setFlows(0, 0.2);
            TankLeak.setFlows(0, 0.2);

            for k = 1:200
                TankOK.update(0.1);
                TankLeak.update(0.1);
            end

            % Leaking tank should have lower level
            testCase.verifyLessThan(TankLeak.State.Level, ...
                TankOK.State.Level);
        end


        function testLeakageProportionalToHead(testCase)
            % Leak rate should be higher when tank is fuller
            %
            % A tank starting at level=8 should leak more volume
            % in the first 10s than a tank starting at level=2,
            % since Qleak = k * h.

            TankHigh = ETank("ID", "H", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 8);
            TankLow = ETank("ID", "L", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 2);

            TankHigh.injectFault("Leakage");
            TankLow.injectFault("Leakage");

            % No external flow — only leak
            TankHigh.setFlows(0, 0);
            TankLow.setFlows(0, 0);

            initHighVol = TankHigh.State.Volume;
            initLowVol = TankLow.State.Volume;

            for k = 1:100
                TankHigh.update(0.1);
                TankLow.update(0.1);
            end

            % Volume lost from each tank
            lostHigh = initHighVol - TankHigh.State.Volume;
            lostLow = initLowVol - TankLow.State.Volume;

            % Higher initial level should lose more volume
            testCase.verifyGreaterThan(lostHigh, lostLow);
        end


        function testLeakageClearedRestoresNormal(testCase)
            % After clearing leakage, tank behaves normally

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("Leakage");

            Tank101.setFlows(0, 0);
            for k = 1:50
                Tank101.update(0.1);
            end
            levelWithLeak = Tank101.State.Level;

            % Clear fault
            Tank101.clearFault("Leakage");
            levelAfterClear = Tank101.State.Level;

            % With no flow and no leak, level should stay constant
            for k = 1:50
                Tank101.update(0.1);
            end

            testCase.verifyEqual(Tank101.State.Level, levelAfterClear, ...
                'AbsTol', 1e-12);
        end

    end


    % ================================================================
    %  SENSOR FAILURE TESTS
    % ================================================================

    methods (Test)

        function testSensorFailureOutputNaN(testCase)
            % Sensor failure makes Level and Volume outputs NaN

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("SensorFailure");
            Tank101.update(0.1);

            testCase.verifyTrue(isnan(Tank101.Outputs.Level));
            testCase.verifyTrue(isnan(Tank101.Outputs.Volume));
        end


        function testSensorFailureStateUnaffected(testCase)
            % Physical state must NOT be affected by sensor failure

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("SensorFailure");

            Tank101.setFlows(0.5, 0.2);
            for k = 1:100
                Tank101.update(0.1);
            end

            % State should reflect actual physics
            testCase.verifyGreaterThan(Tank101.State.Level, 5);
            testCase.verifyFalse(isnan(Tank101.State.Level));

            % But output should be NaN
            testCase.verifyTrue(isnan(Tank101.Outputs.Level));
        end


        function testSensorFailureTagQuality(testCase)
            % Tag quality must be "BAD" for level/volume under sensor fault

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("SensorFailure");
            Tank101.update(0.1);

            tags = Tank101.getTags();

            levelIdx = tags.Tag == "T1.LEVEL";
            volumeIdx = tags.Tag == "T1.VOLUME";
            qinIdx = tags.Tag == "T1.QIN";

            testCase.verifyEqual(tags.Quality(levelIdx), "BAD");
            testCase.verifyEqual(tags.Quality(volumeIdx), "BAD");
            % Non-sensor tags should remain GOOD
            testCase.verifyEqual(tags.Quality(qinIdx), "GOOD");
        end


        function testSensorRecovery(testCase)
            % After clearing sensor failure, outputs restore to state

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("SensorFailure");
            Tank101.update(0.1);
            testCase.verifyTrue(isnan(Tank101.Outputs.Level));

            Tank101.clearFault("SensorFailure");
            Tank101.update(0.1);
            testCase.verifyFalse(isnan(Tank101.Outputs.Level));
            testCase.verifyEqual(Tank101.Outputs.Level, ...
                Tank101.State.Level);
        end

    end


    % ================================================================
    %  FAULT MANAGEMENT TESTS
    % ================================================================

    methods (Test)

        function testUnknownFaultError(testCase)
            % Injecting unsupported fault must error

            Tank101 = ETank("ID", "T1", "Diameter", 5, "Height", 10);

            testCase.verifyError(@() Tank101.injectFault("FlyingPigs"), ...
                "Equipment:UnknownFault");
        end


        function testClearAllFaults(testCase)
            % clearAllFaults must deactivate every fault

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("Leakage");
            Tank101.injectFault("SensorFailure");

            testCase.verifyTrue(Tank101.hasFault("Leakage"));
            testCase.verifyTrue(Tank101.hasFault("SensorFailure"));
            testCase.verifyTrue(Tank101.hasAnyFault());

            Tank101.clearAllFaults();

            testCase.verifyFalse(Tank101.hasFault("Leakage"));
            testCase.verifyFalse(Tank101.hasFault("SensorFailure"));
            testCase.verifyFalse(Tank101.hasAnyFault());
        end


        function testHasFaultMethods(testCase)
            % hasFault and hasAnyFault work correctly

            Tank101 = ETank("ID", "T1", "Diameter", 5, "Height", 10);

            testCase.verifyFalse(Tank101.hasAnyFault());
            testCase.verifyFalse(Tank101.hasFault("Leakage"));

            Tank101.injectFault("Leakage");

            testCase.verifyTrue(Tank101.hasAnyFault());
            testCase.verifyTrue(Tank101.hasFault("Leakage"));
            testCase.verifyFalse(Tank101.hasFault("SensorFailure"));
        end

    end


    % ================================================================
    %  RESET TESTS
    % ================================================================

    methods (Test)

        function testReset(testCase)
            % Reset must restore initial level and clear inputs

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 3);

            Tank101.setFlows(1, 0);
            for k = 1:100
                Tank101.update(0.1);
            end

            % Level should have changed
            testCase.verifyNotEqual(Tank101.State.Level, 3);

            Tank101.reset();

            testCase.verifyEqual(Tank101.State.Level, 3, 'AbsTol', 1e-12);
            testCase.verifyEqual(Tank101.Inputs.Qin, 0);
            testCase.verifyEqual(Tank101.Inputs.Qout, 0);
        end


        function testResetClearsFaults(testCase)
            % Reset must clear all active faults

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.injectFault("Leakage");
            Tank101.injectFault("SensorFailure");
            Tank101.reset();

            testCase.verifyFalse(Tank101.Faults.Leakage);
            testCase.verifyFalse(Tank101.Faults.SensorFailure);
        end


        function testResetRestoresOutputs(testCase)
            % After reset, outputs should match initial state

            initLevel = 4;
            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", initLevel);

            Tank101.injectFault("SensorFailure");
            Tank101.setFlows(1, 0);
            Tank101.update(1);

            Tank101.reset();

            testCase.verifyEqual(Tank101.Outputs.Level, initLevel);
            testCase.verifyFalse(isnan(Tank101.Outputs.Level));
        end

    end


    % ================================================================
    %  TAG SYSTEM TESTS
    % ================================================================

    methods (Test)

        function testTagTableStructure(testCase)
            % getTags must return table with correct columns

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            tags = Tank101.getTags();

            testCase.verifyClass(tags, 'table');
            testCase.verifyTrue(ismember('Tag', tags.Properties.VariableNames));
            testCase.verifyTrue(ismember('Value', tags.Properties.VariableNames));
            testCase.verifyTrue(ismember('Unit', tags.Properties.VariableNames));
            testCase.verifyTrue(ismember('Quality', tags.Properties.VariableNames));
            testCase.verifyTrue(ismember('Timestamp', tags.Properties.VariableNames));
        end


        function testTagCount(testCase)
            % ETank should export 13 tags

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            tags = Tank101.getTags();
            testCase.verifyEqual(height(tags), 13);
        end


        function testTagNames(testCase)
            % Verify all expected tag names are present

            Tank101 = ETank( ...
                "ID", "Tank101", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            tags = Tank101.getTags();

            expectedTags = [
                "Tank101.LEVEL"
                "Tank101.VOLUME"
                "Tank101.QIN"
                "Tank101.QOUT"
                "Tank101.IS_FULL"
                "Tank101.IS_EMPTY"
                "Tank101.ALARM_LL"
                "Tank101.ALARM_L"
                "Tank101.ALARM_H"
                "Tank101.ALARM_HH"
                "Tank101.FAULT_LEAKAGE"
                "Tank101.FAULT_SENSOR"
                "Tank101.STATUS"
            ];

            for i = 1:length(expectedTags)
                testCase.verifyTrue(any(tags.Tag == expectedTags(i)), ...
                    sprintf("Missing tag: %s", expectedTags(i)));
            end
        end


        function testTagValues(testCase)
            % Tag values must match current outputs

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            Tank101.setFlows(0.3, 0.1);
            Tank101.update(1);

            tags = Tank101.getTags();

            levelIdx = tags.Tag == "T1.LEVEL";
            testCase.verifyEqual(tags.Value(levelIdx), ...
                Tank101.Outputs.Level, 'AbsTol', 1e-12);

            qinIdx = tags.Tag == "T1.QIN";
            testCase.verifyEqual(tags.Value(qinIdx), 0.3, 'AbsTol', 1e-12);
        end


        function testTagQualityNormal(testCase)
            % All tag qualities should be GOOD under normal operation

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            tags = Tank101.getTags();

            testCase.verifyTrue(all(tags.Quality == "GOOD"));
        end

    end


    % ================================================================
    %  BASE CLASS INTERFACE TESTS
    % ================================================================

    methods (Test)

        function testGetInfo(testCase)
            % getInfo must return struct with ID, Type, Description

            Tank101 = ETank( ...
                "ID", "Tank101", "Diameter", 5, "Height", 10);

            info = Tank101.getInfo();

            testCase.verifyEqual(info.ID, "Tank101");
            testCase.verifyEqual(info.Type, "Tank");
            testCase.verifyClass(info.Description, 'string');
        end


        function testGetDiagnostics(testCase)
            % getDiagnostics must return comprehensive struct

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            diag = Tank101.getDiagnostics();

            testCase.verifyEqual(diag.ID, "T1");
            testCase.verifyEqual(diag.Type, "Tank");
            testCase.verifyTrue(isfield(diag, 'Parameters'));
            testCase.verifyTrue(isfield(diag, 'State'));
            testCase.verifyTrue(isfield(diag, 'Inputs'));
            testCase.verifyTrue(isfield(diag, 'Outputs'));
            testCase.verifyTrue(isfield(diag, 'Alarms'));
            testCase.verifyTrue(isfield(diag, 'Faults'));
            testCase.verifyTrue(isfield(diag, 'Status'));
        end


        function testSetInput(testCase)
            % Generic setInput must work via Equipment base class

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10);

            Tank101.setInput("Qin", 0.5);
            Tank101.setInput("Qout", 0.2);

            testCase.verifyEqual(Tank101.Inputs.Qin, 0.5);
            testCase.verifyEqual(Tank101.Inputs.Qout, 0.2);
        end


        function testHandleSemantics(testCase)
            % Equipment instances must be handle objects (shared reference)

            Tank101 = ETank( ...
                "ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 5);

            % Create an alias (should be same object, not a copy)
            alias = Tank101;
            alias.setFlows(1, 0);
            alias.update(1);

            % Original should reflect the change
            testCase.verifyGreaterThan(Tank101.State.Level, 5);
        end


        function testMultipleInstances(testCase)
            % Different instances must maintain independent state

            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, ...
                "InitialLevel", 2);
            T2 = ETank("ID", "T2", "Diameter", 3, "Height", 8, ...
                "InitialLevel", 6);

            T1.setFlows(0.5, 0);
            T2.setFlows(0, 0.3);

            for k = 1:100
                T1.update(0.1);
                T2.update(0.1);
            end

            % T1 should have risen, T2 should have dropped
            testCase.verifyGreaterThan(T1.State.Level, 2);
            testCase.verifyLessThan(T2.State.Level, 6);
        end


        function testGetArea(testCase)
            % getArea convenience method

            D = 4;
            Tank101 = ETank("ID", "T1", "Diameter", D, "Height", 10);

            expected = pi * D^2 / 4;
            testCase.verifyEqual(Tank101.getArea(), expected, ...
                'RelTol', 1e-12);
        end

    end

end
