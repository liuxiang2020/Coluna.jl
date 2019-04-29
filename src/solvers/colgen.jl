struct ColumnGeneration <: AbstractSolver end

mutable struct ColumnGenerationData <: AbstractSolverData
    incumbents::Incumbents
    has_converged::Bool
    is_feasible::Bool
end

function ColumnGenerationData(S::Type{<:AbstractObjSense})
    return ColumnGenerationData(Incumbents(S), false, true)
end

# Data needed for another round of column generation
struct ColumnGenerationRecord <: AbstractSolverRecord
    incumbents::Incumbents
end

# Overload of the solver interface
function setup!(::Type{ColumnGeneration}, formulation, node)
    @logmsg LogLevel(-1) "Setup ColumnGeneration."
    return ColumnGenerationData(formulation.master.obj_sense)
end

function run!(::Type{ColumnGeneration}, solver_data::ColumnGenerationData,
              formulation, node, parameters)
    @logmsg LogLevel(-1) "Run ColumnGeneration."
    return colgen_solver_ph2(solver_data, formulation)
end

function setdown!(::Type{ColumnGeneration}, 
                 solver_record::ColumnGenerationRecord, formulation, node)
    @logmsg LogLevel(-1) "Record ColumnGeneration."
    set!(node.incumbents, solver_record.incumbents)
end

# Internal methods to the column generation
function update_pricing_problem(sp_form::Formulation, dual_sol::DualSolution)

    for (id, var) in filter(_active_pricing_sp_var_ , getvars(sp_form))
        setcurcost!(var, getperencost(var))
    end

    coefficient_matrix = getcoefmatrix(sp_form.parent_formulation)

    for (var_id, var) in getvars(sp_form)
        for (constr_id, dual_val) in getsol(dual_sol)
            coeff = coefficient_matrix[constr_id, var_id]
            setcurcost!(var, getcurcost(var) - dual_val * coeff)
        end
    end
    for (var_id, var) in getvars(sp_form)
        commit_cost_change!(sp_form, var)
    end

    return false
end

function update_pricing_target(sp_form::Formulation)
    # println("pricing target will only be needed after automating convexity constraints")
end

function compute_original_cost(sp_sol, sp_form)
    val = sum(getperencost(getvar(sp_form, var_id)) * value for (var_id, value) in sp_sol)
    return val
end

function insert_cols_in_master(master_form::Formulation,
                               sp_form::Formulation,
                               sp_sols::Vector{PrimalSolution{S}}) where {S}

    # println("\e[1;32m insert cols in master \e[00m")
    sp_uid = getuid(sp_form)
    #mbship = master_form.memberships
    nb_of_gen_col = 0
    
    #var_uids = getvar_uids(sp_form, PricingSpSetupVar)
    #@assert length(var_uids) == 1
    #setup_var_uid = var_uids[1]

    # @show sp_sols

    coef_matrix = getcoefmatrix(master_form)
    partialsol_matrix = getpartialsolmatrix(master_form)

    for sp_sol in sp_sols
        if getvalue(sp_sol) < -0.0001 # TODO use tolerance
            # println(" >>>> \e[33m  create new column \e[00m")

            ### TODO  : check if sp sol exists as a registered column

            #if id_of_existing_mc > 0 # already exists
            #    @warn string("column already exists as", id_of_existing_mc)
            #    continue
            # end

            ### create new column
            nb_of_gen_col += 1
            ref = getvarcounter(master_form) + 1
            name = string("MC", sp_uid, "_", ref)
            cost = compute_original_cost(sp_sol, sp_form)
            lb = 0.0
            ub = Inf
            kind = Continuous
            duty = MasterCol
            sense = Positive
            mc = set_var!(
                master_form, name, duty; cost = cost, lb = lb, ub = ub,
                kind = kind, sense = sense, members = sp_sol
            )
            # mc_id = getid(mc)

            # ### Record Sp solution
            # for (var_id, var_val) in sp_sol
            #     partialsol_matrix[mc_id, var_id] = var_val
            # end
            #==add_partialsol!(master_form, mc)

            ### check if column exists
            id_of_existing_mc = - 1
            for (col_id, col_var, col_members) in columns(partialsol_matrix)
                if (col_members == partialsol_matrix[:, mc_id])
                    id_of_existing_mc = col_id
                    break
                end
            end
            if (id_of_existing_mc != mc_id)
                @warn string("column already exists as", id_of_existing_mc)
            end
            ==#

            # ### Compute column vector
            # # This adds the column to the convexity constraints automatically
            # # since the setup variable is in the sp solution and it has a
            # # a coefficient of 1.0 in the convexity constraints
            # for (var_id, var_val) in getsol(sp_sol)
            #     for (constr_id, var_coef) in coef_matrix[:,var_id]
            #         coef_matrix[constr_id,mc_id] = var_val * var_coef
            #         commit_coef_matrix_change!(
            #             master_form,
            #             constr_id, mc_id, var_val * var_coef
            #         )
            #     end
            # end


            #update_moi_membership(master_form, mc_var)
            # println("\e[43m column added \e[00m")
            #@show string("added column ", mc_id, mc_var)
            # TODO  do while sp_sol.next exists
        end
    end

    return nb_of_gen_col
