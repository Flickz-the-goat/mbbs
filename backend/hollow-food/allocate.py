"""Demo allocation: max-min proportional fairness, subject to shared inventory.
Units are synthetic ration portions; NOT medically/nutritionally validated.
"""
from fractions import Fraction
from math import isfinite

from scipy.optimize import linprog

def allocate(demands: list[float], available_units: float) -> list[float]:
    if not isfinite(available_units) or available_units < 0 or any(
        not isfinite(demand) or demand < 0 for demand in demands
    ):
        raise ValueError('Demand and inventory must be finite and nonnegative')
    if not demands:
        return []
    requested = [Fraction(str(demand)) for demand in demands]
    total = sum(requested)
    if not total:
        return [0.0] * len(demands)

    # Normalize the single LP constraint so it works across stock scales.
    limit = min(Fraction(1), Fraction(str(available_units)) / total)
    result = linprog([-1], A_ub=[[1]], b_ub=[float(limit)], bounds=[(0, 1)], method='highs')
    if not result.success:
        raise RuntimeError(result.message)

    # The single constraint binds at the optimum. Use its exact value when
    # converting the solver result to milliunits, where rounding up spends stock.
    fraction = limit if result.x[0] == float(limit) else min(limit, Fraction(str(result.x[0])))
    return [(demand * fraction * 1000 // 1) / 1000 for demand in requested]

if __name__=='__main__':
    print(allocate([12,24,36],36))
