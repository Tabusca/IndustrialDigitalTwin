classdef ELevelTransmitter < ETransmitter
    % ELevelTransmitter  Industrial level transmitter model.
    %
    %   Subclass of ETransmitter specialized for measuring tank level.
    %   Automatically targets the 'Level' property and assigns meters 'm'
    %   as the engineering unit in tags.
    %
    %   Example:
    %     LT101 = ELevelTransmitter("ID","LT101","Target",Tank1,...
    %         "RangeMax", 15);
    %
    %   See also: ETransmitter, ETank

    methods

        function obj = ELevelTransmitter(options)
            arguments
                options.ID string
                options.Target (1,1) handle
                options.RangeMin (1,1) double = 0
                options.RangeMax (1,1) double = 10
                options.NoiseStdDev (1,1) double {mustBeNonnegative} = 0.01
            end

            obj@ETransmitter("ID", options.ID, "Target", options.Target, ...
                "Property", "Level", "RangeMin", options.RangeMin, ...
                "RangeMax", options.RangeMax, "NoiseStdDev", options.NoiseStdDev);
            
            obj.Type = "LevelTransmitter";
            obj.Description = sprintf("Level Transmitter for %s", options.Target.ID);
        end

        function tags = getTags(obj)
            % getTags  Return transmitter tags with level units.
            tags = getTags@ETransmitter(obj);
            
            idxPV = (tags.Tag == obj.ID + ".PV") | (tags.Tag == obj.ID + ".RAW_PV");
            tags.Unit(idxPV) = "m";
        end

    end
end
