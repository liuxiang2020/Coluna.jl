struct PrimalBound{S <: AbstractObjSense} <: AbstractBound
    value::Float64
end
PrimalBound{MinSense}() = PrimalBound{MinSense}(Inf)
PrimalBound{MaxSense}() = PrimalBound{MaxSense}(-Inf)

struct DualBound{S <: AbstractObjSense} <: AbstractBound
    value::Float64
end
DualBound{MinSense}() = DualBound{MinSense}(-Inf)
DualBound{MaxSense}() = DualBound{MaxSense}(Inf)

isbetter(b1::PrimalBound{MinSense}, b2::PrimalBound{MinSense}) = b1.value < b2.value

isbetter(b1::PrimalBound{MaxSense}, b2::PrimalBound{MaxSense}) = b1.value > b2.value

isbetter(b1::DualBound{MinSense}, b2::DualBound{MinSense}) = b1.value > b2.value

isbetter(b1::DualBound{MaxSense}, b2::DualBound{MaxSense}) = b1.value < b2.value

diff(b1::PrimalBound{MinSense}, b2::DualBound{MinSense}) = b1.value - b2.value

diff(b1::DualBound{MinSense}, b2::PrimalBound{MinSense}) = b2.value - b1.value

diff(b1::PrimalBound{MaxSense}, b2::DualBound{MaxSense}) = b2.value - b1.value

diff(b1::DualBound{MaxSense}, b2::PrimalBound{MaxSense}) = b1.value - b2.value

struct PrimalSolution{S <: AbstractObjSense}
    bound::PrimalBound{S}
    sol::Dict{Id{Variable},Float64}
end

function PrimalSolution{S}() where {S <: AbstractObjSense}
    return PrimalSolution{S}(PrimalBound{S}(), Dict{Id{Variable}}())
end

struct DualSolution{S <: AbstractObjSense}
    bound::DualBound{S}
    sol::Dict{Id{Constraint},Float64}
end

function DualSolution{S}() where {S <: AbstractObjSense}
    return DualSolution{S}(PrimalBound{S}(), Dict{Id{Constraint}}())
end
