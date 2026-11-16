import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // This classwork is intentionally tested against LOCAL Firebase emulators.
  // Release builds need a separately approved production configuration.
  if (kDebugMode) {
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  }

  runApp(const CloudQuestApp());
}

class CloudQuestApp extends StatelessWidget {
  const CloudQuestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud Quest',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Scaffold(body: Center(child: Text('Authentication unavailable.')));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snapshot.data;
          return user == null
              ? const SignInScreen()
              : QuestScreen(key: ValueKey(user.uid), user: user);
        },
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Enter an email and a password of at least 6 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = 'Sign-in failed: ${error.code}');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect to Firebase emulator.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Quest')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(Icons.cloud_outlined, size: 60),
                const SizedBox(height: 12),
                Text(_register ? 'Create a learner account' : 'Sign in',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 18),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? 'Connecting...' : (_register ? 'Sign up' : 'Sign in')),
                ),
                TextButton(
                  onPressed: _loading ? null : () => setState(() {
                    _register = !_register;
                    _error = null;
                  }),
                  child: Text(_register ? 'Already registered? Sign in' : 'New account? Sign up'),
                ),
                const Text('Local Firebase emulator classwork', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QuestScreen extends StatefulWidget {
  const QuestScreen({super.key, required this.user});
  final User user;

  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  final _question = TextEditingController(text: 'Can you give me a hint?');
  String? _hint;
  String? _hintMode;
  String? _message;
  bool _coachLoading = false;
  bool _rewardLoading = false;

  DocumentReference<Map<String, dynamic>> get _challengeRef =>
      FirebaseFirestore.instance.collection('challenges').doc('today');

  DocumentReference<Map<String, dynamic>> get _progressRef =>
      FirebaseFirestore.instance.collection('users').doc(widget.user.uid)
          .collection('progress').doc('today');

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _askCoach() async {
    final question = _question.text.trim();
    if (question.isEmpty || question.length > 300) {
      setState(() => _message = 'Enter a question between 1 and 300 characters.');
      return;
    }
    setState(() {
      _coachLoading = true;
      _hint = null;
      _hintMode = null;
      _message = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('askQuestCoach').call<Map<String, dynamic>>({'question': question});
      if (!mounted) return;
      setState(() {
        _hint = (result.data['reply'] ?? 'No hint received.').toString();
        _hintMode = result.data['mode']?.toString();
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) setState(() => _message = 'Coach unavailable (${error.code}). Try again.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not contact the coach.');
    } finally {
      if (mounted) setState(() => _coachLoading = false);
    }
  }

  Future<void> _complete() async {
    setState(() {
      _rewardLoading = true;
      _message = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('completeToday')
          .call<Map<String, dynamic>>({'challengeId': 'today'});
      if (!mounted) return;
      final already = result.data['alreadyCompleted'] == true;
      setState(() => _message = already
          ? 'Already completed. Your reward is still 10 points and one badge.'
          : 'Quest completed! You earned 10 points and the First Quest badge.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) setState(() => _message = 'Reward unavailable (${error.code}). Retry later.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not complete quest. Try again.');
    } finally {
      if (mounted) setState(() => _rewardLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Quest'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Signed in as ${widget.user.email ?? widget.user.uid}'),
                const SizedBox(height: 12),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _challengeRef.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Text('Challenge read failed. Check Firestore rules and emulators.');
                    if (!snapshot.hasData) return const LinearProgressIndicator();
                    final challenge = snapshot.data!.data();
                    if (challenge == null) {
                      return const Text('No challenge found. Run the local seed command.');
                    }
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(challenge['title']?.toString() ?? 'Today\'s Challenge',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text(challenge['prompt']?.toString() ?? 'No challenge prompt.'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _progressRef.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Text('Progress read failed. Check Firestore rules.');
                    if (!snapshot.hasData) return const LinearProgressIndicator();
                    final progress = snapshot.data!.data();
                    final completed = progress?['completed'] == true;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status: ${completed ? 'Completed' : 'Not completed'}'),
                            Text('Points: ${progress?['points'] ?? 0}'),
                            Text('Badge: ${completed ? 'First Quest' : 'None yet'}'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _rewardLoading ? null : _complete,
                              child: Text(_rewardLoading ? 'Saving...' :
                                  completed ? 'Retry completion (test)' : 'Complete challenge'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text('Quest Coach', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: _question,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Ask for a hint',
                    border: OutlineInputBorder(),
                  ),
                ),
                OutlinedButton(
                  onPressed: _coachLoading ? null : _askCoach,
                  child: Text(_coachLoading ? 'Checking your quest...' : 'Get hint'),
                ),
                if (_hint != null) ...[
                  const SizedBox(height: 10),
                  Text(_hint!, key: const Key('coachHint')),
                  if (_hintMode == 'emulator-mock')
                    const Text('Emulator mock response (not a live AI model).',
                        style: TextStyle(fontSize: 12)),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  Text(_message!, key: const Key('statusMessage')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
