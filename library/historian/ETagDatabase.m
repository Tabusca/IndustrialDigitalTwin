classdef ETagDatabase < handle
    % ETagDatabase  Central registry for all plant equipment and tags.
    %
    %   The Tag Database acts as the centralized Plant Server (like an
    %   OPC UA Server). It maintains references to all Equipment objects,
    %   scans them to aggregate their tags, and provides a unified master
    %   table of the entire plant state.
    %
    %   Features:
    %     - Equipment registration
    %     - Global tag scanning (scanAll)
    %     - Tag lookup by name
    %
    %   Example:
    %     db = ETagDatabase();
    %     db.register(Tank1);
    %     db.register(Pump1);
    %     db.scanAll();
    %     val = db.readTag("P101.SPEED");
    %
    %   See also: EHistorian, Equipment

    properties (SetAccess = protected)
        EquipmentList (1,:) cell = {}
        MasterTagTable table
        TagMap containers.Map
    end

    methods
        function obj = ETagDatabase()
            % ETagDatabase  Construct a tag database.
            
            % Initialize empty tag map for fast lookups
            obj.TagMap = containers.Map('KeyType', 'char', 'ValueType', 'any');
            
            % Initialize empty master table
            obj.MasterTagTable = table([], [], [], [], [], ...
                'VariableNames', {'Tag', 'Value', 'Unit', 'Quality', 'Timestamp'});
        end

        function register(obj, eq)
            % register  Add an Equipment object to the database.
            %
            %   obj.register(eq) where eq is an instance of Equipment.

            arguments
                obj
                eq (1,1) Equipment
            end

            obj.EquipmentList{end+1} = eq;
        end

        function tbl = scanAll(obj)
            % scanAll  Poll all registered equipment and aggregate tags.
            %
            %   tbl = obj.scanAll() queries getTags() on every registered
            %   equipment, builds the MasterTagTable, and updates the fast
            %   lookup map.

            if isempty(obj.EquipmentList)
                tbl = obj.MasterTagTable;
                return;
            end

            % Preallocate cell array to collect tables
            numEq = length(obj.EquipmentList);
            tables = cell(1, numEq);

            for i = 1:numEq
                tables{i} = obj.EquipmentList{i}.getTags();
            end

            % Vertically concatenate all tables
            obj.MasterTagTable = vertcat(tables{:});

            % Update the fast lookup map
            % Convert to cell arrays for fast map assignment
            tags = cellstr(obj.MasterTagTable.Tag);
            
            % We store a struct with Value, Unit, Quality, Timestamp in the map
            for i = 1:length(tags)
                tagInfo.Value = obj.MasterTagTable.Value(i);
                tagInfo.Unit = obj.MasterTagTable.Unit(i);
                tagInfo.Quality = obj.MasterTagTable.Quality(i);
                tagInfo.Timestamp = obj.MasterTagTable.Timestamp(i);
                
                obj.TagMap(tags{i}) = tagInfo;
            end

            tbl = obj.MasterTagTable;
        end

        function val = readTag(obj, tagName)
            % readTag  Read the current value of a specific tag.
            %
            %   val = obj.readTag(tagName) returns the numeric value.
            %   Throws an error if the tag does not exist.

            arguments
                obj
                tagName (1,1) string
            end

            key = char(tagName);
            if obj.TagMap.isKey(key)
                tagInfo = obj.TagMap(key);
                val = tagInfo.Value;
            else
                error("ETagDatabase:TagNotFound", ...
                    "Tag '%s' not found in database.", tagName);
            end
        end
        
        function info = getTagInfo(obj, tagName)
            % getTagInfo  Read full info (Value, Unit, Quality, Timestamp).
            %
            %   info = obj.getTagInfo(tagName) returns a struct.

            arguments
                obj
                tagName (1,1) string
            end

            key = char(tagName);
            if obj.TagMap.isKey(key)
                info = obj.TagMap(key);
            else
                error("ETagDatabase:TagNotFound", ...
                    "Tag '%s' not found in database.", tagName);
            end
        end

    end
end
