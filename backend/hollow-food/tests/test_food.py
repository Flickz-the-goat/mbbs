import asyncio
import unittest
from fractions import Fraction

from pydantic import ValidationError

from allocate import allocate
from api import AllocationRequest, Household, allocation, app, predict


HOUSEHOLD = {
    'level_id': 2,
    'household_size': 3,
    'children_count': 1,
    'senior_count': 1,
    'rice_kg': 1,
    'beans_kg': 1,
    'canned_food_count': 2,
    'water_liters': 4,
    'daily_portions_per_person': 2,
    'planning_days': 4,
    'reserve_portions_per_person': 1,
}


class FoodTests(unittest.TestCase):
    def test_proportional_shortage(self):
        self.assertEqual(allocate([12, 24, 36], 36), [6, 12, 18])
        self.assertEqual(allocate([0, 2], 10), [0, 2])
        self.assertEqual(allocate([1, 2], 0), [0, 0])

    def test_rounding_preserves_stock_and_demand(self):
        for demands, stock in [([1, 1, 1], 0.002), ([0.0006], 1), ([1, 2, 3], 0.0115)]:
            with self.subTest(demands=demands, stock=stock):
                result = allocation(AllocationRequest(demands=demands, available_shared_units=stock))
                amounts = result['allocated_units']
                for amount, demand in zip(amounts, demands):
                    self.assertGreaterEqual(amount, 0)
                    self.assertLessEqual(amount, demand)
                total = sum(Fraction(str(amount)) for amount in amounts)
                self.assertEqual(total + Fraction(str(result['remaining_units'])), Fraction(str(stock)))
                self.assertGreaterEqual(result['remaining_units'], 0)

    def test_invalid_quantities_are_rejected(self):
        for quantity in (-1, 'Infinity', 'NaN'):
            with self.subTest(quantity=quantity), self.assertRaises(ValidationError):
                AllocationRequest(demands=[quantity], available_shared_units=1)

    def test_household_counts_and_levels_are_validated(self):
        for overrides in ({'children_count': 3}, {'level_id': 9}, {'level_id': 0}, {'rice_kg': 'NaN'}):
            with self.subTest(overrides=overrides), self.assertRaises(ValidationError):
                Household(**(HOUSEHOLD | overrides))

    def test_bundled_model_predicts(self):
        async def run():
            async with app.router.lifespan_context(app):
                return predict(Household(**HOUSEHOLD))

        result = asyncio.run(run())
        self.assertGreaterEqual(result['predicted_additional_ration_units'], 0)
        self.assertFalse(result['validated_for_real_distribution'])
