classdef ETagDatabaseTest < matlab.unittest.TestCase
    % ETagDatabaseTest  Test suite for Tag Database.

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..', '..');
            addpath(fullfile(projectRoot, 'library', 'core'));
            addpath(fullfile(projectRoot, 'library', 'process'));
            addpath(fullfile(projectRoot, 'library', 'historian'));
        end
    end

    methods (Test)
        function testRegistrationAndScanning(testCase)
            db = ETagDatabase();
            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 5);
            P1 = EPump("ID", "P1", "RatedFlow", 1.0, "RatedHead", 50);
            
            db.register(T1);
            db.register(P1);
            
            testCase.verifyEqual(length(db.EquipmentList), 2);
            
            % Scan
            tbl = db.scanAll();
            
            % Check master table
            testCase.verifyNotEmpty(tbl);
            testCase.verifyTrue(ismember('T1.LEVEL', tbl.Tag));
            testCase.verifyTrue(ismember('P1.SPEED', tbl.Tag));
        end

        function testReadTag(testCase)
            db = ETagDatabase();
            T1 = ETank("ID", "T1", "Diameter", 5, "Height", 10, "InitialLevel", 7.5);
            db.register(T1);
            db.scanAll();
            
            val = db.readTag("T1.LEVEL");
            testCase.verifyEqual(val, 7.5);
        end
        
        function testTagNotFound(testCase)
            db = ETagDatabase();
            testCase.verifyError(@() db.readTag("NONEXISTENT"), "ETagDatabase:TagNotFound");
        end
    end
end
