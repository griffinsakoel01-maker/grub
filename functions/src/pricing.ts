// Server-side mirror of the app's costing rules (lib/services/calculation_service.dart)
// so the AI assistant only ever sees prices computed from Grub's own data.

export interface Product {
  id: string;
  name: string;
  unit: string; // g | ml | pcs | bunch | packet
  allergens?: string[];
  dietTags?: string[];
}
export interface Price {
  productId: string;
  supermarketId: string;
  packageSize: number;
  price: number; // KSh per package
  verificationStatus?: string;
}
export interface Ingredient { productId: string; amount: number; unit: string }
export interface Recipe {
  id: string;
  name: string;
  category: string;
  servings: number;
  prepMinutes?: number;
  cookMinutes?: number;
  tags?: string[];
  ingredients: Ingredient[];
}
export interface Profile {
  allergies?: string[];
  preferences?: string[]; // diets
  dislikes?: string[];
}

export function toBase(amount: number, unit: string): number {
  switch (unit) {
    case 'kg':
    case 'l':
      return amount * 1000;
    case 'tbsp':
      return amount * 15;
    case 'tsp':
      return amount * 5;
    case 'cup':
      return amount * 250;
    default:
      return amount;
  }
}

/** Required quantity = original × (selected servings / original servings) */
export function scale(original: number, originalServings: number, selected: number): number {
  return originalServings > 0 ? original * (selected / originalServings) : original;
}

export function productAllowed(p: Product | undefined, profile: Profile): boolean {
  if (!p) return false;
  const allergies = profile.allergies ?? [];
  const diets = profile.preferences ?? [];
  const tags = p.dietTags ?? [];
  if ((p.allergens ?? []).some((a) => allergies.includes(a))) return false;
  if ((profile.dislikes ?? []).includes(p.id)) return false;
  if (diets.includes('vegan') && tags.some((t) => ['meat', 'fish', 'dairy', 'egg'].includes(t))) return false;
  if (diets.includes('vegetarian') && tags.some((t) => ['meat', 'fish'].includes(t))) return false;
  if (diets.includes('pescatarian') && tags.includes('meat')) return false;
  return true;
}

export function recipeAllowed(r: Recipe, products: Map<string, Product>, profile: Profile): boolean {
  return r.ingredients.every((i) => productAllowed(products.get(i.productId), profile));
}

/** Cheapest cost (in cents) of the consumed quantity; null if any ingredient is unpriced. */
export function recipeCostCents(
  r: Recipe,
  servings: number,
  prices: Price[],
  pantry: Record<string, number> = {},
): number | null {
  let total = 0;
  for (const ing of r.ingredients) {
    let need = toBase(scale(ing.amount, r.servings, servings), ing.unit);
    need = Math.max(0, need - (pantry[ing.productId] ?? 0));
    if (need <= 1e-6) continue;
    const options = prices.filter((p) => p.productId === ing.productId && p.packageSize > 0);
    if (options.length === 0) return null;
    const best = Math.min(...options.map((p) => (p.price * 100 * need) / p.packageSize));
    total += best;
  }
  return Math.round(total);
}

export function ksh(cents: number): string {
  return 'KSh ' + Math.round(cents / 100).toLocaleString('en-KE');
}
