import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String currentVersion = '1.0.3';
  static const int currentVersionCode = 4;
  static const String defaultBackendUrl = 'https://nexon-jyp1.onrender.com';
  static const String githubReleasesUrl = 'https://api.github.com/repos/shivaww/Nexon/releases/latest';

  /// Silent background check on app startup
  static Future<void> checkOnStartup(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheckRaw = prefs.getString('nexon_last_update_check_time');
    final now = DateTime.now();

    if (lastCheckRaw != null) {
      final lastCheck = DateTime.tryParse(lastCheckRaw);
      if (lastCheck != null && now.difference(lastCheck).inHours < 12) {
        // Skip silent check if checked within the last 12 hours
        return;
      }
    }

    await prefs.setString('nexon_last_update_check_time', now.toIso8601String());
    if (context.mounted) {
      await checkForUpdates(context, userInitiated: false);
    }
  }

  /// Check for app updates (backend endpoint + GitHub releases fallback)
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool userInitiated = true,
  }) async {
    if (userInitiated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checking for new app version…'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    String? latestVersion;
    String? downloadUrl;
    String releaseNotes = '';

    // 1. Try Backend Version Endpoint
    try {
      final response = await http
          .get(Uri.parse('$defaultBackendUrl/api/version'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        latestVersion = data['latest_version']?.toString();
        downloadUrl = data['download_url']?.toString();
        releaseNotes = data['release_notes']?.toString() ?? '';
      }
    } catch (_) {}

    // 2. Fallback to GitHub Latest Release if backend is unavailable or not set
    if (latestVersion == null || downloadUrl == null || downloadUrl.isEmpty) {
      try {
        final response = await http
            .get(
              Uri.parse(githubReleasesUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'},
            )
            .timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final tagName = data['tag_name']?.toString() ?? '';
          latestVersion = tagName.replaceAll(RegExp(r'[^0-9.]'), '');
          downloadUrl = data['html_url']?.toString() ?? 'https://github.com/shivaww/Nexon/releases';
          releaseNotes = data['body']?.toString() ?? '';
        }
      } catch (_) {}
    }

    if (!context.mounted) return;

    if (latestVersion != null && _isNewerVersion(latestVersion, currentVersion)) {
      _showUpdateDialog(
        context,
        latestVersion: latestVersion,
        downloadUrl: downloadUrl ?? 'https://github.com/shivaww/Nexon/releases',
        releaseNotes: releaseNotes,
      );
    } else if (userInitiated) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 24),
              SizedBox(width: 8),
              Text(
                'Up to Date',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          content: Text(
            'You are running the latest version of Nexon (v$currentVersion).',
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String latestVersion,
    required String downloadUrl,
    required String releaseNotes,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              color: Color(0xFF2563EB),
              size: 26,
            ),
            SizedBox(width: 10),
            Text(
              'New Version Available!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version (v$latestVersion) of Nexon is available. Please check and download the update.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF334155),
                  height: 1.4,
                ),
              ),
              if (releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Release Notes:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    releaseNotes,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Later',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
            label: const Text(
              'Download Update',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
