import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/notification_permission_gate.dart';
import '../shared/constants.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'features/language.dart';
import 'features/profile.dart';
import 'home.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.home = const NotificationPermissionGate(child: Home())});

  final Widget home;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _completed = _readCompletion();
  bool _finished = false;

  Future<bool> _readCompletion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_complete') ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_finished) return widget.home;
    return FutureBuilder<bool>(
      future: _completed,
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const Scaffold(
            backgroundColor: spotifyBgColor,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) return widget.home;
        return OnboardingPage(onComplete: () => setState(() => _finished = true));
      },
    );
  }
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _name = TextEditingController();
  final _languages = <String>{};
  bool _selectingLanguages = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish({bool skip = false}) async {
    if (_saving || (!skip && _languages.isEmpty)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedName = _name.text.trim();
      if (savedName.isNotEmpty && !await prefs.setString('username', savedName)) {
        throw StateError('Could not save name');
      }
      if (_languages.isNotEmpty) {
        await savePreferredLanguages(ref.read(languageNotifierProvider), _languages.toList());
      }
      if (!await prefs.setBool('onboarding_complete', true)) throw StateError('Could not save setup');
      if (savedName.isNotEmpty) {
        username = savedName;
        profileRefreshNotifier.value++;
      }
      if (mounted) widget.onComplete();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save your preferences. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_name.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectingLanguages = true);
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectingLanguages ? _languages.isNotEmpty : _name.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: _OnboardingBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset('assets/icons/logo.png', width: 46, height: 46, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hivefy',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                        Text('Your music, your way.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'STEP ',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          TextSpan(
                            text: _selectingLanguages ? '02' : '01',
                            style: const TextStyle(color: spotifyGreen),
                          ),
                          const TextSpan(
                            text: ' / 02',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 58, bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectingLanguages ? 'What do you like to listen to?' : 'What should we call you?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectingLanguages
                              ? 'Select the languages you enjoy listening to.'
                              : 'Enter your name to get started.',
                          style: const TextStyle(color: Colors.white60, fontSize: 16, height: 1.5),
                        ),
                        const SizedBox(height: 28),
                        if (_selectingLanguages)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final language in availableLanguages)
                                ChoiceChip(
                                  label: Text(capitalize(language)),
                                  selected: _languages.contains(language),
                                  onSelected: _saving
                                      ? null
                                      : (selected) => setState(() {
                                          if (selected) {
                                            _languages.add(language);
                                          } else {
                                            _languages.remove(language);
                                          }
                                        }),
                                  selectedColor: const Color(0xFF242424),
                                  backgroundColor: const Color(0xFF242424),
                                  labelStyle: TextStyle(
                                    color: _languages.contains(language) ? spotifyGreen : Colors.white,
                                  ),
                                  showCheckmark: false,
                                  side: BorderSide(
                                    color: _languages.contains(language) ? spotifyGreen : Colors.white24,
                                  ),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'YOUR NAME',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _name,
                                maxLength: 20,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(color: Colors.white, fontSize: 20),
                                decoration: const InputDecoration(
                                  hintText: 'Enter your name',
                                  hintStyle: TextStyle(color: Colors.white38),
                                  counterStyle: TextStyle(color: Colors.white54),
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: spotifyGreen)),
                                ),
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _next(),
                                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                              ),
                              const Text(
                                'You can change this later in your profile.',
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : () => _finish(skip: true),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: const Text('Skip'),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF087C39),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1D4931),
                    disabledForegroundColor: Colors.white54,
                    minimumSize: const Size.fromHeight(54),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _saving || !canContinue
                      ? null
                      : _selectingLanguages
                      ? () => _finish()
                      : _next,
                  child: Text(
                    _saving
                        ? 'Saving...'
                        : _selectingLanguages
                        ? 'Start listening'
                        : 'Continue',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingBackground extends StatefulWidget {
  const _OnboardingBackground({required this.child});

  final Widget child;

  @override
  State<_OnboardingBackground> createState() => _OnboardingBackgroundState();
}

class _OnboardingBackgroundState extends State<_OnboardingBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _motion,
      child: widget.child,
      builder: (context, child) {
        final movement = reduceMotion ? 0.0 : Curves.easeInOut.transform(_motion.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF142920), Color(0xFF0E1713), Color(0xFF0A0D0B)],
                  stops: [0, 0.48, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(1.25 - 0.5 * movement, -0.8 + 0.35 * movement),
                  radius: 1.05,
                  colors: [Color(0x99459669), Color(0x44306649), Color(0x00225C3B)],
                  stops: [0, 0.42, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-1.3 + 0.35 * movement, 0.55 - 0.3 * movement),
                  radius: 1.0,
                  colors: [Color(0x5540855E), Color(0x1E245A3B), Color(0x00245A3B)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0x00000000), Color(0x99000000)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            child!,
          ],
        );
      },
    );
  }
}
