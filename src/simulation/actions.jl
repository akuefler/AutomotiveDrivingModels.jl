export
    ActionContext,
    ContextFree,
    IntegratedContinuous,

    DriveAction,
    NextState,
    AccelTurnrate,
    AccelDesang,

    propagate


abstract ActionContext

type ContextFree <: ActionContext end
type IntegratedContinuous <: ActionContext
    Δt::Float64 # timestep
    n_integration_steps::Int # number of substeps taken during integration
end

###############

abstract DriveAction
Base.length{A<:DriveAction}(a::Type{A}) = error("length not defined for DriveAction $a")
Base.convert{A<:DriveAction}(a::Type{A}, v::Vector{Float64}) = error("convert v → a not implemented for DriveAction $a")
Base.copy!(v::Vector{Float64}, a::DriveAction) = error("copy! not implemented for DriveAction $a")
Base.convert{A<:DriveAction}(::Type{Vector{Float64}}, a::A) = copy!(Array(Float64, length(A)), a)
propagate(veh::Vehicle, action::DriveAction, context::ActionContext, roadway::Roadway) = error("propagate not implemented for DriveAction $action and context $context")

immutable AccelTurnrate <: DriveAction
    a::Float64
    ω::Float64
end
Base.length(::Type{AccelTurnrate}) = 2
Base.convert(::Type{AccelTurnrate}, v::Vector{Float64}) = AccelTurnrate(v[1], v[2])
function Base.copy!(v::Vector{Float64}, a::AccelTurnrate)
    v[1] = a.a
    v[2] = a.ω
    v
end
function propagate(veh::Vehicle, action::AccelTurnrate, context::IntegratedContinuous, roadway::Roadway)

    a = action.a # accel
    ω = action.ω # turnrate

    x = veh.state.posG.x
    y = veh.state.posG.y
    θ = veh.state.posG.θ
    v = veh.state.v

    δt = context.Δt / context.n_integration_steps

    for i in 1 : context.n_integration_steps
        x += v*cos(θ)*δt
        y += v*sin(θ)*δt
        θ += ω*δt
        v += a*δt
    end

    posG = VecSE2(x, y, θ)
    VehicleState(posG, roadway, v)
end

immutable AccelDesang <: DriveAction
    a::Float64
    ϕdes::Float64
end
Base.length(::Type{AccelDesang}) = 2
Base.convert(::Type{AccelDesang}, v::Vector{Float64}) = AccelDesang(v[1], v[2])
function Base.copy!(v::Vector{Float64}, a::AccelDesang)
    v[1] = a.a
    v[2] = a.ϕdes
    v
end
function propagate(veh::Vehicle, action::AccelDesang, context::IntegratedContinuous, roadway::Roadway)

    a = action.a # accel
    ϕdes = action.ϕdes # desired heading angle

    x = veh.state.posG.x
    y = veh.state.posG.y
    θ = veh.state.posG.θ
    v = veh.state.v

    δt = context.Δt/context.n_integration_steps

    for i in 1 : context.n_integration_steps

        posF = Frenet(VecSE2(x, y, θ), roadway)
        ω = ϕdes - posF.ϕ

        x += v*cos(θ)*δt
        y += v*sin(θ)*δt
        θ += ω*δt
        v += a*δt
    end

    posG = VecSE2(x, y, θ)
    VehicleState(posG, roadway, v)
end

###############

immutable NextState <: DriveAction
    s::VehicleState
end

Base.length(::Type{NextState}) = 11
function Base.convert(::Type{NextState}, v::Vector{Float64})
    VehicleState(VecSE2(v[1],v[2],v[3]), # x, y, θ
                 Frenet(
                    RoadIndex(
                        CurveIndex(round(Int, v[4]), v[5]),
                        LaneTag(round(Int, v[6]), round(Int, v[7])),
                    ),
                    v[8], v[9], v[10] # s, t, ϕ
                 ),
                 v[11] # speed
    )
end
function Base.copy!(v::Vector{Float64}, a::NextState)
    v[1] = a.s.posG.x
    v[2] = a.s.posG.y
    v[2] = a.s.posG.θ
    v[2] = a.s.posF.roadind.ind.i
    v[2] = a.s.posG.roadind.ind.t
    v[2] = a.s.posG.roadind.tag.segment
    v[2] = a.s.posG.roadind.tag.lane
    v[2] = a.s.posG.s
    v[2] = a.s.posG.t
    v[2] = a.s.posG.ϕ
    v
end
propagate{C<:ActionContext}(veh::Vehicle, action::NextState, context::C, roadway::Roadway) = action.s