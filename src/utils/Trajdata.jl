# Traj Data

# Copyright (c) 2014 Tim wheeler, Robert Bosch Gmbh

# code for the use of trajectory data files, originally generated from Bosch bagfiles

module Trajdata

using DataFrames
using DataArrays
using Vec

import Base: start, next, done, get


export 
	PrimaryDataset,                     # type containing precomputed road network data

	CARIND_EGO,                         # index value associated with ego vehicle
	CARID_EGO,							# id value associated with ego vehicle

	CONTROL_STATUS_START,               # vehicle is in start mode
	CONTROL_STATUS_ACTIVE,	            # vehicle is in active mode
	CONTROL_STATUS_ACTIVE_REINT,        # 
	CONTROL_STATUS_CONTROL_ACTIVE,      # 
	CONTROL_STATUS_AUTO,                # autonomous driving mode
	CONTROL_STATUS_HANDOVER_TO_DRIVER,  # system -> driver handover
	CONTROL_STATUS_HANDOVER_TO_SYSTEM,  # driver -> system handover
	CONTROL_STATUS_PREPARE_ACTUATORS,   # 
	CONTROL_STATUS_READY,               #
	CONTROL_STATUS_WAITING,             #
	CONTROL_STATUS_FAILURE,             #
	CONTROL_STATUS_INIT,                #
	CONTROL_STATUS_PASSIVE,             #
	CONTROL_STATUS_VIRES_AUTO,          # system was simulated by Vires

	validfind_inbounds,                 # true if the given valid frame index is inbounds
	frameind_inbounds,                  # true if the given frame index is inbounds
	nframeinds,                         # number of farme indeces
	nvalidfinds,                        # number of valid frame indeces
	calc_sec_per_frame,                 # compute seconds elapsed between frame samples
	get_elapsed_time,                   # elapsed time between validfinds
	closest_frameind,                   # 
	closest_validfind,
	carid2ind,
	carind2id,
	carid2ind_or_negative_one_otherwise,
	carid2ind_or_negative_two_otherwise,
	validfind2frameind,
	frameind2validfind,
	jumpframe,
	getc,
	gete,
	gete_validfind,
	setc!,
	sete!,
	set!,
	idinframe,
	indinframe,
	getc_symb,
	getc_has,
	setc_has!,
	carind_exists,
	carid_exists,
	frame2frameind,
	get_max_num_cars,
	get_max_carind,
	get_maxcarind,
	get_carids,
	get_valid_frameinds,
	copy_trace!,
	copy_vehicle!,
	load_trajdata,
	export_trajdata,
	remove_car_from_frame!,
	remove_cars_from_frame!,
	remove_car!,
	find_slot_for_car!,
	get_num_other_cars_in_frame,
	get_num_cars_in_frame,
	add_car_slot!,
	frames_contain_carid,
	extract_continuous_segments,
	spanning_validfinds	,
	are_validfinds_continuous,
	get_validfinds_containing_carid,
	isnum

# ------------------------

const CONTROL_STATUS_START              =  1
const CONTROL_STATUS_ACTIVE             =  2
const CONTROL_STATUS_ACTIVE_REINT       =  3
const CONTROL_STATUS_CONTROL_ACTIVE     =  4
const CONTROL_STATUS_AUTO               =  5
const CONTROL_STATUS_HANDOVER_TO_DRIVER =  7
const CONTROL_STATUS_HANDOVER_TO_SYSTEM =  8
const CONTROL_STATUS_PREPARE_ACTUATORS  =  9
const CONTROL_STATUS_READY              = 10
const CONTROL_STATUS_WAITING            = 11
const CONTROL_STATUS_FAILURE            = 12
const CONTROL_STATUS_INIT               = 13
const CONTROL_STATUS_PASSIVE            = 14
const CONTROL_STATUS_VIRES_AUTO         = 99

const CARIND_EGO                        = -1
const CARID_EGO                         = -1

const NUMBER_REGEX = r"(-)?(0|[1-9]([\d]*))(\.[\d]*)?((e|E)(\+|-)?[\d]*)?"

type PrimaryDataset

	#=
	DF_EGO_PRIMARY:
	--------------

	time           = time
	frame          = frame
	control_status = trajdata[:control_status], # enum identifier of control status (5==AUTO)
	posGx          = easting in the global frame
	posGy          = northing in the global frame
	posGyaw        = heading in the global frame
	posFx          = longitudinal distance along RHS lane centerline
	posFy          = lateral distance from RHS lane center
	posFyaw        = heading angle (average between two closest lanes)
	velFx          = longitudinal speed in lane
	velFy          = lateral speed in lane
	lanetag        = current lane definition
	nll            = number of lanes to the left
	nlr            = number of lanes to the right
	curvature      = local lane curvature
	d_cl           = lateral distance between center of car and closest centerline (true)
	d_ml           = lateral distance from left lane marker
	d_mr           = lateral distance from right lane marker
	d_merge        = distance along the road until the next merge
	d_split        = distance along the road until the next split
	=#


	df_ego_primary     :: DataFrame              # [frameind,  :feature] -> value
	df_other_primary   :: DataFrame              # [validfind, :feature] -> value, missing features are NA
	dict_trajmat       :: Dict{Uint32,DataFrame} # [carid] -> trajmat
	dict_other_idmap   :: Dict{Uint32,Uint16}    # [carid] -> matind
	mat_other_indmap   :: Matrix{Int16}          # [validfind, matind] -> carind, -1 if not present
	ego_car_on_freeway :: BitVector              # [frameind] -> bool
	validfind2frameind :: Vector{Int32}          # [validfind] -> frameind
	frameind2validfind :: Vector{Int32}          # [frameind] -> validfind, 0 if not applicable
	maxcarind          :: Int16                  # max ind of car in frame

	df_other_ncol_per_entry :: Int               # number of entries per column in df_other
	df_other_column_map :: Dict{Symbol, Int}     # maps symbol to column index

	PrimaryDataset(
		df_ego_primary     :: DataFrame, 
		df_other_primary   :: DataFrame,
		dict_trajmat       :: Dict{Uint32,DataFrame},
		dict_other_idmap   :: Dict{Uint32,Uint16},
		mat_other_indmap   :: Matrix{Int16},
		ego_car_on_freeway :: BitVector
		) = begin

		n_frames = size(df_ego_primary, 1)
		n_valid  = sum(ego_car_on_freeway)

		validfind2frameind = zeros(Int32, n_valid)
		frameind2validfind = zeros(Int32, n_frames)

		validfind = 0
		for frameind = 1 : n_frames
			if ego_car_on_freeway[frameind]
				validfind += 1
				validfind2frameind[validfind] = frameind
				frameind2validfind[frameind] = validfind
			end
		end

		maxcarind = -1
		while haskey(df_other_primary, symbol(@sprintf("id_%d", maxcarind+1)))
			maxcarind += 1
		end

		df_other_column_map = Dict{Symbol, Int}()
		df_names = names(df_other_primary)
		col = 0
		while col < length(df_names)
			col += 1
			str = string(df_names[col])
			keyval = symbol(match(r".+(?=_\d+$)", str).match) # pull only the part before "_0", "_1", etc
			if !haskey(df_other_column_map, keyval)
				df_other_column_map[keyval] = col
			else # we are repeating
				break
			end
		end
		df_other_ncol_per_entry = length(df_other_column_map)

		new(df_ego_primary, 
			df_other_primary,
			dict_trajmat,
			dict_other_idmap,
			mat_other_indmap, 
			ego_car_on_freeway, 
			validfind2frameind,
			frameind2validfind,
			maxcarind,
			df_other_ncol_per_entry,
			df_other_column_map
			)
	end
end

export IterOtherCarindsInFrame, IterAllCarindsInFrame