end

function compute_pricing_dual_bound_contrib(sp_form::Formulation,
                                            sp_sol_value::PrimalBound{S},
                                            sp_lb::Float64,
                                            sp_ub::Float64) where {S}
    # Since convexity constraints are not automated and there is no stab
    # the pricing_dual_bound_contrib is just the reduced cost * multiplicty
    if ( sp_sol_value <= 0) 
        contrib =  sp_sol_value * sp_ub
    else
        contrib =  sp_sol_value * sp_lb
    end
    
        
    # @logmsg LogLevel(-2) string("princing prob has contribution = ", contrib)
    return contrib
end

function gen_new_col(master_form::Formulation,
                     sp_form::Formulation,
                     dual_sol::DualSolution,
                     sp_lb::Float64,
                     sp_ub::Float64)
    
    # @timeit to(alg) "gen_new_col" begin

    #flag_need_not_generate_more_col = 0 # Not used
    flag_is_sp_infeasible = -1
    #flag_cannot_generate_more_col = -2 # Not used
    #dual_bound_contrib = 0 # Not used
    #pseudo_dual_bound_contrib = 0 # Not used

    # TODO renable this. Needed at least for the diving
    # if can_not_generate_more_col(princing_prob)
    #     return flag_cannot_generate_more_col
    # end



    # Compute target
    update_pricing_target(sp_form)


    # Reset var bounds, var cost, sp minCost
    if update_pricing_problem(sp_form, dual_sol) # Never returns true
        #     This code is never executed because update_pricing_prob always returns false
        #     @logmsg LogLevel(-3) "pricing prob is infeasible"
        #     # In case one of the subproblem is infeasible, the master is infeasible
        #     compute_pricing_dual_bound_contrib(alg, pricing_prob)
        #     return flag_is_sp_infeasible
    end
    # if alg.colgen_stabilization != nothing && true #= TODO add conds =#
    #     # switch off the reduced cost estimation when stabilization is applied
    # end

    # Solve sub-problem and insert generated columns in master
    # @logmsg LogLevel(-3) "optimizing pricing prob"
    #@timeit to(alg) "optimize!(pricing_prob)"
    #begin
    status, value, p_sols, d_sol = optimize!(sp_form)
    #end
    
    pricing_dual_bound_contrib = compute_pricing_dual_bound_contrib(sp_form, value, sp_lb, sp_ub)
    # @show pricing_dual_bound_contrib
    
    if status != MOI.OPTIMAL
        # @logmsg LogLevel(-3) "pricing prob is infeasible"
        return flag_is_sp_infeasible
    end
    
    insertion_status = insert_cols_in_master(master_form, sp_form, p_sols)
    
    return (insertion_status, pricing_dual_bound_contrib)

    #end # @timeit to(alg) "gen_new_col" begin

end

function gen_new_columns(reformulation::Reformulation,
                         dual_sol::DualSolution{S},
                         sp_lbs::Dict{FormId, Float64},
                         sp_ubs::Dict{FormId, Float64}) where {S}

    nb_new_cols = 0
    dual_bound_contrib = DualBound(S, 0.0)
    master_form = getmaster(reformulation)
    for sp_form in reformulation.dw_pricing_subprs
        sp_uid = getuid(sp_form)
        (gen_status, contrib) = gen_new_col(master_form, sp_form, dual_sol, sp_lbs[sp_uid], sp_ubs[sp_uid])

        if gen_status > 0
            nb_new_cols += gen_status
            dual_bound_contrib += float(contrib)
        elseif gen_status == -1 # Sp is infeasible
            return (gen_status, Inf)
        end
    end
    return (nb_new_cols, dual_bound_contrib)
