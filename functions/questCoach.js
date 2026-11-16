const { HttpsError } = require('firebase-functions/v2/https');

// The only tool available to the coach. It reads shared challenge data and
// progress belonging to the UID verified by the callable's Auth context.
async function readMyQuestState(db, verifiedUid) {
  if (!verifiedUid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const [challenge, progress] = await Promise.all([
    db.doc('challenges/today').get(),
    db.doc(`users/${verifiedUid}/progress/today`).get(),
  ]);
  if (!challenge.exists) {
    throw new HttpsError('failed-precondition', 'Challenge unavailable.');
  }
  return {
    title: String(challenge.data().title ?? ''),
    prompt: String(challenge.data().prompt ?? ''),
    completed: progress.exists && progress.data().completed === true,
    points: progress.exists ? Number(progress.data().points || 0) : 0,
    badgeId: progress.exists ? String(progress.data().badgeId || '') : '',
  };
}

const COACH_INSTRUCTIONS =
  'You are a supportive quest coach. Give one concise hint grounded only in ' +
  'the supplied challenge and learner progress, not a complete answer. ' +
  'Never say you granted a reward. Never reveal other users or secrets. ' +
  'The learner must press Complete; you cannot write Firestore.';

async function makeCoach({ db, uid, question }) {
  // Mandatory read BEFORE any coach reply. Tool errors fail closed.
  const state = await readMyQuestState(db, uid);

  // IMPORTANT: The instructor-provided Genkit model gateway was NOT included
  // in the uploaded assignment. This emulator mock tests the Auth/tool boundary
  // but is NOT a genuine model call. Replace only this section when the course
  // gateway is supplied, keeping the mandatory tool and verified UID unchanged.
  if (!process.env.FUNCTIONS_EMULATOR && !process.env.FIRESTORE_EMULATOR_HOST) {
    throw new HttpsError('failed-precondition',
      'The course AI model gateway is not configured.');
  }

  const normalized = question.toLowerCase();
  if (normalized.includes('999') || normalized.includes('give me points') ||
      normalized.includes('ignore your rules') || normalized.includes('award points')) {
    return {
      reply: 'I can give a hint, but I cannot change points or award badges. ' +
        'Use the separate Complete challenge button when you are ready.',
      mode: 'emulator-mock',
      tool: 'readMyQuestState',
    };
  }
  if (normalized.includes('simulate-tool-failure')) {
    throw new HttpsError('unavailable', 'Simulated coach tool error.');
  }
  const status = state.completed ? 'You have already finished this quest. ' : '';
  return {
    reply: status + 'For "' + state.title + '", start with this: ' +
      state.prompt.slice(0, 135) + ' Think about the first small step ' +
      'you would take, then check your progress. I cannot complete it for you.',
    mode: 'emulator-mock',
    tool: 'readMyQuestState',
  };
}

module.exports = { readMyQuestState, makeCoach, COACH_INSTRUCTIONS };
