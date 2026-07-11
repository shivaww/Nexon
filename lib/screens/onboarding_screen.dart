import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import '../services/drive_sync_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({Key? key, required this.onComplete})
    : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _backupEnabled = true;
  bool _isSigningIn = false;

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding_v2', true);
    await prefs.setBool('google_drive_backup_enabled', _backupEnabled);
    widget.onComplete();
  }

  late final StreamSubscription<AuthState> _authStateSubscription;

  @override
  void initState() {
    super.initState();
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((data) async {
          final session = data.session;
          if (session != null && _isSigningIn) {
            // Persist the Google provider token immediately — it's only
            // available right after sign-in and disappears on session refresh.
            await DriveSyncService.persistProviderToken();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Checking for existing backup on Google Drive...',
                  ),
                ),
              );
            }
            await DriveSyncService.restoreFromDriveDetailed();
            if (mounted) {
              setState(() => _isSigningIn = false);
              _nextPage();
            }
          }
        });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isSigningIn = true);

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && session.providerToken != null) {
      // Persist immediately before it's lost
      await DriveSyncService.persistProviderToken();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checking for existing backup on Google Drive...'),
          ),
        );
      }
      await DriveSyncService.restoreFromDriveDetailed();
      if (mounted) {
        setState(() => _isSigningIn = false);
        _nextPage();
      }
      return;
    }

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.nexon://login-callback',
        scopes:
            'https://www.googleapis.com/auth/drive.appdata https://www.googleapis.com/auth/drive.file',
        queryParams: const {
          'access_type': 'offline',
          'prompt': 'consent',
          'include_granted_scopes': 'true',
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSigningIn = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF2),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _buildTermsAndConditions(),
                  _buildGoogleSignIn(),
                  _buildBackupPermission(),
                  _buildTermuxSetup(),
                ],
              ),
            ),
            _buildProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsAndConditions() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome to Nexon',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7B4E2E),
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Before we begin, please review our core architectural principles:',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF2D241C),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: const [
                ListTile(
                  leading: Icon(Icons.security, color: Color(0xFF7B4E2E)),
                  title: Text(
                    'Absolute Privacy via Google Drive',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'We do not store your chats on central servers. All your conversations, API keys, and memory are stored entirely on your local device and securely backed up to your personal Google Drive.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.terminal, color: Color(0xFF7B4E2E)),
                  title: Text(
                    'Local Agentic Execution',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Nexon requires Termux to run Python scripts and execute shell commands locally. This gives the AI the ability to act as a fully autonomous agent on your device without sending data externally.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.storage, color: Color(0xFF7B4E2E)),
                  title: Text(
                    'Data Ownership',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Because everything lives in your Google Drive and Termux environment, you own 100% of your data. We cannot read your chats or access your files.',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B4E2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'I Agree & Proceed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleSignIn() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_sync, size: 80, color: Color(0xFF7B4E2E)),
          const SizedBox(height: 32),
          const Text(
            'Secure Cloud Sync',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7B4E2E),
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sign in with Google to securely authenticate and link your Google Drive for zero-cost, private cloud backups.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF2D241C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          _isSigningIn
              ? const CircularProgressIndicator(color: Color(0xFF7B4E2E))
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _signInWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text(
                      'Sign in with Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B4E2E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildBackupPermission() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enable Drive Backups',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7B4E2E),
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'WARNING: If you do not enable backups, you WILL lose all your chats, API keys, AI memory, artifacts, and SVGs if you uninstall the app or lose your device.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.red,
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            title: const Text(
              'Enable Auto-Sync to Google Drive',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF7B4E2E),
              ),
            ),
            subtitle: const Text('You can change this later in settings.'),
            value: _backupEnabled,
            activeColor: const Color(0xFF7B4E2E),
            onChanged: (val) => setState(() => _backupEnabled = val),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B4E2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermuxSetup() {
    const setupCommand =
        'curl -O https://raw.githubusercontent.com/shivaww/Nexon/main/python_bridge/termux_forge_bridge.py && python termux_forge_bridge.py';
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agentic Termux Setup',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF7B4E2E),
              fontFamily: 'serif',
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'To give the AI file access and terminal capabilities, you must install and run the Python bridge inside Termux.',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF2D241C),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    setupCommand,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white),
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: setupCommand));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard!')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '1. Open Termux\n2. Paste and run the command above\n3. Return to this app',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF2D241C),
              fontWeight: FontWeight.bold,
              height: 1.5,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _nextPage, // Calls _finishOnboarding
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B4E2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Finish Setup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 8,
            width: _currentPage == index ? 24 : 8,
            decoration: BoxDecoration(
              color: _currentPage == index
                  ? const Color(0xFF7B4E2E)
                  : Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
