classdef ETank < Equipment
    % ETank  Industrial cylindrical tank model.
    %
    %   ETank models a vertical cylindrical tank with constant
    %   cross-section. It simulates fluid level dynamics, alarms,
    %   and fault injection with physically meaningful effects.
    %
    %   Physics:
    %     dh/dt = (Qin - Qout - Qleak) / A
    %
    %     A = pi * D^2 / 4       (cross-sectional area)
    %     V = A * h              (fluid volume)
    %
    %   When the Leakage fault is active:
    %     Qleak = k_leak * h     (flow proportional to hydrostatic head)
    %
    %   Level is physically clamped to [0, Height]. When clamped,
    %   volume conservation is intentionally violated (overflow or
    %   empty conditions — the excess/deficit is treated as lost
    %   to the environment or as air ingestion).
    %
    %   Assumptions:
    %     - Vertical cylindrical geometry (constant cross-section)
    %     - Incompressible fluid
    %     - Well-mixed (uniform level across tank cross-section)
    %     - No thermal effects on fluid volume
    %     - Leakage flow proportional to hydrostatic head (simplified
    %       Torricelli model without velocity coefficient)
    %     - No inertial effects on fluid (quasi-static filling)
    %
    %   Limitations:
    %     - Does not model fluid momentum or sloshing
    %     - Does not model variable-geometry tanks (conical, etc.)
    %     - No temperature tracking (isothermal assumption)
    %     - Leakage model is simplified (constant coefficient)
    %     - Does not model gas phase above liquid
    %
    %   Parameters:
    %     Geometry.Diameter     [m]     - Tank internal diameter
    %     Geometry.Height       [m]     - Tank internal height
    %     Geometry.Area         [m^2]   - Cross-sectional area (computed)
    %     Geometry.MaxVolume    [m^3]   - Maximum capacity (computed)
    %     Fluid.Density         [kg/m^3]- Fluid density
    %     InitialConditions.Level [m]   - Starting fluid level
    %     Limits.LL/L/H/HH     [m]     - Alarm setpoints
    %     Leakage.Coefficient   [m^2/s] - Leak proportionality constant
    %
    %   State (true physics, never corrupted by sensor faults):
    %     Level   [m]     - True physical fluid level
    %     Volume  [m^3]   - True fluid volume
    %
    %   Inputs (set externally via setFlows or setInput):
    %     Qin     [m^3/s] - Inlet volumetric flow rate
    %     Qout    [m^3/s] - Outlet volumetric flow rate
    %
    %   Outputs (what PLC/SCADA sees — affected by sensor faults):
    %     Level   [m]     - Measured level (NaN if sensor failed)
    %     Volume  [m^3]   - Measured volume (NaN if sensor failed)
    %     Qin     [m^3/s] - Inlet flow (echoed from Inputs)
    %     Qout    [m^3/s] - Outlet flow (echoed from Inputs)
    %     IsFull  [bool]  - True when level = Height
    %     IsEmpty [bool]  - True when level = 0
    %
    %   Faults:
    %     Leakage       - Adds Qleak = k * h to mass balance outflow
    %     SensorFailure - Level and Volume outputs become NaN
    %
    %   Alarms:
    %     LEVEL_LL - Level at or below LL setpoint (Critical)
    %     LEVEL_L  - Level at or below L setpoint  (High)
    %     LEVEL_H  - Level at or above H setpoint  (High)
    %     LEVEL_HH - Level at or above HH setpoint (Critical)
    %
    %   Example:
    %     Tank101 = ETank("ID","Tank101","Diameter",5,"Height",10,...
    %         "InitialLevel",3,"Density",998);
    %     Tank101.setFlows(0.5, 0.2);
    %     for k = 1:100
    %         Tank101.update(0.1);
    %     end
    %     disp(Tank101.Outputs.Level);
    %     disp(Tank101.getTags());
    %
    %   See also: Equipment, IndustrialObject


    methods

        function obj = ETank(options)
            % ETank  Construct a cylindrical tank.
            %
            %   Tank = ETank("ID","Tank101","Diameter",5,"Height",10,...)
            %
            %   Required Name-Value Arguments:
            %     ID           - string, unique identifier
            %     Diameter     - double [m], tank internal diameter (>0)
            %     Height       - double [m], tank internal height (>0)
            %
            %   Optional Name-Value Arguments:
            %     InitialLevel       - double [m], starting level (default: 0)
            %     Density            - double [kg/m^3], fluid density (default: 998)
            %     LevelLL            - double [m], LL alarm setpoint (default: 10% of Height)
            %     LevelL             - double [m], L alarm setpoint  (default: 20% of Height)
            %     LevelH             - double [m], H alarm setpoint  (default: 80% of Height)
            %     LevelHH            - double [m], HH alarm setpoint (default: 90% of Height)
            %     LeakageCoefficient - double [m^2/s], leak constant (default: 0.01)

            arguments
                options.ID string
                options.Diameter (1,1) double {mustBePositive}
                options.Height (1,1) double {mustBePositive}
                options.InitialLevel (1,1) double {mustBeNonnegative} = 0
                options.Density (1,1) double {mustBePositive} = 998
                options.LevelLL (1,1) double = NaN
                options.LevelL (1,1) double = NaN
                options.LevelH (1,1) double = NaN
                options.LevelHH (1,1) double = NaN
                options.LeakageCoefficient (1,1) double {mustBeNonnegative} = 0.01
            end


            % --- Validate initial level ---
            if options.InitialLevel > options.Height
                error("ETank:InvalidInitialLevel", ...
                    "InitialLevel (%.2f m) cannot exceed Height (%.2f m).", ...
                    options.InitialLevel, options.Height);
            end


            % --- Identity ---
            obj.ID = options.ID;
            obj.Type = "Tank";
            obj.Description = sprintf( ...
                "Cylindrical tank, D=%.2f m, H=%.2f m", ...
                options.Diameter, options.Height);


            % --- Geometry ---
            A = pi * options.Diameter^2 / 4;

            obj.Parameters.Geometry.Diameter = options.Diameter;
            obj.Parameters.Geometry.Height = options.Height;
            obj.Parameters.Geometry.Area = A;
            obj.Parameters.Geometry.MaxVolume = A * options.Height;


            % --- Fluid ---
            obj.Parameters.Fluid.Density = options.Density;


            % --- Initial conditions ---
            obj.Parameters.InitialConditions.Level = options.InitialLevel;


            % --- Alarm limits ---
            % Default to percentage of height if not explicitly provided
            H = options.Height;

            if isnan(options.LevelLL)
                obj.Parameters.Limits.LL = 0.10 * H;
            else
                obj.Parameters.Limits.LL = options.LevelLL;
            end

            if isnan(options.LevelL)
                obj.Parameters.Limits.L = 0.20 * H;
            else
                obj.Parameters.Limits.L = options.LevelL;
            end

            if isnan(options.LevelH)
                obj.Parameters.Limits.H = 0.80 * H;
            else
                obj.Parameters.Limits.H = options.LevelH;
            end

            if isnan(options.LevelHH)
                obj.Parameters.Limits.HH = 0.90 * H;
            else
                obj.Parameters.Limits.HH = options.LevelHH;
            end

            % Validate alarm limit ordering: LL < L < H < HH
            lim = obj.Parameters.Limits;
            if lim.LL >= lim.L
                error("ETank:InvalidAlarmLimits", ...
                    "LL (%.2f) must be less than L (%.2f).", lim.LL, lim.L);
            end
            if lim.L >= lim.H
                error("ETank:InvalidAlarmLimits", ...
                    "L (%.2f) must be less than H (%.2f).", lim.L, lim.H);
            end
            if lim.H >= lim.HH
                error("ETank:InvalidAlarmLimits", ...
                    "H (%.2f) must be less than HH (%.2f).", lim.H, lim.HH);
            end


            % --- Leakage configuration ---
            obj.Parameters.Leakage.Coefficient = options.LeakageCoefficient;


            % --- Initialize dynamic state ---
            obj.State.Level = options.InitialLevel;
            obj.State.Volume = A * options.InitialLevel;


            % --- Initialize inputs ---
            obj.Inputs.Qin = 0;
            obj.Inputs.Qout = 0;


            % --- Initialize faults ---
            obj.Faults.Leakage = false;
            obj.Faults.SensorFailure = false;


            % --- Compute initial outputs, alarms, status ---
            obj.updateOutputs();
            obj.updateAlarms();
            obj.updateStatus();
        end


        function setFlows(obj, Qin, Qout)
            % setFlows  Convenience method to set inlet and outlet flows.
            %
            %   obj.setFlows(Qin, Qout) sets both flow inputs.
            %   Flows must be non-negative.
            %
            %   This is equivalent to:
            %     obj.setInput("Qin", Qin);
            %     obj.setInput("Qout", Qout);

            arguments
                obj
                Qin (1,1) double
                Qout (1,1) double
            end

            if Qin < 0
                error("ETank:NegativeFlow", ...
                    "Qin cannot be negative (got %.4f m^3/s).", Qin);
            end

            if Qout < 0
                error("ETank:NegativeFlow", ...
                    "Qout cannot be negative (got %.4f m^3/s).", Qout);
            end

            obj.Inputs.Qin = Qin;
            obj.Inputs.Qout = Qout;
        end


        function update(obj, dt)
            % update  Advance tank state by one timestep.
            %
            %   obj.update(dt) integrates the tank mass balance over
            %   timestep dt [seconds] using forward Euler.
            %
            %   Before calling update, set inlet and outlet flows via
            %   setFlows() or setInput().
            %
            %   Physics:
            %     dh/dt = (Qin - Qout - Qleak) / A
            %
            %   If Leakage fault is active:
            %     Qleak = LeakageCoefficient * Level
            %
            %   Level is clamped to [0, Height].

            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            % Read current inputs
            Qin = obj.Inputs.Qin;
            Qout = obj.Inputs.Qout;

            % Compute leakage outflow when fault is active
            % Leak rate is proportional to hydrostatic head:
            % physically, higher liquid column drives more flow
            % through a leak opening (simplified Torricelli)
            Qleak = 0;
            if obj.Faults.Leakage
                Qleak = obj.Parameters.Leakage.Coefficient ...
                    * obj.State.Level;
            end

            % Mass balance: dh/dt = (Qin - Qout - Qleak) / A
            A = obj.Parameters.Geometry.Area;
            dh = (Qin - Qout - Qleak) / A;
            newLevel = obj.State.Level + dh * dt;

            % Physical constraints: level cannot go below zero
            % or above tank height. Clamping intentionally violates
            % volume conservation at boundaries (overflow or empty).
            newLevel = max(0, newLevel);
            newLevel = min(obj.Parameters.Geometry.Height, newLevel);

            % Update true physical state
            obj.State.Level = newLevel;
            obj.State.Volume = A * newLevel;

            % Derive outputs, alarms, status from new state
            obj.updateOutputs();
            obj.updateAlarms();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Restore tank to initial conditions.
            %
            %   obj.reset() returns level to the initial value,
            %   clears all inputs, faults, and alarms.

            initLevel = obj.Parameters.InitialConditions.Level;
            A = obj.Parameters.Geometry.Area;

            % Restore state
            obj.State.Level = initLevel;
            obj.State.Volume = A * initLevel;

            % Clear inputs
            obj.Inputs.Qin = 0;
            obj.Inputs.Qout = 0;

            % Clear all faults
            obj.clearAllFaults();

            % Recompute derived quantities
            obj.updateOutputs();
            obj.updateAlarms();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return tank industrial tags as a table.
            %
            %   tags = obj.getTags() returns a table with columns:
            %     Tag, Value, Unit, Quality, Timestamp
            %
            %   Quality is "BAD" for level/volume tags when the
            %   SensorFailure fault is active.

            now = datetime("now");

            % Level and volume quality depends on sensor health
            if obj.Faults.SensorFailure
                levelQuality = "BAD";
            else
                levelQuality = "GOOD";
            end

            % Status encoded numerically for tag compatibility
            % 0=OK, 1=WARNING, 2=CRITICAL, 3=FAULTED
            statusCode = obj.statusToCode();

            Tag = [
                obj.ID + ".LEVEL"
                obj.ID + ".VOLUME"
                obj.ID + ".QIN"
                obj.ID + ".QOUT"
                obj.ID + ".IS_FULL"
                obj.ID + ".IS_EMPTY"
                obj.ID + ".ALARM_LL"
                obj.ID + ".ALARM_L"
                obj.ID + ".ALARM_H"
                obj.ID + ".ALARM_HH"
                obj.ID + ".FAULT_LEAKAGE"
                obj.ID + ".FAULT_SENSOR"
                obj.ID + ".STATUS"
            ];

            Value = [
                obj.Outputs.Level
                obj.Outputs.Volume
                obj.Outputs.Qin
                obj.Outputs.Qout
                double(obj.Outputs.IsFull)
                double(obj.Outputs.IsEmpty)
                double(obj.Alarms.LEVEL_LL)
                double(obj.Alarms.LEVEL_L)
                double(obj.Alarms.LEVEL_H)
                double(obj.Alarms.LEVEL_HH)
                double(obj.Faults.Leakage)
                double(obj.Faults.SensorFailure)
                statusCode
            ];

            Unit = [
                "m"; "m3"; "m3/s"; "m3/s";
                "-"; "-"; "-"; "-"; "-"; "-"; "-"; "-"; "-"
            ];

            Quality = [
                levelQuality; levelQuality;
                "GOOD"; "GOOD"; "GOOD"; "GOOD";
                "GOOD"; "GOOD"; "GOOD"; "GOOD";
                "GOOD"; "GOOD"; "GOOD"
            ];

            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end


        function A = getArea(obj)
            % getArea  Return the tank cross-sectional area [m^2].
            A = obj.Parameters.Geometry.Area;
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            % getSupportedFaults  Return list of faults supported by ETank.
            %
            %   Leakage       - Physical leak proportional to head
            %   SensorFailure - Level/volume measurement becomes invalid

            faults = ["Leakage", "SensorFailure"];
        end


        function updateOutputs(obj)
            % updateOutputs  Compute measured outputs from physical state.
            %
            %   When SensorFailure is active, level and volume outputs
            %   are set to NaN (representing a lost/invalid measurement).
            %   The true State is never modified by sensor faults.

            if obj.Faults.SensorFailure
                obj.Outputs.Level = NaN;
                obj.Outputs.Volume = NaN;
            else
                obj.Outputs.Level = obj.State.Level;
                obj.Outputs.Volume = obj.State.Volume;
            end

            % Flow inputs are echoed to outputs (no flow measurement
            % model yet — flow sensors will be separate instruments)
            obj.Outputs.Qin = obj.Inputs.Qin;
            obj.Outputs.Qout = obj.Inputs.Qout;

            % Boolean status outputs
            obj.Outputs.IsFull = ...
                (obj.State.Level >= obj.Parameters.Geometry.Height);
            obj.Outputs.IsEmpty = ...
                (obj.State.Level <= 0);
        end


        function updateAlarms(obj)
            % updateAlarms  Evaluate level alarm conditions.
            %
            %   Alarms are evaluated against the TRUE physical level
            %   (State.Level), not the measured output. This reflects
            %   the physical reality: in a real plant, the alarm
            %   condition exists regardless of sensor health.
            %   The sensor failure itself would generate a separate
            %   diagnostic alarm in a full implementation.

            level = obj.State.Level;
            limits = obj.Parameters.Limits;

            obj.Alarms.LEVEL_LL = (level <= limits.LL);
            obj.Alarms.LEVEL_L  = (level <= limits.L);
            obj.Alarms.LEVEL_H  = (level >= limits.H);
            obj.Alarms.LEVEL_HH = (level >= limits.HH);
        end


        function updateStatus(obj)
            % updateStatus  Determine overall equipment health.
            %
            %   Priority order (highest to lowest):
            %     FAULTED  - Any fault is active
            %     CRITICAL - LL or HH alarm active
            %     WARNING  - L or H alarm active
            %     OK       - No faults, no alarms

            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            elseif obj.Alarms.LEVEL_LL || obj.Alarms.LEVEL_HH
                obj.Status = "CRITICAL";
            elseif obj.Alarms.LEVEL_L || obj.Alarms.LEVEL_H
                obj.Status = "WARNING";
            else
                obj.Status = "OK";
            end
        end


        function code = statusToCode(obj)
            % statusToCode  Encode status as numeric value for tags.
            %   0=OK, 1=WARNING, 2=CRITICAL, 3=FAULTED

            switch obj.Status
                case "OK"
                    code = 0;
                case "WARNING"
                    code = 1;
                case "CRITICAL"
                    code = 2;
                case "FAULTED"
                    code = 3;
                otherwise
                    code = -1;
            end
        end

    end

end
