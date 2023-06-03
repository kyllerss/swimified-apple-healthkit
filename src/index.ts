import { registerPlugin } from '@capacitor/core';

import type { SwimifiedCapacitorHealthKitPlugin } from './definitions';

const SwimifiedCapacitorHealthKit = registerPlugin<SwimifiedCapacitorHealthKitPlugin>(
  'SwimifiedCapacitorHealthKit',
);

export * from './definitions';
export { SwimifiedCapacitorHealthKit };