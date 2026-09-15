classdef EPipe < Equipment
    % EPipe  Industrial pipe model for fluid transport.
    %
    %   EPipe models pressure drop through a straight pipe using a
    %   simplified Darcy-Weisbach resistance model.
    %
    %   Physics:
    %     ΔP_friction  = R * Q * |Q|
    %     ΔP_elevation = ρ * g * Δz
    %     ΔP_total     = ΔP_friction + ΔP_elevation
    %     v            = Q / A
    %
    %   where the resistance coefficient is derived from Darcy-Weisbach:
    %     R = f * L * ρ / (2 * D * A²)
    %     A = π * D² / 4
    %
    %   The pipe model is steady-state: it computes the pressure drop
    %   for a given flow rate. The dt argument in update() is accepted
    %   for interface compatibility but does not affect the calculation.
    %
    %   Assumptions:
    %     - Incompressible fluid
    %     - Steady-state flow (no water hammer or transient effects)
    %     - Constant friction factor (fully turbulent regime)
    %     - Uniform circular cross-section
    %     - No fittings or bends (add via increased friction factor)
    %
    %   Limitations:
    %     - No transient pressure wave modeling
    %     - No heat transfer
    %     - No two-phase flow
    %     - Friction factor does not vary with Reynolds number
    %
    %   Parameters:
    %     Geometry.Length      [m]       - Pipe length
    %     Geometry.Diameter    [m]       - Internal diameter
    %     Geometry.Area        [m²]     - Cross-sectional area (computed)
    %     Fluid.Density        [kg/m³]  - Fluid density
    %     Fluid.FrictionFactor [-]       - Darcy friction factor (default 0.02)
    %     Elevation.Change     [m]       - Outlet minus inlet elevation
    %     Hydraulic.Resistance [Pa·s²/m⁶] - Computed resistance coefficient
    %
    %   Inputs:
    %     FlowRate [m³/s] - volumetric flow through the pipe
    %
    %   Outputs:
    %     FlowRate     [m³/s] - output flow (reduced by leak if fault)
    %     PressureDrop [Pa]   - total pressure drop inlet to outlet
    %     Velocity     [m/s]  - average fluid velocity
    %
    %   Faults:
    %     Blockage - multiplies resistance by BlockageFactor (default 5×)
    %     Leak     - reduces output flow by LeakFraction (default 10%)
    %
    %   Example:
    %     Pipe101 = EPipe("ID","Pipe101","Length",50,"Diameter",0.15);
    %     Pipe101.setFlow(0.05);
    %     Pipe101.update(0.1);
    %     fprintf('ΔP = %.0f Pa\n', Pipe101.Outputs.PressureDrop);
    %
    %   See also: Equipment, ETank, EPump, EValve


    methods

        function obj = EPipe(options)
            % EPipe  Construct a pipe model.
            %
            %   Required: ID, Length, Diameter
            %   Optional: FrictionFactor, FluidDensity, ElevationChange,
            %             BlockageFactor, LeakFraction

            arguments
                options.ID string
                options.Length (1,1) double {mustBePositive}
                options.Diameter (1,1) double {mustBePositive}
                options.FrictionFactor (1,1) double {mustBePositive} = 0.02
                options.FluidDensity (1,1) double {mustBePositive} = 998
                options.ElevationChange (1,1) double = 0
                options.BlockageFactor (1,1) double {mustBePositive} = 5
                options.LeakFraction (1,1) double {mustBeNonnegative} = 0.10
            end

            if options.LeakFraction > 1
                error("EPipe:InvalidLeakFraction", ...
                    "LeakFraction must be between 0 and 1 (got %.2f).", ...
                    options.LeakFraction);
            end

            % Identity
            obj.ID = options.ID;
            obj.Type = "Pipe";
            obj.Description = sprintf("Pipe L=%.1fm, D=%.3fm", ...
                options.Length, options.Diameter);

            % Geometry
            A = pi * options.Diameter^2 / 4;
            obj.Parameters.Geometry.Length = options.Length;
            obj.Parameters.Geometry.Diameter = options.Diameter;
            obj.Parameters.Geometry.Area = A;

            % Fluid
            obj.Parameters.Fluid.Density = options.FluidDensity;
            obj.Parameters.Fluid.FrictionFactor = options.FrictionFactor;

            % Elevation
            obj.Parameters.Elevation.Change = options.ElevationChange;

            % Resistance coefficient from Darcy-Weisbach:
            % ΔP = f * (L/D) * (ρ*v²/2) = f*L*ρ/(2*D*A²) * Q²
            R = options.FrictionFactor * options.Length * options.FluidDensity ...
                / (2 * options.Diameter * A^2);
            obj.Parameters.Hydraulic.Resistance = R;

            % Fault configuration
            obj.Parameters.Faults.BlockageFactor = options.BlockageFactor;
            obj.Parameters.Faults.LeakFraction = options.LeakFraction;

            % State
            obj.State.FlowRate = 0;
            obj.State.Velocity = 0;
            obj.State.PressureDrop = 0;

            % Inputs
            obj.Inputs.FlowRate = 0;

            % Faults
            obj.Faults.Blockage = false;
            obj.Faults.Leak = false;

            % Initialize outputs
            obj.updateOutputs();
            obj.updateStatus();
        end


        function setFlow(obj, flowRate)
            % setFlow  Convenience method to set input flow rate.
            %
            %   obj.setFlow(Q) sets the volumetric flow rate [m³/s].

            arguments
                obj
                flowRate (1,1) double
            end

            obj.Inputs.FlowRate = flowRate;
        end


        function update(obj, dt)
            % update  Compute pressure drop and outputs for current flow.
            %
            %   obj.update(dt) computes the steady-state pressure drop.
            %   The dt argument is accepted for interface compatibility
            %   but does not affect the pipe calculation (no dynamics).

            arguments
                obj
                dt (1,1) double {mustBePositive}
            end

            Q = obj.Inputs.FlowRate;
            A = obj.Parameters.Geometry.Area;
            rho = obj.Parameters.Fluid.Density;
            dz = obj.Parameters.Elevation.Change;

            % Resistance (increased by blockage fault)
            R = obj.Parameters.Hydraulic.Resistance;
            if obj.Faults.Blockage
                R = R * obj.Parameters.Faults.BlockageFactor;
            end

            % Friction pressure drop: ΔP = R * Q * |Q|
            % The |Q| term preserves sign for reverse flow
            dP_friction = R * Q * abs(Q);

            % Elevation pressure change: ΔP = ρ*g*Δz
            % Positive Δz (uphill) increases pressure drop
            dP_elevation = rho * 9.81 * dz;

            dP_total = dP_friction + dP_elevation;

            % Fluid velocity
            velocity = Q / A;

            % Output flow (leak reduces delivered flow)
            Qout = Q;
            if obj.Faults.Leak
                Qout = Q * (1 - obj.Parameters.Faults.LeakFraction);
            end

            % Update state
            obj.State.FlowRate = Qout;
            obj.State.Velocity = velocity;
            obj.State.PressureDrop = dP_total;

            obj.updateOutputs();
            obj.updateStatus();
        end


        function reset(obj)
            % reset  Restore pipe to initial conditions.

            obj.State.FlowRate = 0;
            obj.State.Velocity = 0;
            obj.State.PressureDrop = 0;
            obj.Inputs.FlowRate = 0;

            obj.clearAllFaults();
            obj.updateOutputs();
            obj.updateStatus();
        end


        function tags = getTags(obj)
            % getTags  Return pipe industrial tags.

            now = datetime("now");
            statusCode = 0;
            if obj.hasAnyFault(), statusCode = 3; end

            Tag = [
                obj.ID + ".FLOW_RATE"
                obj.ID + ".PRESSURE_DROP"
                obj.ID + ".VELOCITY"
                obj.ID + ".FAULT_BLOCKAGE"
                obj.ID + ".FAULT_LEAK"
                obj.ID + ".STATUS"
            ];

            Value = [
                obj.Outputs.FlowRate
                obj.Outputs.PressureDrop
                obj.Outputs.Velocity
                double(obj.Faults.Blockage)
                double(obj.Faults.Leak)
                statusCode
            ];

            Unit = ["m3/s"; "Pa"; "m/s"; "-"; "-"; "-"];
            Quality = repmat("GOOD", length(Tag), 1);
            Timestamp = repmat(now, length(Tag), 1);

            tags = table(Tag, Value, Unit, Quality, Timestamp);
        end

    end


    methods (Access = protected)

        function faults = getSupportedFaults(~)
            faults = ["Blockage", "Leak"];
        end

        function updateOutputs(obj)
            obj.Outputs.FlowRate = obj.State.FlowRate;
            obj.Outputs.PressureDrop = obj.State.PressureDrop;
            obj.Outputs.Velocity = obj.State.Velocity;
        end

        function updateStatus(obj)
            if obj.hasAnyFault()
                obj.Status = "FAULTED";
            else
                obj.Status = "OK";
            end
        end

    end

end