end

#==function solve_restricted_mast(master::Formulation)
    # @logmsg LogLevel(-2) "starting solve_restricted_mast"
    #@timeit to(alg) "solve_restricted_mast" begin
 
    # println("Solving master problem: ")
    # @show master
    status, value, primal_sols, dual_sol = optimize!(master)
    # @show status
    # @show result_count = MOI.get(master.moi_optimizer, MOI.ResultCount())
    # @show primal_status = MOI.get(master.moi_optimizer, MOI.PrimalStatus())
    # @show dual_status = MOI.get(master.moi_optimizer, MOI.DualStatus())
    # @show value
    # @show primal_sols
    # @show dual_sol
    # readline()
    #end # @timeit to(alg) "solve_restricted_mast"
    return status, value, primal_sols[1], dual_sol
end ==#


function compute_mast_dual_bound_contrib(alg::ColumnGenerationData,
                                      restricted_master_sol_value::PrimalBound{S})where {S}
    # stabilization = alg.colgen_stabilization
    # This is commented because function is_active does not exist
    # if stabilization == nothing# || !is_active(stabilization)
        return DualBound(S, restricted_master_sol_value)
    # else
    #     error("compute_mast_dual_bound_contrib" *
    #           "is not yet implemented with stabilization")
    # end
end

function update_lagrangian_dual_bound(alg::ColumnGenerationData,
                                      restricted_master_sol_value::PrimalBound{S},
                                      pricing_sp_dual_bound_contrib::DualBound{S},
                                      update_dual_bound::Bool) where {S}
    mast_lagrangian_bnd = DualBound(S, 0)
    mast_lagrangian_bnd += compute_mast_dual_bound_contrib(alg, restricted_master_sol_value)
    # @logmsg LogLevel(-2) string("dual bound contrib of master = ",
    #                            mast_lagrangian_bnd)

    # Subproblem contributions
   # for pricing_prob in alg.extended_problem.pricing_vect
   #     mast_lagrangian_bnd += alg.pricing_contribs[pricing_prob]
    #    @logmsg LogLevel(-2) string("dual bound contrib of SP[",
   #                pricing_prob.prob_ref, "] = ",
   #                alg.pricing_contribs[pricing_prob],
   #                ". mast_lagrangian_bnd = ", mast_lagrangian_bnd)
   # end

    mast_lagrangian_bnd += pricing_sp_dual_bound_contrib

    # @logmsg LogLevel(-2) string("UPDATED CURRENT DUAL BOUND. lp_primal_bound = ",
    #           alg.sols_and_bounds.alg_inc_lp_primal_bound,
    #           ". mast_lagrangian_bnd = ", mast_lagrangian_bnd)

    #TODO: clarify this comment
    # by Guillaume : subgradient algorithm needs to know when the incumbent
    if update_dual_bound
        set_ip_dual_bound!(alg.incumbents, mast_lagrangian_bnd)
        #update_dual_lp_bound(alg.incumbents, mast_lagrangian_bnd) TODO : should provide the dual lp sol
    else # if alg.colgen_stabilization != nothing
        set_ip_dual_bound!(alg.incumbents, mast_lagrangian_bnd)
        #update_dual_lp_bound(alg.incumbents, mast_lagrangian_bnd)
    end
    return mast_lagrangian_bnd
end