type IterOtherCarindsInFrame
	# An iterator over other cars in a frame
	# iterators from carind 0 to maxcarind
	# does not return ego carind

	# the state is the carind

	pdset     :: PrimaryDataset
	validfind :: Int
end
type IterAllCarindsInFrame
	# An iterator over all cars in a frame
	# iterators from carind -1 to maxcarind
	# does not return ego carind

	# the state is the carind

	pdset     :: PrimaryDataset
	validfind :: Int
end

start(::IterOtherCarindsInFrame) = 0
function done(I::IterOtherCarindsInFrame, carind::Int)
	!validfind_inbounds(I.pdset, I.validfind) || !indinframe(I.pdset, carind, I.validfind)
end
next(::IterOtherCarindsInFrame, carind::Int) = (carind, carind+1)

start(::IterAllCarindsInFrame) = -1
function done(I::IterAllCarindsInFrame, carind::Int)
	# NOTE(tim): the state is the carind
	if !validfind_inbounds(I.pdset, I.validfind)
		return true
	end
	if carind == CARIND_EGO
		return false
	end
	!indinframe(I.pdset, carind, I.validfind)
end
next(::IterAllCarindsInFrame, carind::Int) = (carind, carind+1)

# TrajData Data Definition:

	# id::Integer         # car identification number
	# posEx::Real         # position in the ego frame relative to the ego car
	# posEy::Real     
	# velEx::Real         # velocity in the ego frame relative to the ego car
	# velEy::Real
	# posGx::Real         # global position of the car in UTM
	# posGy::Real
	# velGx::Real         # global velocity of the car in m/s
	# velGy::Real
	# yawG::Real          # heading angle with respect to UTM
	# lane::Integer       # lane number
	# lane_offset::Real   # offset the car from the centerline
	# lane_tangent::Real  # local heading angle of the centerline
	# angle_to_lane::Real # heading of the car with respect to the centerline
	# velLs::Real         # velocity of the car projected along its lane
	# velLd::Real         # velocity of the car projected perpendicularly to the lane
	# posRLs::Real        # position of the car along the rightmost lane
	# posRLd::Real        # position of the car from the rightmost lane

	# frame::Integer
	# time::Real
	# control_status::Integer # the state of the car's control system (autonomous, etc.)

	# # global position [m](UTM)
	# posGx::Real
	# posGy::Real
	# posGz::Real

	# # orientation [rad]
	# rollG::Real
	# pitchG::Real
	# yawG::Real

	# # odom velocity [m/s](ego)
	# velEx::Real
	# velEy::Real
	# velEz::Real

	# # lane, 0=our lane, -1 = left, 1 = right, etc.
	# lane::Integer
	
	# # offset with resect to center line [m]
	# lane_offset::Real

	# #  closest centerline point
	# centerline_closest_x::Real
	# centerline_closest_y::Real

function Base.deepcopy(pdset::PrimaryDataset)
    PrimaryDataset(
        deepcopy(pdset.df_ego_primary),
        deepcopy(pdset.df_other_primary),
        deepcopy(pdset.dict_trajmat),
        deepcopy(pdset.dict_other_idmap),
        deepcopy(pdset.mat_other_indmap),
        deepcopy(pdset.ego_car_on_freeway)
    )
end

nframeinds( trajdata::DataFrame ) = size(trajdata, 1)
nframeinds(  pdset::PrimaryDataset ) = length(pdset.frameind2validfind)
nvalidfinds( pdset::PrimaryDataset ) = length(pdset.validfind2frameind)

function idinframe( pdset::PrimaryDataset, carid::Integer, validfind::Integer )
	if validfind < 1 || validfind > size(pdset.mat_other_indmap, 1)
		return false
	end

	if carid == CARID_EGO
		return true
	end

	if !haskey(pdset.dict_other_idmap, carid)
		return false
	end
	
	matind = pdset.dict_other_idmap[carid]
	pdset.mat_other_indmap[validfind, matind] != -1
end
function indinframe( pdset::PrimaryDataset, carind::Integer, validfind::Integer )
	if validfind < 1 || validfind > size(pdset.mat_other_indmap, 1)
		return false
	end
	if carind == CARIND_EGO
		return true
	end
	if 0 ≤ carind ≤ pdset.maxcarind
		col = pdset.df_other_column_map[:id] + pdset.df_other_ncol_per_entry * carind
		id_ = pdset.df_other_primary[validfind, col]
		# id_ = pdset.df_other_primary[validfind, symbol(@sprintf("id_%d", carind))]
		!isa(id_, NAtype)
	else
		false
	end
end
function carid2ind( trajdata::DataFrame, carid::Integer, frameind::Integer)
	if carid == CARID_EGO
		return CARIND_EGO
	end
	@assert(haskey(trajdata, symbol(@sprintf("has_%d", carid))))
	carind = int(frameind, trajdata[symbol(@sprintf("has_%d", carid))])
	@assert(carind != -1)
	int(carind)
end
function carid2ind( pdset::PrimaryDataset, carid::Integer, validfind::Integer )
	if carid == CARID_EGO
		return CARIND_EGO
	end
	# @assert(haskey(pdset.dict_other_idmap, carid))
	matind = pdset.dict_other_idmap[carid]
	carind = pdset.mat_other_indmap[validfind, matind]
	@assert(carind != -1)
	int(carind)
end
function carid2ind_or_negative_one_otherwise(trajdata::DataFrame, carid::Integer, frameind::Integer)
	
	if carid == CARID_EGO
		return CARIND_EGO
	end
	@assert(haskey(trajdata, symbol(@sprintf("has_%d", carid))))
	carind = int(trajdata[symbol(@sprintf("has_%d", carid))][frameind])
	# -1 if no exist
	int(carind)
end
function carid2ind_or_negative_two_otherwise(pdset::PrimaryDataset, carid::Integer, validfind::Integer)
	# -2 if no exist
	if carid == CARID_EGO
		return CARIND_EGO
	end

	if !haskey(pdset.dict_other_idmap, carid)
		return -2
	end

	matind = pdset.dict_other_idmap[carid]
	carind = pdset.mat_other_indmap[validfind, matind]

	if carind == -1
		return -2
	end

	int(carind)
end
function carind2id( trajdata::DataFrame, carind::Integer, frameind::Integer)
	if carind == CARIND_EGO
		return CARID_EGO
	end
	@assert(haskey(trajdata, symbol(@sprintf("id_%d", carind))))
	carid = trajdata[frameind, symbol(@sprintf("id_%d", carind))]
	@assert(carid != -1)
	int(carid)
end
function carind2id( pdset::PrimaryDataset, carind::Integer, validfind::Integer )
	if carind == CARIND_EGO
		return CARID_EGO
	end
	# @assert(haskey(pdset.df_other_primary, symbol(@sprintf("id_%d", carind))))
	# carid = pdset.df_other_primary[validfind, symbol(@sprintf("id_%d", carind))]
	col = pdset.df_other_column_map[:id] + pdset.df_other_ncol_per_entry * carind
	carid = pdset.df_other_primary[validfind, col]
	@assert(carid != -1)
	int(carid)
end

validfind_inbounds( pdset::PrimaryDataset, validfind::Integer ) = 1 <= validfind <= length(pdset.validfind2frameind)
frameind_inbounds( pdset::PrimaryDataset, frameind::Integer ) = 1 <= frameind <= length(pdset.frameind2validfind)
function frameind2validfind( pdset::PrimaryDataset, frameind::Integer )
	# returns 0 if it does not exist
	if !frameind_inbounds(pdset, frameind)
		return 0
	end
	int(pdset.frameind2validfind[frameind])
end
function validfind2frameind( pdset::PrimaryDataset, validfind::Integer )
	# returns 0 if it does not exist
	if !validfind_inbounds(pdset, validfind)
		return 0
	end
	int(pdset.validfind2frameind[validfind])
