classdef EFactory < handle
    % EFactory  Container for all plant components.
    %
    %   Holds equipment, instruments, and connections.
    %   Manages the ETagDatabase and EHistorian.

    properties
        Equipment (1,:) cell = {}
        Connections (1,:) cell = {}
        Database 
        Historian 
    end
    
    methods
        function obj = EFactory()
            obj.Database = ETagDatabase();
            obj.Historian = EHistorian(obj.Database);
        end
        
        function add(obj, component)
            if isa(component, 'Equipment')
                obj.Equipment{end+1} = component;
                obj.Database.register(component);
            elseif isa(component, 'EConnection')
                obj.Connections{end+1} = component;
            end
        end
        
        function update(obj, dt)
            % 1. Update all connections (transfer outputs to inputs)
            for i = 1:length(obj.Connections)
                obj.Connections{i}.update();
            end
            
            % 2. Update all equipment (physics step)
            for i = 1:length(obj.Equipment)
                obj.Equipment{i}.update(dt);
            end
            
            % 3. Update database and log to historian
            obj.Database.scanAll();
            obj.Historian.log();
        end
    end
end