function colgen_solver_ph2(alg::ColumnGenerationData,
                           reformulation::Reformulation)::ColumnGenerationRecord
    nb_cg_iterations = 0
    # Phase II loop: Iterate while can generate new columns and
    # termination by bound does not apply
    master_form = reformulation.master
    sp_lbs = Dict{FormId, Float64}()
    sp_ubs = Dict{FormId, Float64}()

    # collect multiplicity current bounds for each sp
    for sp_form in reformulation.dw_pricing_subprs
        sp_uid = getuid(sp_form)
        lb_convexity_constr_id = reformulation.dw_pricing_sp_lb[sp_uid]
        ub_convexity_constr_id = reformulation.dw_pricing_sp_ub[sp_uid]
        sp_lbs[sp_uid] = getcurrhs(getconstr(master_form, lb_convexity_constr_id))
        sp_ubs[sp_uid] = getcurrhs(getconstr(master_form, ub_convexity_constr_id))
    end

    # @show sp_lbs

    while true
        # GLPK.write_lp(getinner(get_optimizer(master_form)), string(dirname(@__FILE__ ), "/mip_", nb_cg_iterations,".lp"))
        # solver restricted master lp and update bounds
        before_master = time()
        status_rm, master_val, primal_sols, dual_sol = optimize!(master_form)
        mst_time = (time() - before_master)

        #status_rm, mst_time, b, gc, allocs = @timed solve_restricted_mast(reformulation.master)
        # status_rm, mas_time = solve_restricted_mast(alg)
        # if alg.colgen_stabilization != nothing # Never evals to true
        #     # This function does not exist
        #     init_after_solving_restricted_mast(colgen_stabilization,
        #             computeOptimGap(alg), nbCgIterations,
        #             curMaxLevelOfSubProbRestriction)
        # end

        if status_rm == MOI.INFEASIBLE || status_rm == MOI.INFEASIBLE_OR_UNBOUNDED
            # @logmsg LogLevel(-2) "master restrcited lp solver returned infeasible"
            #mark_infeasible(alg)
            return ColumnGenerationRecord(alg.incumbents)
        end
        set_lp_primal_sol!(alg.incumbents, primal_sols[1])
        set_lp_dual_sol!(alg.incumbents, dual_sol)

        # if integer update_primal_ip_incumbents(alg.incumbents, master_val, primal_sol.members)
        ##cleanup_restricted_mast_columns(alg, nb_cg_iterations)
        nb_cg_iterations += 1

        # generate new columns by solving the subproblems
        nb_new_col = 0
        sp_time = 0.0
        while true
            # @logmsg LogLevel(-2) "need to generate new master columns"
            before_sp = time()
            nb_new_col, sp_dual_bound_contrib =  gen_new_columns(reformulation,
                                                                 dual_sol,
                                                                 sp_lbs,
                                                                 sp_ubs)
            sp_time = (time() - before_sp)

            update_lagrangian_dual_bound(alg, master_val, sp_dual_bound_contrib, true)

            # In case subproblem infeasibility results in master infeasibility
            if nb_new_col < 0
                #mark_infeasible(alg)
                return ColumnGenerationRecord(alg.incumbents)
            end
            # if alg.colgen_stabilization == nothing
            #|| !update_after_pricing_problem_solution(alg.colgen_stabilization, nb_new_col)
            # break
            # end
            break
        end

        print_intermediate_statistics(
            alg, nb_new_col, nb_cg_iterations, mst_time, sp_time
        )
        # if alg.colgen_stabilization != nothing
        #     # This function does not exist
        #     update_after_colgen_iteration(alg.colgen_stabilization)
        # end
        #@logmsg LogLevel(-2) string
        # println("colgen iter ", nb_cg_iterations,
        #                            " : inserted ", nb_new_col, " columns")

        lb = get_ip_dual_bound(alg.incumbents)
        ub = min(
            get_lp_primal_bound(alg.incumbents), get_ip_primal_bound(alg.incumbents)
        )

        if nb_new_col == 0 || diff(lb + 0.00001, ub) < 0
            alg.has_converged = true
            return ColumnGenerationRecord(alg.incumbents)
        end
        if nb_cg_iterations > 1000 ##TDalg.max_nb_cg_iterations
            # println("Maximum number of column generation iteration is reached")
            # @logmsg LogLevel(-2) "max_nb_cg_iterations limit reached"
            alg.is_feasible = false
            return ColumnGenerationRecord(alg.incumbents)
        end
        # @logmsg LogLevel(-2) "next colgen ph2 iteration"
    end
    # These lines are never executed becasue there is no break from the outtermost 'while true' above
    # @logmsg LogLevel(-2) "colgen_solver_ph2 has finished"
    # return false
    return ColumnGenerationRecord(alg.incumbents)
end

function print_intermediate_statistics(alg::ColumnGenerationData,
                                       nb_new_col::Int,
                                       nb_cg_iterations::Int,
                                       mst_time::Float64, sp_time::Float64)
    mlp = getvalue(get_lp_primal_bound(alg.incumbents))
    db = getvalue(get_ip_dual_bound(alg.incumbents))
    pb = getvalue(get_ip_primal_bound(alg.incumbents))
    @printf(
            "<it=%i> <et=%i> <mst=%.3f> <sp=%.3f> <cols=%i> <mlp=%.4f> <DB=%.4f> <PB=%.4f>\n",
            nb_cg_iterations, _elapsed_solve_time(), mst_time, sp_time, nb_new_col, mlp, db, pb
    )
end
