classdef EPipeTest < matlab.unittest.TestCase
    % EPipeTest  Comprehensive test suite for the EPipe class.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
        end
    end

    methods (Test)
        function testConstruction(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5);
            testCase.verifyEqual(P1.ID, "P1");
            testCase.verifyEqual(P1.Parameters.Geometry.Length, 100);
            testCase.verifyEqual(P1.Parameters.Geometry.Diameter, 0.5);
            testCase.verifyEqual(P1.Parameters.Geometry.Area, pi * 0.5^2 / 4, 'RelTol', 1e-12);
        end

        function testPressureDropFriction(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5, "FrictionFactor", 0.02, "FluidDensity", 1000);
            A = pi * 0.5^2 / 4;
            R = 0.02 * 100 * 1000 / (2 * 0.5 * A^2);
            Q = 0.1;
            P1.setFlow(Q);
            P1.update(1);
            
            expectedDP = R * Q^2;
            testCase.verifyEqual(P1.Outputs.PressureDrop, expectedDP, 'RelTol', 1e-12);
        end

        function testPressureDropElevation(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5, "ElevationChange", 10, "FluidDensity", 1000);
            P1.setFlow(0); % No flow, only static head
            P1.update(1);
            
            expectedDP = 1000 * 9.81 * 10;
            testCase.verifyEqual(P1.Outputs.PressureDrop, expectedDP, 'RelTol', 1e-12);
        end

        function testBlockageFault(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5, "BlockageFactor", 10);
            Q = 0.1;
            
            P1.setFlow(Q);
            P1.update(1);
            dpNormal = P1.Outputs.PressureDrop;
            
            P1.injectFault("Blockage");
            P1.update(1);
            dpBlocked = P1.Outputs.PressureDrop;
            
            testCase.verifyEqual(dpBlocked, dpNormal * 10, 'RelTol', 1e-12);
        end

        function testLeakFault(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5, "LeakFraction", 0.2);
            Q = 0.1;
            
            P1.setFlow(Q);
            P1.injectFault("Leak");
            P1.update(1);
            
            testCase.verifyEqual(P1.Outputs.FlowRate, Q * 0.8, 'RelTol', 1e-12);
        end

        function testReset(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5);
            P1.setFlow(0.5);
            P1.injectFault("Leak");
            P1.update(1);
            
            P1.reset();
            testCase.verifyEqual(P1.Outputs.FlowRate, 0);
            testCase.verifyEqual(P1.Outputs.PressureDrop, 0);
            testCase.verifyFalse(P1.Faults.Leak);
        end
        
        function testTags(testCase)
            P1 = EPipe("ID", "P1", "Length", 100, "Diameter", 0.5);
            tags = P1.getTags();
            testCase.verifyEqual(height(tags), 6);
            testCase.verifyTrue(ismember('Tag', tags.Properties.VariableNames));
            testCase.verifyTrue(any(tags.Tag == "P1.PRESSURE_DROP"));
        end
    end
end
