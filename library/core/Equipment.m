classdef (Abstract) Equipment < IndustrialObject
    % Equipment  Abstract base class for all industrial equipment.
    %
    %   Equipment extends IndustrialObject with the standard operational
    %   structure shared by all industrial equipment: configurable
    %   parameters, dynamic state, process inputs/outputs, alarms,
    %   faults, and an overall status indicator.
    %
    %   This class provides concrete implementations for:
    %     - Fault management (inject, clear, validate)
    %     - Generic input setting
    %     - Diagnostics retrieval
    %
    %   Subclasses must implement:
    %     - getSupportedFaults()  (list of valid fault names)
    %     - update(dt)            (physics and state evolution)
    %     - reset()               (return to initial conditions)
    %     - getTags()             (export industrial tag table)
    %
    %   Property Architecture:
    %     Parameters - Struct of configurable parameters (geometry, fluid,
    %                  limits, etc.). Set at construction, read-only during
    %                  simulation.
    %     State      - Struct of true physical state variables (level,
    %                  temperature, pressure). Represents the actual
    %                  process, never corrupted by sensor faults.
    %     Inputs     - Struct of process inputs (flows, commands, setpoints).
    %                  Set externally by the connection/factory system
    %                  before each update() call.
    %     Outputs    - Struct of measured/reported values. This is what
    %                  downstream systems (PLC, SCADA, historian) see.
    %                  Affected by sensor faults and measurement models.
    %     Alarms     - Struct of boolean alarm states.
    %     Faults     - Struct of boolean fault flags.
    %     Status     - Overall equipment health string.
    %
    %   The critical separation is State vs. Outputs:
    %     State  = true physics (never affected by sensor faults)
    %     Outputs = what external systems see (affected by faults)
    %
    %   See also: IndustrialObject, ETank

    properties (SetAccess = protected)

        % Parameters - Equipment configuration (geometry, limits, etc.)
        Parameters struct = struct()

        % State - True physical state variables
        State struct = struct()

        % Inputs - Process inputs set externally before update()
        Inputs struct = struct()

        % Outputs - Measured/reported values (affected by sensor faults)
        Outputs struct = struct()

        % Alarms - Boolean alarm states
        Alarms struct = struct()

        % Faults - Boolean fault flags
        Faults struct = struct()

        % Status - Overall equipment health ("OK","WARNING","CRITICAL","FAULTED")
        Status string = "OK"

    end


    methods (Abstract, Access = protected)

        % getSupportedFaults  Return list of fault names this equipment supports.
        %
        %   faults = obj.getSupportedFaults() returns a string array of
        %   valid fault names that can be injected. For example:
        %     ["Leakage", "SensorFailure"]
        %
        %   This method is called by injectFault/clearFault to validate
        %   the fault name before modifying the Faults struct.
        faults = getSupportedFaults(obj)

    end


    methods

        function setInput(obj, name, value)
            % setInput  Set a named process input.
            %
            %   obj.setInput(name, value) sets Inputs.(name) = value.
            %
            %   This is the generic interface used by the connection system
            %   to feed process variables into equipment. Equipment-specific
            %   convenience methods (e.g., ETank.setFlows) may wrap this.
            %
            %   Example:
            %     Tank101.setInput("Qin", 0.5);

            arguments
                obj
                name string
                value
            end

            obj.Inputs.(name) = value;
        end


        function injectFault(obj, faultName)
            % injectFault  Activate a fault on this equipment.
            %
            %   obj.injectFault(faultName) activates the named fault.
            %   The fault must be in the list returned by
            %   getSupportedFaults(), otherwise an error is raised.
            %
            %   Fault effects are applied during the next update() call.
            %   The specific physical effects depend on the equipment type.
            %
            %   Example:
            %     Tank101.injectFault("Leakage");
            %     Pump101.injectFault("BearingFault");

            arguments
                obj
                faultName string
            end

            supported = obj.getSupportedFaults();

            if ~ismember(faultName, supported)
                error("Equipment:UnknownFault", ...
                    "Unknown fault '%s' for equipment '%s'. " + ...
                    "Supported faults: %s", ...
                    faultName, obj.ID, strjoin(supported, ", "));
            end

            obj.Faults.(faultName) = true;
        end


        function clearFault(obj, faultName)
            % clearFault  Deactivate a specific fault.
            %
            %   obj.clearFault(faultName) deactivates the named fault.
            %   The fault must be in the supported list.
            %
            %   Example:
            %     Tank101.clearFault("Leakage");

            arguments
                obj
                faultName string
            end

            supported = obj.getSupportedFaults();

            if ~ismember(faultName, supported)
                error("Equipment:UnknownFault", ...
                    "Unknown fault '%s' for equipment '%s'. " + ...
                    "Supported faults: %s", ...
                    faultName, obj.ID, strjoin(supported, ", "));
            end

            obj.Faults.(faultName) = false;
        end


        function clearAllFaults(obj)
            % clearAllFaults  Deactivate all faults on this equipment.
            %
            %   obj.clearAllFaults() sets every supported fault to false.

            supported = obj.getSupportedFaults();

            for i = 1:length(supported)
                obj.Faults.(supported(i)) = false;
            end
        end


        function tf = hasFault(obj, faultName)
            % hasFault  Check whether a specific fault is active.
            %
            %   tf = obj.hasFault(faultName) returns true if the named
            %   fault is currently active.

            arguments
                obj
                faultName string
            end

            if isfield(obj.Faults, faultName)
                tf = obj.Faults.(faultName);
            else
                tf = false;
            end
        end


        function tf = hasAnyFault(obj)
            % hasAnyFault  Check whether any fault is currently active.
            %
            %   tf = obj.hasAnyFault() returns true if at least one
            %   supported fault is active.

            supported = obj.getSupportedFaults();
            tf = false;

            for i = 1:length(supported)
                if isfield(obj.Faults, supported(i)) && obj.Faults.(supported(i))
                    tf = true;
                    return;
                end
            end
        end


        function diag = getDiagnostics(obj)
            % getDiagnostics  Return a complete diagnostic snapshot.
            %
            %   diag = obj.getDiagnostics() returns a struct containing
            %   all identification, configuration, state, and status
            %   information for this equipment.
            %
            %   Fields: ID, Type, Description, Status, Parameters, State,
            %           Inputs, Outputs, Alarms, Faults

            diag.ID = obj.ID;
            diag.Type = obj.Type;
            diag.Description = obj.Description;
            diag.Status = obj.Status;
            diag.Parameters = obj.Parameters;
            diag.State = obj.State;
            diag.Inputs = obj.Inputs;
            diag.Outputs = obj.Outputs;
            diag.Alarms = obj.Alarms;
            diag.Faults = obj.Faults;
        end

    end

end
