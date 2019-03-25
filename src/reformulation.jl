
function Reformulation(method::SolutionMethod)
    return Reformulation(method, nothing, nothing, Vector{AbstractFormulation}())
end

function Reformulation()
    return Reformulation(DirectMip)
end

function setmaster!(r::Reformulation, f)
    r.master = f
    return
end

function add_dw_pricing_sp!(r::Reformulation, f)
    push!(r.dw_pricing_subprs, f)
    return
end


function fill_annotations_set!(ann_set, varconstr_annotations)
    for (varconstr_id, varconstr_annotation) in varconstr_annotations
        push!(ann_set, varconstr_annotation)
    end
    return
end

function inverse(varconstr_annotations)
    varconstr_in_form = Dict{FormId, Vector{Int}}()
    for (varconstr_id, annotation) in varconstr_annotations
        if !haskey(varconstr_in_form, annotation.unique_id)
            varconstr_in_form[annotation.unique_id] = Int[]
        end
        push!(varconstr_in_form[annotation.unique_id], varconstr_id)
    end
    return varconstr_in_form
end

function build_dw_master!(model::Model,
                          annotation_id::Int,
                          reformulation::Reformulation,
                          formulation::Formulation,
                          vars_in_form::Vector{VarId},
                          constrs_in_form::Vector{ConstrId})


       orig_form = get_original_formulation(model)

 

    membership = SparseVector()
 
    # create convexity constraints
    
    @assert !isempty(reformulation.dw_pricing_subprs)
    for spform in reformulation.dw_pricing_subprs
        # create convexity constraint
        name = "convexity_sp_$(spform.uid)"
        sense = ConstrSense(Equal)
        rhs = 1.0
        vc_type = ConstrType(SubprobConvexity)
        flag = Flag(Static)
        duty = ConstrDuty(MastConvexityConstr)
        conv_constr = Constraint(model,name,sense,vc_type,flag,duty)
        register_constraint!(formulation, conv_constr, rhs, membership)
        # create representative of sp setup var
        setup_var_uid = 1
        
        #var = getvar(spform 
        
    end
    
    # for  master constraints, create associated artificial variables
    # new_vars = Variable[]
    # lb = fill(-Inf, length(vars))
    #  ub = fill(Inf, length(vars))
    #  vtypes = fill(Continuous, length(vars))
    
    # register_variable!(
    
    
    
    # clone pure master variables 
    copy_variables!(formulation, orig_form, vars_in_form)

    # clone pure & mixed  master constraints 
    copy_constraints!(formulation, orig_form, constrs_in_form)

    
  
    
    return
end

function build_dw_pricing_sp!(m::Model, annotation_id::Int,
                           formulation::Formulation,
                           vars_in_form::Vector{VarId},
                           constrs_in_form::Vector{ConstrId})
    orig_form = get_original_formulation(m)
    copy_variables!(formulation, orig_form, vars_in_form)
    copy_constraints!(formulation, orig_form, constrs_in_form)
    return
end

function reformulate!(m::Model, method::SolutionMethod)
    println("Do reformulation.")

    # Create formulations & reformulations
    ann_set = Set{BD.Annotation}()
    fill_annotations_set!(ann_set, m.var_annotations)
    fill_annotations_set!(ann_set, m.constr_annotations)

    # At the moment, BlockDecomposition supports only classic 
    # Dantzig-Wolfe decomposition.
    # TODO : improve all drafts as soon as BlockDecomposition returns a
    # decomposition-tree.

    vars_in_forms = inverse(m.var_annotations)
    constrs_in_forms = inverse(m.constr_annotations)
    @show vars_in_forms
    @show constrs_in_forms


    reformulation = Reformulation(method)
    ann_sorted_by_uid = sort(collect(ann_set), by = ann -> ann.unique_id)
    formulations = Dict{Int, Formulation}()

    
    # Build pricing  subproblems
    master_annotation_id = -1
    for annotation in ann_sorted_by_uid
        f = Formulation(m)
        formulations[annotation.unique_id] = f
        if annotation.problem == BD.Master
             master_annotation_id = annotation.unique_id
        elseif annotation.problem == BD.Pricing
            if haskey(vars_in_forms, annotation.unique_id)
                vars =  vars_in_forms[annotation.unique_id]
            else
                vars = Vector{VarId}()
            end
            if haskey(constrs_in_forms, annotation.unique_id)
                constrs = constrs_in_forms[annotation.unique_id]
            else
                constrs = Vector{ConstrId}()
            end
            add_dw_pricing_sp!(reformulation, f)
            build_dw_pricing_sp!(m, annotation.unique_id, f, vars, constrs)
        else
            error("Not supported yet.")
        end
    end

    # Build Master
    @assert master_annotation_id != -1
    if haskey(vars_in_forms, master_annotation_id)
        vars =  vars_in_forms[master_annotation_id]
    else
        vars = Vector{VarId}()
    end
    if haskey(constrs_in_forms, master_annotation_id)
        constrs = constrs_in_forms[master_annotation_id]
    else
        constrs = Vector{ConstrId}()
    end
    f = formulations[master_annotation_id]
    setmaster!(reformulation, f)
    build_dw_master!(m, master_annotation_id, reformulation, f, vars, constrs)


    # TODO : Register constraints and variables

end