end
function jumpframe( pdset::PrimaryDataset, validfind::Integer, delta::Integer )
	# get the validfind that has a frameind of + delta
	# returns 0 if it does not exist
	frameind = validfind2frameind(pdset, validfind)
	jump_frameind = frameind + delta
	frameind2validfind(pdset, jump_frameind)
end

function calc_sec_per_frame( pdset::PrimaryDataset )
	# estimate the difference between frames assuming that is it more or less consistent
	# across the entire sequence
	nframes = nframeinds(pdset)
	t0 = gete(pdset, :time, 1)::Float64
	tf = gete(pdset, :time, nframes)::Float64

	(tf - t0) / (nframes-1)
end
function get_elapsed_time(pdset::PrimaryDataset, validfindA::Integer, validfindB::Integer)
	t1 = gete(pdset, :time, validfindA)::Float64
	t2 = gete(pdset, :time, validfindB)::Float64
	t2 - t1
end
function closest_frameind( pdset::PrimaryDataset, time::Float64 )
	# returns the frameind that is closest to the given time
	# uses the fact that Δt is more or less consistent

	N = nframeinds(pdset)

	Δt = calc_sec_per_frame(pdset)
	t0 = gete(pdset, :time, 1)::Float64
	frameind = clamp(int((time - t0) / Δt + 1), 1, N)
	t  = gete(pdset, :time, frameind)::Float64

	tp = frameind < N ? gete(pdset, :time, frameind + 1)::Float64 : t
	if abs(tp - time) < abs(t-time)
		t, frameind = tp, frameind+1
		tp = frameind < N ? gete(pdset, :time, frameind + 1)::Float64 : t
		while abs(tp - time) < abs(t-time)
			t, frameind = tp, frameind+1
			tp = frameind < N ? gete(pdset, :time, frameind + 1)::Float64 : t
		end
		return frameind
	end

	tn = frameind > 1 ? gete(pdset, :time, frameind - 1)::Float64 : t
	if abs(tn - time) < abs(t-time)
		t, frameind = tn, frameind-1
		tn = frameind > 1 ? gete(pdset, :time, frameind - 1)::Float64 : t
		while abs(tn - time) < abs(t-time)
			t, frameind = tn, frameind-1
			tn = frameind > 1 ? gete(pdset, :time, frameind - 1)::Float64 : t
		end
		return frameind
	end

	frameind
end
function closest_validfind( pdset::PrimaryDataset, time::Float64 )
	# returns the validfind that is closest	to the given time
	frameind = closest_frameind(pdset, time)
	validfind = frameind2validfind(pdset, frameind)
	if validfind != 0
		return validfind
	end

	N = nframeinds(pdset)
	if frameind < N
		find_forward = frameind + 1
		while frameind2validfind(pdset, find_forward) == 0
			find_forward += 1
			if find_forward ≥ N
				break
			end
		end
		fp = frameind2validfind(pdset, find_forward) == 0 ? 0 : find_forward
	else
		fp = 0
	end

	isvalid_n = false
	if frameind > 1
		find_back = frameind - 1
		while frameind2validfind(pdset, find_back) == 0
			find_back -= 1
			if find_back ≤ 1
				break
			end
		end
		fn = frameind2validfind(pdset, find_back) == 0 ? 0 : find_back
	else
		fn = 0
	end

	
	@assert(fn != fp)

	if fn == 0
		return fp
	elseif fp == 0
		return fn
	end

	tp = gete(pdset, :time, fp)::Float64
	tn = gete(pdset, :time, fn)::Float64

	dp = abs(tp - time)
	dn = abs(tn - time)

	return dp ≤ dn ? fp : fn
end


getc_symb( str::String, carind::Integer ) = symbol(@sprintf("%s_%d", str, carind))
function getc( trajdata::DataFrame, str::String, carind::Integer, frameind::Integer )
	# @assert(haskey(trajdata, symbol(@sprintf("id_%d", carind))))
	trajdata[frameind, symbol(@sprintf("%s_%d", str, carind))]
end
function getc( pdset::PrimaryDataset, sym::Symbol, carind::Integer, validfind::Integer )
	# sym_orig = symbol(@sprintf("%s_%d", string(sym), carind))
	# println(names(pdset.df_other_primary))
	# println(findfirst(names(pdset.df_other_primary), sym_orig))

	# print(carind, "  ", col, "  ", sym, "  ")
	# println(names(pdset.df_other_primary)[col])
	
	col = pdset.df_other_column_map[sym] + pdset.df_other_ncol_per_entry * carind
	pdset.df_other_primary[validfind, col]
end
function getc( pdset::PrimaryDataset, str::String, carind::Integer, validfind::Integer )
	# @assert(haskey(pdset.df_other_primary, symbol(@sprintf("id_%d", carind))))
	sym = symbol(@sprintf("%s_%d", str, carind))
	pdset.df_other_primary[validfind, sym]
end
gete( pdset::PrimaryDataset, sym::Symbol, frameind::Integer ) = pdset.df_ego_primary[frameind, sym]
function gete_validfind( pdset::PrimaryDataset, sym::Symbol, validfind::Integer )
	pdset.df_ego_primary[validfind2frameind(pdset, validfind), sym]
end
function get(pdset::PrimaryDataset, str::String, carind::Integer, validfind::Integer)
	if carind == CARIND_EGO
		frameind = validfind2frameind(pdset, validfind)
		return gete(pdset, symbol(str), frameind)
	end
	getc(pdset, str, carind, validfind)
end
function get(pdset::PrimaryDataset, sym::Symbol, carind::Integer, validfind::Integer)
	if carind == CARIND_EGO
		frameind = validfind2frameind(pdset, validfind)
		return gete(pdset, sym, frameind)
	end
	getc(pdset, sym, carind, validfind)
end
function get(pdset::PrimaryDataset, sym::Symbol, str::String, carind::Integer, frameind::Integer, validfind::Integer)
	# a more efficient version
	carind == CARIND_EGO ? gete(pdset, sym, frameind) : getc(pdset, sym, carind, validfind)
end
function get(pdset::PrimaryDataset, sym::Symbol, carind::Integer, frameind::Integer, validfind::Integer)
	# a more efficient version
	carind == CARIND_EGO ? gete(pdset, sym, frameind) : getc(pdset, sym, carind, validfind)
end
function setc!( trajdata::DataFrame, str::String, carind::Integer, frameind::Integer, val::Any )
	@assert(haskey(trajdata, symbol(@sprintf("id_%d", carind))))
	trajdata[symbol(@sprintf("%s_%d", str, carind))][frameind] = val
end
function sete!( pdset::PrimaryDataset, sym::Symbol, frameind::Integer, val::Any )
	@assert(1 <= frameind && frameind <= length(pdset.frameind2validfind))
	pdset.df_ego_primary[frameind, sym] = val
end
function setc!( pdset::PrimaryDataset, str::String, carind::Integer, validfind::Integer, val::Any )
	@assert(haskey(pdset.df_other_primary, symbol(@sprintf("id_%d", carind))))
	pdset.df_other_primary[validfind, symbol(@sprintf("%s_%d", str, carind))] = val
end
function setc!( pdset::PrimaryDataset, sym::Symbol, carind::Integer, validfind::Integer, val::Any )
	col = pdset.df_other_column_map[sym] + pdset.df_other_ncol_per_entry * carind	
	pdset.df_other_primary[validfind, col] = val
end
function set!(pdset::PrimaryDataset, str::String, carind::Integer, validfind::Integer, val::Any)
	if carind == CARIND_EGO
		frameind = validfind2frameind(pdset, validfind)
		return sete!(pdset, symbol(str), frameind, val)
	end
	setc!(pdset, str, carind, validfind, val)
