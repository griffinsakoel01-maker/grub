import { test } from 'node:test';
import assert from 'node:assert/strict';
import { productAllowed, recipeCostCents, scale, toBase } from './pricing';

test('scaling and units', () => {
  assert.equal(scale(250, 2, 6), 750);
  assert.equal(toBase(3, 'tbsp'), 45);
  assert.equal(toBase(1.5, 'kg'), 1500);
});

test('allergy and diet filtering', () => {
  const eggs = { id: 'eggs', name: 'Eggs', unit: 'pcs', allergens: ['eggs'], dietTags: ['egg'] };
  const beef = { id: 'beef', name: 'Beef', unit: 'g', dietTags: ['meat'] };
  assert.equal(productAllowed(eggs, { allergies: ['eggs'] }), false);
  assert.equal(productAllowed(beef, { preferences: ['vegetarian'] }), false);
  assert.equal(productAllowed(beef, {}), true);
});

test('recipe cost uses cheapest price and pantry', () => {
  const r = { id: 'x', name: 'X', category: 'lunch', servings: 2, ingredients: [{ productId: 'rice', amount: 500, unit: 'g' }] };
  const prices = [
    { productId: 'rice', supermarketId: 'a', packageSize: 1000, price: 200 },
    { productId: 'rice', supermarketId: 'b', packageSize: 1000, price: 180 },
  ];
  assert.equal(recipeCostCents(r, 4, prices), 18000); // 1 kg × KSh 180
  assert.equal(recipeCostCents(r, 4, prices, { rice: 500 }), 9000);
  assert.equal(recipeCostCents(r, 4, []), null);
});
