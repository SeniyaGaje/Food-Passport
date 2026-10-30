import { before, after, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

// Starts the Firestore and Storage emulators with this project's rules (no real data is touched).
let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-foodpassport',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8') }
  });
});
// Shuts the emulators' test project down after all tests.
after(async () => { await env?.cleanup(); });

// Shared catalogues: any signed-in user can read, no app can write, signed-out users can't read.
for (const collection of ['restaurants', 'quests', 'trails', 'challenges']) {
  test(`${collection}: signed-in reads; all client writes denied`, async () => {
    const signedIn = doc(env.authenticatedContext('alice').firestore(), collection, 'sample');
    await assertSucceeds(getDoc(signedIn));
    await assertFails(setDoc(signedIn, { name: 'changed' }));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), collection, 'sample')));
  });
}

// Personal data: Alice can write her own; Bob and signed-out users can't read or change it.
for (const collection of ['visits', 'stamps', 'trails', 'challenges']) {
  test(`${collection}: owner data is isolated`, async () => {
    const path = `users/alice/${collection}/one`;
    await assertSucceeds(setDoc(doc(env.authenticatedContext('alice').firestore(), path), { progress: 1 }));
    await assertFails(getDoc(doc(env.authenticatedContext('bob').firestore(), path)));
    await assertFails(setDoc(doc(env.authenticatedContext('bob').firestore(), path), { progress: 2 }));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path)));
  });
}

test('only the owner can save a valid quest', async () => {
  const quest = { type: 'New cuisines', duration: 'This month', targetCuisines: 3, budget: 3000,
    maxDistanceKm: 2, startedAt: Timestamp.now() };
  const alice = doc(env.authenticatedContext('alice').firestore(), 'users/alice/quests/active');
  // A valid quest saves; a negative budget or 99 cuisines is rejected.
  await assertSucceeds(setDoc(alice, quest));
  await assertFails(setDoc(alice, { ...quest, budget: -1 }));
  await assertFails(setDoc(alice, { ...quest, targetCuisines: 99 }));
  // Bob can't write Alice's quest.
  await assertFails(setDoc(doc(env.authenticatedContext('bob').firestore(), alice.path), quest));
  await assertSucceeds(deleteDoc(alice));
});

test('quests can be extended with a timestamp only', async () => {
  const quest = { type: 'New cuisines', duration: 'This week', targetCuisines: 3, budget: 3000,
    maxDistanceKm: 2, startedAt: Timestamp.now(), extendedUntil: Timestamp.now() };
  const alice = doc(env.authenticatedContext('alice').firestore(), 'users/alice/quests/active');
  // extendedUntil must be a real timestamp, not text.
  await assertSucceeds(setDoc(alice, quest));
  await assertFails(setDoc(alice, { ...quest, extendedUntil: 'next week' }));
});

test('planned visits: only the owner, with a valid estimate', async () => {
  const plan = { id: 'plan-1', restaurantID: 'dragon-wok', date: Timestamp.now(), estimatedCost: 750, countsTowardsQuest: true };
  const alice = doc(env.authenticatedContext('alice').firestore(), 'users/alice/plannedVisits/plan-1');
  await assertSucceeds(setDoc(alice, plan));
  // A negative estimate, a mismatched id or an extra field are all rejected.
  await assertFails(setDoc(alice, { ...plan, estimatedCost: -5 }));
  await assertFails(setDoc(alice, { ...plan, id: 'other' }));
  await assertFails(setDoc(alice, { ...plan, extra: true }));
  await assertFails(getDoc(doc(env.authenticatedContext('bob').firestore(), alice.path)));
  await assertSucceeds(deleteDoc(alice));
});

test('push tokens: only their owner can register or read them', async () => {
  const token = { token: 'test-registration-token', platform: 'ios', updatedAt: Timestamp.now() };
  const path = 'users/alice/devices/test';
  const alice = doc(env.authenticatedContext('alice').firestore(), path);
  await assertSucceeds(setDoc(alice, token));
  // A token with an unexpected field is rejected, and other users can't read it.
  await assertFails(setDoc(alice, { ...token, unexpected: true }));
  await assertFails(getDoc(doc(env.authenticatedContext('bob').firestore(), path)));
});

test('meal photos: owner upload/read/delete, cross-account access denied', async () => {
  const path = 'users/alice/mealPhotos/12345678-1234-1234-1234-123456789abc.jpg';
  const alice = ref(env.authenticatedContext('alice').storage(), path);
  // Alice can upload and read her own photo.
  await assertSucceeds(uploadBytes(alice, new Uint8Array([255, 216, 255]), { contentType: 'image/jpeg' }));
  await assertSucceeds(getBytes(alice));
  const bob = ref(env.authenticatedContext('bob').storage(), path);
  // Bob can't read or delete it, and neither can a signed-out user.
  await assertFails(getBytes(bob));
  await assertFails(deleteObject(bob));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), path)));
  await assertSucceeds(deleteObject(alice));
});

test('meal photos: oversized files, wrong MIME types and paths rejected', async () => {
  const storage = env.authenticatedContext('alice').storage();
  const valid = ref(storage, 'users/alice/mealPhotos/abcdefab-1234-1234-1234-123456789abc.jpg');
  // Too big (over 5 MB), wrong type, outside a user folder, or another user's folder: all rejected.
  await assertFails(uploadBytes(valid, new Uint8Array(5 * 1024 * 1024 + 1), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(valid, new Uint8Array([1]), { contentType: 'text/plain' }));
  await assertFails(uploadBytes(ref(storage, 'public/photo.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' }));
  await assertFails(uploadBytes(ref(storage, 'users/bob/mealPhotos/abcdefab-1234-1234-1234-123456789abc.jpg'), new Uint8Array([1]), { contentType: 'image/jpeg' }));
});