end
function set!(pdset::PrimaryDataset, sym::Symbol, carind::Integer, validfind::Integer, val::Any)
	if carind == CARIND_EGO
		frameind = validfind2frameind(pdset, validfind)
		return sete!(pdset, sym, frameind, val)
	end
	setc!(pdset, sym, carind, validfind, val)
end
function getc_has( trajdata::DataFrame, carid::Integer, frameind::Integer )
	@assert(haskey(trajdata, symbol(@sprintf("has_%d", carid))))
	return int(trajdata[symbol(@sprintf("has_%d", carid))][frameind])
end
function getc_has( trajdata::DataFrame, carid::Integer )
	@assert(haskey(trajdata, symbol(@sprintf("has_%d", carid))))
	return int(trajdata[symbol(@sprintf("has_%d", carid))])
end
function setc_has!( trajdata::DataFrame, carid::Integer, frameind::Integer, carind::Integer )
	@assert(haskey(trajdata, symbol(@sprintf("has_%d", carid))))
	@assert(carind >= -1)
	trajdata[symbol(@sprintf("has_%d", carid))][frameind] = carind
end
function get_max_num_cars( trajdata::DataFrame )
	i = -1
	while haskey(trajdata, symbol(@sprintf("id_%d", i+1)))
		i += 1
	end
	return i
end
function get_max_carind( trajdata::DataFrame )
	i = -1
	while haskey(trajdata, symbol(@sprintf("id_%d", i+1)))
		i += 1
	end
	return i
end
get_maxcarind( pdset::PrimaryDataset ) = pdset.maxcarind
function get_maxcarind( pdset::PrimaryDataset, validfind::Integer )
	i = -1
	for carind = 0 : pdset.maxcarind
		if indinframe(pdset, carind, validfind)
			i = carind
		end
	end
	i
end

function get_carids( trajdata::DataFrame )
	# obtain a set of car ids ::Set{Int}
	carids = Set{Int}()
	push!(carids, CARID_EGO)
	for name in names(trajdata)
		str = string(name)
		if ismatch(r"^has_(\d)+$", str)
			m = match(r"(\d)+", str)
			id = int(m.match)
			push!(carids, id)
		end
	end
	carids
end
function get_carids( pdset::PrimaryDataset )
	carids = Set{Int}()

	push!(carids, CARID_EGO)	
	for carid in keys(pdset.dict_other_idmap)
		push!(carids, carid)
	end
	
	carids
end
function carind_exists( trajdata::DataFrame, carind::Integer, frameind::Integer )
	@assert( carind >= 0 )
	@assert( haskey(trajdata, symbol(@sprintf("id_%d", carind))) )
	!isa(trajdata[frameind, symbol(@sprintf("id_%d", carind))], NAtype)
end
carid_exists( pdset::PrimaryDataset, carid::Integer ) = (carid == CARID_EGO) || haskey(pdset.dict_other_idmap, uint32(carid))
function carid_exists( trajdata::DataFrame, carid::Integer, frameind::Integer)

	return (carid == CARID_EGO) || getc_has( trajdata, carid, frameind ) != -1
end

function get_valid_frameinds( pdset::PrimaryDataset ) 

	all_inds = [1:size(pdset.df_ego_primary,1)]
	all_inds[pdset.ego_car_on_freeway]
end
frame2frameind( trajdata::DataFrame, frame::Integer ) = findfirst(x->x == frame, array(trajdata[:frame], -999))

function load_trajdata( input_path::String )
	@assert(isfile(input_path))

	# clean the csv file to add necessary commas
	# ----------------------------------------
	file = open(input_path, "r")
	lines = readlines(file)
	close(file)

	n_cols = length(matchall(r",", lines[1]))+1

	temp_name = tempname()*".csv"
	file = open(temp_name, "w")
	for i = 1 : length(lines)

		# replace "None" with "Inf"
		lines[i] = replace(lines[i], "None", "Inf")

		cols = length(matchall(r",", lines[i]))+1
		if n_cols - cols < 0
			println(i, ": ", cols, " -> ", n_cols)
		end 
		@printf(file, "%s", lines[i][1:end-1]*(","^(n_cols-cols))*"\n" )
	end
	close(file)

	# load the cleaned file
	# ----------------------------------------
	df = readtable(temp_name)
	rm(temp_name)


	# rename the columns
	# ----------------------------------------
	rename!(df, :entry,                      :frame)
	rename!(df, :timings,                    :time)
	rename!(df, :status,                     :control_status)
	rename!(df, :global_position_x,          :posGx)
	rename!(df, :global_position_y,          :posGy)
	rename!(df, :global_position_z,          :posGz)
	rename!(df, :global_rotation_w,          :quatw)
	rename!(df, :global_rotation_x,          :quatx)
	rename!(df, :global_rotation_y,          :quaty)
	rename!(df, :global_rotation_z,          :quatz)
	rename!(df, :odom_velocity_x,            :velEx)
	rename!(df, :odom_velocity_y,            :velEy)
	rename!(df, :odom_velocity_z,            :velEz)
	rename!(df, :odom_acceleration_x,        :accEx)
	rename!(df, :odom_acceleration_y,        :accEy)
	rename!(df, :odom_acceleration_z,        :accEz)
	rename!(df, :offsetwrtcenterline,        :lane_offset)
	rename!(df, :closest_centerline_point_x, :centerline_closest_x)
	rename!(df, :closest_centerline_point_y, :centerline_closest_y)

	i = 0
	while haskey(df, symbol(@sprintf("car_id%d", i)))

		rename!(df, symbol(@sprintf("car_id%d",i)),                symbol(@sprintf("id_%d",            i)))
		rename!(df, symbol(@sprintf("ego_x%d",i)),                 symbol(@sprintf("posEx_%d",         i)))
		rename!(df, symbol(@sprintf("ego_y%d",i)),                 symbol(@sprintf("posEy_%d",         i)))
		rename!(df, symbol(@sprintf("v_x%d",i)),                   symbol(@sprintf("velEx_%d",         i)))
		rename!(df, symbol(@sprintf("v_y%d",i)),                   symbol(@sprintf("velEy_%d",         i)))
		rename!(df, symbol(@sprintf("global_x%d",i)),              symbol(@sprintf("posGx_%d",         i)))
		rename!(df, symbol(@sprintf("global_y%d",i)),              symbol(@sprintf("posGy_%d",         i)))
		rename!(df, symbol(@sprintf("global_v_x%d",i)),            symbol(@sprintf("velGx_%d",         i)))
		rename!(df, symbol(@sprintf("global_v_y%d",i)),            symbol(@sprintf("velGy_%d",         i)))
		rename!(df, symbol(@sprintf("car_angle%d",i)),             symbol(@sprintf("yawG_%d",          i)))
		rename!(df, symbol(@sprintf("lane%d",i)),                  symbol(@sprintf("lane_%d",          i)))
		rename!(df, symbol(@sprintf("offset_wrt_centerline%d",i)), symbol(@sprintf("lane_offset_%d",   i)))
		rename!(df, symbol(@sprintf("tangent_theta%d",i)),         symbol(@sprintf("lane_tangent_%d",  i)))
		rename!(df, symbol(@sprintf("angle_to_lane%d",i)),         symbol(@sprintf("angle_to_lane_%d", i)))
		rename!(df, symbol(@sprintf("lane_v_x%d",i)),              symbol(@sprintf("velLs_%d",         i)))
		rename!(df, symbol(@sprintf("lane_v_y%d",i)),              symbol(@sprintf("velLd_%d",         i)))
		rename!(df, symbol(@sprintf("lane_x%d",i)),                symbol(@sprintf("posRLs_%d",        i)))
		rename!(df, symbol(@sprintf("lane_y%d",i)),                symbol(@sprintf("posRLd_raw_%d",    i)))

		i += 1
	end
	maxcarind = i-1

	# add roll,pitch,yaw columns
	# ----------------------------------------
	rpy = zeros(size(df,1), 3)
	for i = 1 : size(df,1)
		quat = [df[:quatw][i], df[:quatx][i], df[:quaty][i], df[:quatz][i]]
		rpy[i,:] = [quat2euler(quat)...]
	end
	df[:rollG]  = rpy[:,1]
	df[:pitchG] = rpy[:,2]
	df[:yawG]   = rpy[:,3]

	# add a column for every id seen
	# for each frame, list the car index it corresponds to or 0 if it is not in the frame
	# ----------------------------------------
	idset = Array(Integer, 0)
	for i = 1 : size(df,1)
		for carind = 0 : maxcarind
			id = df[symbol(@sprintf("id_%d", carind))][i]
			if !isa(id, NAtype) && !in( id, idset )
				push!(idset, id)
			end
		end
	end
	sort!(idset)
	for id in idset
		df[symbol(@sprintf("has_%d", id))] = -1*ones(size(df,1))
	end
	for frame = 1 : size(df,1)
		for carind = 0 : maxcarind
			carid = df[symbol(@sprintf("id_%d", carind))][frame]
			if !isa(carid, NAtype)
				df[symbol(@sprintf("has_%d", carid))][frame] = carind
			end
		end
	end

	# clean the posRLd column
	# -----------------------------
	for carind = 0 : maxcarind
		symb = symbol(@sprintf("posRLd_raw_%d", carind))
		posRLd = Array(Any,size(df,1))

		for i = 1 : size(df,1)
			if isa(df[symb][i], NAtype)
				posRLd[i] = NA
			elseif df[symb][i] == "None"
				posRLd[i] = -999
			else
				posRLd[i] = float32(df[symb][i])
			end
		end
		df[symbol(@sprintf("posRLd_%d", carind))] = posRLd
		delete!(df, symb)
	end

	return df
