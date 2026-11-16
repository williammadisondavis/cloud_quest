const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { makeCoach } = require('./questCoach');

initializeApp();
const db = getFirestore();

exports.completeToday = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  if (request.data?.challengeId !== 'today') {
    throw new HttpsError('invalid-argument', 'Unknown challenge.');
  }

  // No UID, points, or badge value from the Flutter client is trusted.
  const uid = request.auth.uid;
  const challenge = await db.doc('challenges/today').get();
  if (!challenge.exists) {
    throw new HttpsError('failed-precondition', 'No challenge is available.');
  }
  const ref = db.doc(`users/${uid}/progress/today`);
  return db.runTransaction(async (tx) => {
    const previous = await tx.get(ref);
    if (previous.exists && previous.data().completed === true) {
      return {
        completed: true,
        points: previous.data().points,
        badgeId: previous.data().badgeId,
        alreadyCompleted: true,
      };
    }
    tx.set(ref, {
      completed: true,
      points: 10,
      badgeId: 'first-quest',
      completedAt: FieldValue.serverTimestamp(),
    });
    return {
      completed: true,
      points: 10,
      badgeId: 'first-quest',
      alreadyCompleted: false,
    };
  });
});

exports.askQuestCoach = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  const question = request.data?.question;
  if (typeof question !== 'string' || !question.trim() || question.trim().length > 300) {
    throw new HttpsError('invalid-argument', 'Question must be 1 to 300 characters.');
  }
  // Only the callable's verified Auth UID is passed to the read-only tool.
  return makeCoach({ db, uid: request.auth.uid, question: question.trim() });
});
