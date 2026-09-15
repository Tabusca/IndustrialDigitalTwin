classdef (Abstract) IndustrialObject < handle
    % IndustrialObject  Abstract base class for all industrial plant objects.
    %
    %   IndustrialObject is the root of the industrial Digital Twin class
    %   hierarchy. Every object in the simulated plant — equipment, sensors,
    %   actuators — inherits from this class.
    %
    %   It provides:
    %     - Universal identification (ID, Type, Description)
    %     - A standardized tag interface for historian/SCADA integration
    %     - A common lifecycle contract (update, reset)
    %
    %   This class cannot be instantiated directly. Use concrete subclasses
    %   such as ETank, EPump, EValve, etc.
    %
    %   Properties:
    %     ID          - Unique string identifier (e.g., "Tank101")
    %     Type        - Equipment type string (e.g., "Tank")
    %     Description - Human-readable description
    %
    %   Abstract Methods:
    %     getTags()   - Return a table of industrial tags
    %     update(dt)  - Advance the object state by one timestep
    %     reset()     - Restore the object to its initial conditions
    %
    %   Concrete Methods:
    %     getInfo()   - Return a struct with ID, Type, Description
    %
    %   Design Notes:
    %     - Inherits from handle so that objects are passed by reference.
    %       When a Factory and a Connection both hold a reference to
    %       Tank101, they share the same instance.
    %     - The tag interface (getTags) is the universal data exchange
    %       contract between the Digital Twin and external systems
    %       (Historian, SCADA, OPC UA, SQL, AI/ML).
    %
    %   See also: Equipment, ETank

    properties (SetAccess = protected)

        % ID - Unique identifier for this object (e.g., "Tank101")
        ID string

        % Type - Equipment type (e.g., "Tank", "Pump", "Valve")
        Type string

        % Description - Human-readable description of this object
        Description string

    end


    methods (Abstract)

        % getTags  Return industrial tags as a standardized table.
        %
        %   tags = obj.getTags() returns a table with columns:
        %     Tag       - string  (e.g., "Tank101.LEVEL")
        %     Value     - double  (current value)
        %     Unit      - string  (engineering unit, e.g., "m", "m3/s")
        %     Quality   - string  ("GOOD", "BAD", "UNCERTAIN")
        %     Timestamp - datetime (simulation time or wall clock)
        %
        %   This format is compatible with OPC UA, SQL historians,
        %   and SCADA tag databases.
        tags = getTags(obj)

        % update  Advance the object state by one simulation timestep.
        %
        %   obj.update(dt) where dt is the timestep in seconds.
        %
        %   Before calling update, external systems (Factory, Connection)
        %   must set the object's Inputs via setInput(). The update method:
        %     1. Reads Inputs
        %     2. Applies physics to update State
        %     3. Applies fault effects
        %     4. Computes Outputs (with sensor/fault models)
        %     5. Evaluates alarms
        update(obj, dt)

        % reset  Restore the object to its initial conditions.
        %
        %   obj.reset() returns the object to the state defined at
        %   construction time. Clears all faults, resets alarms,
        %   and restores initial state values.
        reset(obj)

    end


    methods

        function info = getInfo(obj)
            % getInfo  Return identification information as a struct.
            %
            %   info = obj.getInfo() returns a struct with fields:
            %     ID          - string
            %     Type        - string
            %     Description - string
            %
            %   Example:
            %     Tank101 = ETank("ID","Tank101","Diameter",5,...);
            %     info = Tank101.getInfo();
            %     disp(info.ID);  % "Tank101"

            info.ID = obj.ID;
            info.Type = obj.Type;
            info.Description = obj.Description;
        end

    end

end
