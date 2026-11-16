// Seed only the Firestore emulator. This never writes to production.
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Refusing to seed: FIRESTORE_EMULATOR_HOST is not set.');
  process.exit(1);
}
const projectId = process.argv[2];
if (!projectId) {
  console.error('Usage: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node seed.js YOUR_PROJECT_ID');
  process.exit(1);
}
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
initializeApp({ projectId });
getFirestore().doc('challenges/today').set({
  title: 'My First Cloud Quest',
  prompt: 'Explain why an app should verify a learner before awarding points, and why repeating the completion request should not award more points.',
}).then(() => {
  console.log(`Seeded challenges/today in emulator for project ${projectId}`);
  process.exit(0);
}).catch((error) => {
  console.error(error);
  process.exit(1);
});