end
function export_trajdata( filename::String, trajdata::DataFrame )

	fout = open(filename, "w")

	# print the header
	maxncars = get_max_num_cars( trajdata )
	@printf(fout, "entry, timings, global position x, global position y, global position z, global rotation w,global rotation x, global rotation y, global rotation z, odom velocity x, odom velocity y, odom velocity z, odom acceleration x, odom acceleration y, odom acceleration z, lane, offsetwrtcenterline, closest centerline point x, closest centerline point y")
	if maxncars > -1
		@printf(fout, ",")
	end
	for i = 0 : maxncars
		@printf(fout, "car id%d,ego x%d,ego y%d,v x%d,v y%d,global x%d,global y%d,global v_x%d,global v_y%d,car angle%d,lane%d,offset wrt centerline%d,tangent theta%d,angle to lane%d,lane v_x%d,lane v_y%d,lane x%d, lane y%d", i,i,i,i,i,i,i,i,i,i,i,i,i,i,i,i,i,i )
		if i != maxncars
			@printf(fout, ",")
		end
	end
	@printf(fout, "\n")

	for i = 1 : size(trajdata, 1)

		# entry
		@printf(fout, "%d,", i-1)

		# timings
		@printf(fout, "%.5f,", trajdata[:time][i])

		# global position
		@printf(fout, "%.10f,%.10f,%.10f,", trajdata[:posGx][i], trajdata[:posGy][i], trajdata[:posGz][i])
			
		# global rotation
		quat = euler2quat( trajdata[:rollG][i], trajdata[:pitchG][i], trajdata[:yawG][i] )
		@printf(fout, "%.16f,%.16f,%.16f,%.16f,", quat[1], quat[2], quat[3], quat[4])

		# odom velocity
		@printf(fout, "%.14f,%.14f,%.14f,", trajdata[:velEx][i], trajdata[:velEy][i], trajdata[:velEz][i])

		# odom acceleration
		@printf(fout, "%.14f,%.14f,%.14f,", trajdata[:accEx][i], trajdata[:accEy][i], trajdata[:accEz][i])

		# lane
		@printf(fout, "%d,", trajdata[:lane][i])

		# offsetwrtcenterline
		@printf(fout, "%.15f,", trajdata[:lane_offset][i])

		# # closest centerline point
		@printf(fout, "%.15f,%.15f", trajdata[:centerline_closest_x][i], trajdata[:centerline_closest_y][i])
		if maxncars != -1
			@printf(fout, ",")
		end

		# cars
		for j = 0 : maxncars

			val = trajdata[symbol(@sprintf("id_%d",            j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%d",    val))
			val = trajdata[symbol(@sprintf("posEx_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("posEy_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velEx_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velEy_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("posGx_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("posGy_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velGx_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velGy_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("yawG_%d",          j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("lane_%d",          j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%d",    val))
			val = trajdata[symbol(@sprintf("lane_offset_%d",   j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("lane_tangent_%d",  j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("angle_to_lane_%d", j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velLs_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("velLd_%d",         j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))
			val = trajdata[symbol(@sprintf("posRLs_%d",        j))][i]; @printf(fout, "%s,", isa(val, NAtype) ? "" : @sprintf("%.15f", val))

			val = trajdata[symbol(@sprintf("posRLd_%d", j))][i]; 
			if isa(val, NAtype)
				@printf(fout, "")
			elseif val == -999
				@printf(fout, "None")
			else
				@printf(fout, "%.15f", val)
			end
			
			if j < maxncars
				@printf(fout, ",")
			end
		end   

		@printf(fout, "\n")    
	end

	close(fout)
end


function add_car_to_validfind!(pdset::PrimaryDataset, carid::Integer, validfind::Integer)

	#=
	Adds the given carid to the frame
	This will set the `id` field and correctly set mat_other_indmap
	=#

	assert(validfind2frameind(pdset, validfind) != 0)

	carind = find_slot_for_car!(pdset, validfind)
	matind = pdset.dict_other_idmap[carid]
	pdset.mat_other_indmap[validfind, matind] = carind

    setc!("id",        carind, validfind, carid)

    pdset
end

function remove_car_from_frame!( pdset::PrimaryDataset, carind::Integer, validfind::Integer )
	@assert( carind >= 0 && carind <= pdset.maxcarind )
	@assert(validfind >= 0 && validfind <= length(pdset.validfind2frameind))

	# removes the car with the specified carind from the frame, shifting the other cars down

	# pull the carid from this frame
	id = getc( pdset, "id", carind, validfind )
	mat_ind = pdset.dict_other_idmap[id]
	pdset.mat_other_indmap[validfind, mat_ind] = -1

	loop_cind = carind
	while loop_cind < pdset.maxcarind

		if !indinframe(pdset, loop_cind, validfind)
			break
		end

		setc!( pdset, "id",        loop_cind, validfind, getc( pdset, "id",        loop_cind+1, validfind ))
		setc!( pdset, "posFx",     loop_cind, validfind, getc( pdset, "posFx",     loop_cind+1, validfind ))
		setc!( pdset, "posFy",     loop_cind, validfind, getc( pdset, "posFy",     loop_cind+1, validfind ))
		setc!( pdset, "posFyaw",   loop_cind, validfind, getc( pdset, "posFyaw",   loop_cind+1, validfind ))
		setc!( pdset, "velFx",     loop_cind, validfind, getc( pdset, "velFx",     loop_cind+1, validfind ))
		setc!( pdset, "velFy",     loop_cind, validfind, getc( pdset, "velFy",     loop_cind+1, validfind ))
		setc!( pdset, "lane",      loop_cind, validfind, getc( pdset, "lane",      loop_cind+1, validfind ))
		setc!( pdset, "nlr",       loop_cind, validfind, getc( pdset, "nlr",       loop_cind+1, validfind ))
		setc!( pdset, "nll",       loop_cind, validfind, getc( pdset, "nll",       loop_cind+1, validfind ))
		setc!( pdset, "curvature", loop_cind, validfind, getc( pdset, "curvature", loop_cind+1, validfind ))
		setc!( pdset, "d_cl",      loop_cind, validfind, getc( pdset, "d_cl",      loop_cind+1, validfind ))
		setc!( pdset, "id",        loop_cind, validfind, getc( pdset, "id",        loop_cind+1, validfind ))
		setc!( pdset, "t_inview",  loop_cind, validfind, getc( pdset, "t_inview",  loop_cind+1, validfind ))

		# account for downshift in mat_other_indmap
		id = getc( pdset, "id", loop_cind, validfind )
		if !isa(id, NAtype)
			mat_ind = pdset.dict_other_idmap[id]
			pdset.mat_other_indmap[validfind, mat_ind] = loop_cind
		end

		loop_cind += 1
	end

	if loop_cind == pdset.maxcarind
		# delete the last entry
		setc!( pdset, "id",        loop_cind, validfind, NA )
		setc!( pdset, "posFx",     loop_cind, validfind, NA )
		setc!( pdset, "posFy",     loop_cind, validfind, NA )
		setc!( pdset, "posFyaw",   loop_cind, validfind, NA )
		setc!( pdset, "velFx",     loop_cind, validfind, NA )
		setc!( pdset, "velFy",     loop_cind, validfind, NA )
		setc!( pdset, "lane",      loop_cind, validfind, NA )
		setc!( pdset, "nlr",       loop_cind, validfind, NA )
		setc!( pdset, "nll",       loop_cind, validfind, NA )
		setc!( pdset, "curvature", loop_cind, validfind, NA )
		setc!( pdset, "d_cl",      loop_cind, validfind, NA )
		setc!( pdset, "id",        loop_cind, validfind, NA )
		setc!( pdset, "t_inview",  loop_cind, validfind, NA )
	end
end
function remove_car_from_frame!( trajdata::DataFrame, carid::Integer, frameind::Integer )

	# returns true if successfully removed

	# remove the car from the specified frame
	@assert( haskey(trajdata, symbol(@sprintf("has_%d", carid))) )
	@assert( frameind > 0 && frameind <= size(trajdata,1))

	# ind = trajdata[symbol(@sprintf("has_%d", carid))][frameind]
	carind = carid2ind(trajdata, carid, frameind)
	if carind == -1
		return false
	end

	while haskey(trajdata, symbol(@sprintf("id_%d", carind+1)))
		# move it down
		setc!( trajdata, "id",            carind, frameind, getc( trajdata, "id",            carind+1, frameind) )
		setc!( trajdata, "posEx",         carind, frameind, getc( trajdata, "posEx",         carind+1, frameind) )
		setc!( trajdata, "posEy",         carind, frameind, getc( trajdata, "posEy",         carind+1, frameind) )
		setc!( trajdata, "velEx",         carind, frameind, getc( trajdata, "velEx",         carind+1, frameind) )
		setc!( trajdata, "velEy",         carind, frameind, getc( trajdata, "velEy",         carind+1, frameind) )
		setc!( trajdata, "posGx",         carind, frameind, getc( trajdata, "posGx",         carind+1, frameind) )
		setc!( trajdata, "posGy",         carind, frameind, getc( trajdata, "posGy",         carind+1, frameind) )
		setc!( trajdata, "velGx",         carind, frameind, getc( trajdata, "velGx",         carind+1, frameind) )
		setc!( trajdata, "velGy",         carind, frameind, getc( trajdata, "velGy",         carind+1, frameind) )
		setc!( trajdata, "yawG",          carind, frameind, getc( trajdata, "yawG",          carind+1, frameind) )
		setc!( trajdata, "lane",          carind, frameind, getc( trajdata, "lane",          carind+1, frameind) )
		setc!( trajdata, "lane_offset",   carind, frameind, getc( trajdata, "lane_offset",   carind+1, frameind) )
		setc!( trajdata, "lane_tangent",  carind, frameind, getc( trajdata, "lane_tangent",  carind+1, frameind) )
		setc!( trajdata, "angle_to_lane", carind, frameind, getc( trajdata, "angle_to_lane", carind+1, frameind) )
		setc!( trajdata, "velLs",         carind, frameind, getc( trajdata, "velLs",         carind+1, frameind) )
		setc!( trajdata, "velLd",         carind, frameind, getc( trajdata, "velLd",         carind+1, frameind) )
		setc!( trajdata, "posRLs",        carind, frameind, getc( trajdata, "posRLs",        carind+1, frameind) )
		setc!( trajdata, "posRLd",        carind, frameind, getc( trajdata, "posRLd",        carind+1, frameind) )

		# account from the downshift in has_ field
		if carind_exists( trajdata, carind+1, frameind )
			carid2 = carind2id( trajdata, carind+1, frameind )
			setc_has!( trajdata, carid2, frameind, carind )
		end

		carind += 1
	end

	# delete the last entry
	setc!( trajdata, "id",            carind, frameind, NA )
	setc!( trajdata, "posEx",         carind, frameind, NA )
	setc!( trajdata, "posEy",         carind, frameind, NA )
	setc!( trajdata, "velEx",         carind, frameind, NA )
	setc!( trajdata, "velEy",         carind, frameind, NA )
	setc!( trajdata, "posGx",         carind, frameind, NA )
	setc!( trajdata, "posGy",         carind, frameind, NA )
	setc!( trajdata, "velGx",         carind, frameind, NA )
	setc!( trajdata, "velGy",         carind, frameind, NA )
	setc!( trajdata, "yawG",          carind, frameind, NA )
	setc!( trajdata, "lane",          carind, frameind, NA )
	setc!( trajdata, "lane_offset",   carind, frameind, NA )
	setc!( trajdata, "lane_tangent",  carind, frameind, NA )
	setc!( trajdata, "angle_to_lane", carind, frameind, NA )
	setc!( trajdata, "velLs",         carind, frameind, NA )
	setc!( trajdata, "velLd",         carind, frameind, NA )
	setc!( trajdata, "posRLs",        carind, frameind, NA )
	setc!( trajdata, "posRLd",        carind, frameind, NA )

	# pull the car from has_ field
	setc_has!( trajdata, carid, frameind, -1 )

	return true
end
function remove_cars_from_frame!( trajdata::DataFrame, frameind::Integer )

	maxncars = get_max_num_cars(trajdata)

	for carind = 0 : maxncars

		# account from the removal in has_ field
		carid = carind2id(trajdata, carind, frameind)
		if carind_exists( trajdata, carind, frameind )

			setc_has!( trajdata, carid, frameind, -1)

			setc!( trajdata, "id",            carind, frameind, NA )
			setc!( trajdata, "posEx",         carind, frameind, NA )
			setc!( trajdata, "posEy",         carind, frameind, NA )
			setc!( trajdata, "velEx",         carind, frameind, NA )
			setc!( trajdata, "velEy",         carind, frameind, NA )
			setc!( trajdata, "posGx",         carind, frameind, NA )
			setc!( trajdata, "posGy",         carind, frameind, NA )
			setc!( trajdata, "velGx",         carind, frameind, NA )
			setc!( trajdata, "velGy",         carind, frameind, NA )
			setc!( trajdata, "yawG",          carind, frameind, NA )
			setc!( trajdata, "lane",          carind, frameind, NA )
			setc!( trajdata, "lane_offset",   carind, frameind, NA )
			setc!( trajdata, "lane_tangent",  carind, frameind, NA )
			setc!( trajdata, "angle_to_lane", carind, frameind, NA )
			setc!( trajdata, "velLs",         carind, frameind, NA )
			setc!( trajdata, "velLd",         carind, frameind, NA )
			setc!( trajdata, "posRLs",        carind, frameind, NA )
			setc!( trajdata, "posRLd",        carind, frameind, NA )
		end
	end
end
function remove_cars_from_frame!( pdset::PrimaryDataset, validfind::Integer )

	for carind = 0 : pdset.maxcarind

		id = getc( pdset, "id", carind, validfind )
		if !isa(id, NAtype)

			mat_ind = pdset.dict_other_idmap[id]
			pdset.mat_other_indmap[validfind, mat_ind] = -1

			setc!( pdset, "id",        carind, validfind, NA )
			setc!( pdset, "posFx",     carind, validfind, NA )
			setc!( pdset, "posFy",     carind, validfind, NA )
			setc!( pdset, "posFyaw",   carind, validfind, NA )
			setc!( pdset, "velFx",     carind, validfind, NA )
			setc!( pdset, "velFy",     carind, validfind, NA )
			setc!( pdset, "lane",      carind, validfind, NA )
			setc!( pdset, "nlr",       carind, validfind, NA )
			setc!( pdset, "nll",       carind, validfind, NA )
			setc!( pdset, "curvature", carind, validfind, NA )
			setc!( pdset, "d_cl",      carind, validfind, NA )
			setc!( pdset, "id",        carind, validfind, NA )
			setc!( pdset, "t_inview",  carind, validfind, NA )
		end
	end
end
function remove_car!( pdset::PrimaryDataset, carid::Integer )

	@assert(haskey(pdset.dict_other_idmap, carid))
	matind = pdset.dict_other_idmap[carid]

	# removes all instances of the given car from the pdset
	for validfind = 1 : length(pdset.validfind2frameind)
		carind = pdset.mat_other_indmap[validfind, matind]
		if carind != -1
			remove_car_from_frame!( pdset, carind, validfind )
		end
	end

	# remove id from mat_other_indmap 
	pdset.mat_other_indmap = pdset.mat_other_indmap[:,[1:matind-1,matind+1:end]]

	# shift everyone else down
	keyset = collect(keys(pdset.dict_other_idmap))
	for key in keyset
		matind2 = pdset.dict_other_idmap[key]
		if matind2 > matind
			pdset.dict_other_idmap[key] = matind2-1
		end
	end

	# remove id from dict_other_idmap
	delete!(pdset.dict_other_idmap, carid)

	pdset
end

function find_slot_for_car!( trajdata::DataFrame, frameind::Integer, maxncars = -2 )

	# returns the index within the frame to which the car can be added
	# adds a new slot if necessary

	if maxncars < -1
		maxncars = get_max_num_cars(trajdata)
	end

	ncars = ncars_in_frame( trajdata, frameind, maxncars)
	if ncars > maxncars
		# we have no extra slots, make one
		return add_car_slot!( trajdata )
	else
		# we have enough slots; use the first one
		return ncars
	end
end
function find_slot_for_car!( pdset::DataFrame, validfind::Integer )

	# returns the index within the frame to which the car can be added
	# adds a new slot if necessary

	ncars = ncars_in_frame( pdset, validfind )
	if ncars > pdset.maxcarind
		# we have no extra slots, make one
		return add_car_slot!( pdset )
	else
		# we have enough slots; use the first one
		return ncars # this is correct since ncars-1 is the last ind and we want +1 from that
	end
end

function copy_trace!(
    dest::PrimaryDataset,
    source::PrimaryDataset,
    carid::Integer,
    validfind_start_source::Integer,
    validfind_end_source::Integer,
    validfind_start_dest::Integer=validfind_start_source,
    )

    #=
    Copy all instances of a given vehicle in source::PrimaryDataset
    between the given validfinds

    This will skip any validfinds in which the vehicle is not present

    This will fail if the validfinds given are not inbounds or decreasing
    =#

    @assert(validfind_end_source ≥ validfind_start_source)

    validfind_dest = validfind_start_dest - 1
    for validfind = validfind_start_source : validfind_end_source
    	validfind_dest += 1

        carind = carid2ind_or_negative_two_otherwise(source, carid, validfind)
        if carind != -2
            copy_vehicle!(dest, source, carind, validfind, validfind_dest)
        end
    end
    
    dest
end
function copy_vehicle!(
    dest::PrimaryDataset,
    source::PrimaryDataset,
    carind_source::Integer,
    validfind_source::Integer,
    validfind_dest::Integer=validfind_source,
    )

    #=
    Copy the data for a single vehicle in source to dest
    This will fail if the validfind is invalid
    This will fail if the carid is not in source
    =#

    @assert(validfind_inbounds(source, validfind_source))
    @assert(validfind_inbounds(dest, validfind_dest))

    # ---------------------------
    # get / create carind_dest

    carid = carind2id(source, carind_source, validfind_source)
    if !idinframe(dest, carid, validfind_dest)
        add_car_to_validfind!(dest, carid, validfind_dest)
    end
    carind_dest = carid2ind(dest, carid, validfind_dest)
    
    # ---------------------------
    # set values

    if carind_dest == CARIND_EGO
        frameind_source = validfind2frameind(source, validfind_source)
        frameind_dest = validfind2frameind(dest, validfind_dest)

        for col = 1 : ncol(source.df_ego_primary)
            dest.df_ego_primary[frameind_dest, col] = source.df_ego_primary[frameind_source, col]
        end
    else
        col_source = dest.df_other_ncol_per_entry * carind_source
        col_dest = dest.df_other_ncol_per_entry * carind_dest
        for col_ind in 1 : dest.df_other_ncol_per_entry
            col_source += 1
            col_dest += 1
            dest.df_other_primary[validfind_dest, col_dest] = source.df_other_primary[validfind_source, col_source]
        end
    end

    dest
end

function get_num_other_cars_in_frame( trajdata::DataFrame, frameind::Integer, maxncars = -2 )

	if maxncars < -1
		maxncars = get_max_num_cars(trajdata)
	end

	ncars = 0
	for carind = 0 : maxncars
		if carind_exists(trajdata, carind, frameind)
			ncars += 1
		end
	end
	ncars
end
function get_num_other_cars_in_frame( pdset::PrimaryDataset, validfind::Integer )
	ncars = 0
	for carind = 0 : pdset.maxcarind
		if indinframe(pdset, carind, validfind)
			ncars += 1
		end
	end
	ncars
end
get_num_cars_in_frame( pdset::PrimaryDataset, validfind::Integer ) = get_num_other_cars_in_frame(pdset, validfind) + 1

function add_car_slot!( trajdata::DataFrame, maxncars = -2 )
	# increases the number of observed car column sets by 1

	if maxncars < -1
		maxncars = get_max_num_cars(trajdata)
	end

	carind = maxncars+1

	na_arr = Array(Any, size(trajdata,1))
	fill!(na_arr, NA)

	trajdata[symbol(@sprintf("id_%d",            carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posEx_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posEy_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velEx_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velEy_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posGx_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posGy_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velGx_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velGy_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("yawG_%d",          carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("lane_%d",          carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("lane_offset_%d",   carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("lane_tangent_%d",  carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("angle_to_lane_%d", carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velLs_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("velLd_%d",         carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posRLs_%d",        carind))] = copy(na_arr)
	trajdata[symbol(@sprintf("posRLd_%d",        carind))] = copy(na_arr)

	return maxncars+1
end
# function add_car_slot!( pdset::PrimaryDataset )
# 	# increases the number of observed car column sets by 1
# 	# returns the index of the newly added slot
#   # DEPRECATED BECAUSE LaneTag is not in Trajdata.jl
# 	num_rows = nrow(pdset.df_other_primary)
# 	carind = pdset.maxcarind + 1 # new index to add

# 	for (str, typ) in (("posGx",    Float64),
# 					   ("posGy",    Float64),
# 					   ("posGyaw",  Float64),
# 					   ("posFx",    Float64),
# 					   ("posFy",    Float64),
# 					   ("posFyaw",  Float64),
# 					   ("velFx",    Float64),
# 					   ("velFy",    Float64),
# 					   ("lanetag",  LaneTag),
# 					   ("nlr",      Int8),
# 					   ("nll",      Int8),
# 					   ("curvature",Float64),
# 					   ("d_cl",     Float64),
# 					   ("d_mr",     Float64),
# 					   ("d_ml",     Float64),
# 					   ("d_merge",  Float64),
# 					   ("d_split",  Float64),
# 					   ("id",       Uint32),
# 					   ("t_inview", Float64),
# 					   ("trajind",  Uint32),
# 					  )

# 		pdset.df_other_primary[symbol(@sprintf("%s_%d",str,carind))] = DataArray(typ, num_rows)
# 	end

# 	return carind
# end

function frames_contain_carid( trajdata::DataFrame, carid::Integer, startframeind::Int, horizon::Int; frameskip::Int=1 )
		
	if startframeind+horizon > size(trajdata,1)
		return false
	end

	symb = symbol(@sprintf("has_%d", carid))
	if haskey(trajdata, symb)

		for j = 0 : frameskip : horizon
			if trajdata[symb][startframeind+j] == -1
				return false
			end
		end

		return true
	end
	return false
end
function frames_contain_carid( pdset::PrimaryDataset, carid::Integer, startvalidfind::Int, endvalidfind::Int; frameskip::Int=1 )
		
	if !validfind_inbounds(pdset, startvalidfind) || !validfind_inbounds(pdset, endvalidfind)
		return false
	end
	if carid == CARID_EGO
		return true
	end

	symb = symbol(@sprintf("has_%d", carid))
	if !haskey(pdset.dict_other_idmap, carid)
		return false
	end

	validfind = startvalidfind
	while idinframe(pdset, carid, validfind)
		validfind = jumpframe(pdset, validfind, frameskip)
		if validfind > endvalidfind
			return true
		end
	end
	return false
end

function extract_continuous_segments( frame_contains_carid::AbstractVector{Bool} )

	#=
	Find continuous segments for the given occupation vector
	Turns it into a list of monotinically increasing (start, end) pairs
	represented as a 1D array
	=#

	segments = Int[]

	for (i,contains_carid) in enumerate(frame_contains_carid)
		if contains_carid
			if isempty(segments) || segments[end] != i-1
				# start a new segment
				append!(segments, [i, i])
			else
				# extend the segment by one
				segments[end] = i
			end
		end
	end

	segments
end

function spanning_validfinds( pdset::PrimaryDataset, carid::Integer )
	# obtain the min and max validfind where this car can be found
	mat_ind = pdset.dict_other_idmap[carid]
	ind_lo = findfirst(x->x!=-1, pdset.mat_other_indmap[:,mat_ind])
	ind_hi = findfirst(x->x!=-1, reverse(pdset.mat_other_indmap[:,mat_ind]))
	(ind_lo, ind_hi)
end

function _get_validfinds_containing_carid!( validfind_contains_carid::AbstractVector{Bool}, pdset::PrimaryDataset, carid::Integer )
	@assert(carid_exists(pdset, carid))
	for validfind in 1 : length(validfind_contains_carid)
		validfind_contains_carid[validfind] = idinframe(pdset, carid, validfind)
	end
	validfind_contains_carid
end
function get_validfinds_containing_carid( pdset::PrimaryDataset, carid::Integer )
	validfind_contains_carid = falses(nvalidfinds(pdset))
	_get_validfinds_containing_carid!(validfind_contains_carid, pdset, carid)
end

function are_validfinds_continuous(pdset::PrimaryDataset, validfind_start::Int, validfind_end::Int)
	# true if validfinds are continuous between and including validfind start -> end

	frameind_start = validfind2frameind(pdset, validfind_start)
	frameind_end   = validfind2frameind(pdset, validfind_end)

	if frameind_start == 0 || frameind_end == 0
		return false
	end

	for frameind = frameind_start + 1 : frameind_end - 1
		if frameind2validfind(pdset, frameind) == 0
			return false
		end
	end
	true
end

# Helper Functions
# -------------------------
function quat2euler{T <: Real}( quat::Vector{T} )
	# convert a quaternion to roll-pitch-yaw
	
	d = norm(quat)
	w = quat[1]/d
	x = quat[2]/d
	y = quat[3]/d
	z = quat[4]/d

	y2 = y*y
	roll  = atan2(y*z+w*x, 0.5-x*x-y2)
	pitch = asin(-2*(x*z + w*y))
	yaw   = atan2(x*y+w*z, 0.5-y2-z*z)

	return (roll, pitch, yaw)
end
function euler2quat( roll::Real, pitch::Real, yaw::Real )

	hroll = 0.5*roll
	hpitch = 0.5*pitch
	hyaw = 0.5*yaw

	c_r = cos(hroll)
	s_r = sin(hroll)
	c_p = cos(hpitch)
	s_p = sin(hpitch)
	c_y = cos(hyaw)
	s_y = sin(hyaw)

	w2 = c_r*c_p*c_y + s_r*s_p*s_y
	x2 = s_r*c_p*c_y - c_r*s_p*s_y
	y2 = c_r*s_p*c_y + s_r*c_p*s_y
	z2 = c_r*c_p*s_y - s_r*s_p*c_y

	return [w2, x2, y2, z2]
end
function global2ego( egocarGx::Real, egocarGy::Real, egocarYaw::Real, posGx::Real, posGy::Real )

	# pt = [posGx, posGy]
	# eo = [egocarGx, egocarGy]

	# # translate to be relative to ego car
	# pt -= eo

	# # rotate to be in ego car frame
	# R = [ cos(egocarYaw) sin(egocarYaw);
	#      -sin(egocarYaw) cos(egocarYaw)]
	# pt = R*pt

	# return (pt[1], pt[2]) # posEx, posEy

	s, c = sin(egocarYaw), cos(egocarYaw)
	Δx = posGx - egocarGx
	Δy = posGy - egocarGy
	(c*Δx + s*Δy, c*Δy - s*Δx)
end
function global2ego( egocarGx::Real, egocarGy::Real, egocarYaw::Real, posGx::Real, posGy::Real, yawG::Real )

	posEx, posEy = global2ego( egocarGx, egocarGy, egocarYaw, posGx, posGy)
	yawE = mod2pi(yawG - egocarYaw)

	return (posEx, posEy, yawE)
end
function ego2global( egocarGx::Real, egocarGy::Real, egocarYaw::Real, posEx::Real, posEy::Real )

	# pt = [posEx, posEy]
	# eo = [egocarGx, egocarGy]

	# # rotate
	# c, s = cos(egocarYaw), sin(egocarYaw)
	# R = [ c -s;
	#       s  c]
	# pt = R*pt

	# # translate
	# pt += eo

	# return (pt[1], pt[2]) # posGx, posGy

	c, s = cos(egocarYaw), sin(egocarYaw)
	(c*posEx -s*posEy + egocarGx, s*posEx +c*posEy + egocarGy)
end
function ego2global( egocarGx::Real, egocarGy::Real, egocarYaw::Real, posEx::Real, posEy::Real, yawE::Real )

	posGx, posGy = ego2global( egocarGx, egocarGy, egocarYaw, posEx, posEy)
	yawG = mod2pi(yawE + egocarYaw)

	return (posGx, posGy, yawG)
end
isnum(s::String) = ismatch(NUMBER_REGEX, s) || s == "Inf" || s == "inf" || s == "-Inf" || s == "-inf" || s == "+Inf" || s == "+inf"

end # end module