// Extracted from main.dart lines 13358-17173
// Extracted on: 2026-08-26T18:20:45.708136

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexon/widgets/glass_widgets.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';
import 'package:nexon/main.dart';
import 'package:nexon/services/voice/live_voice_engine.dart';
import 'package:nexon/widgets/live_voice_overlay.dart';

class MediaAndModelSheet extends StatefulWidget {
  const MediaAndModelSheet({
    super.key,
    required this.sessions,
    required this.onRestoreCompleted,
    required this.provider,
    required this.customProviders,
    required this.allSettings,
    required this.modelCache,
    required this.settings,
    required this.cachedModels,
    required this.searchSettings,
    required this.agenticEnabled,
    required this.artifactsEnabled,
    required this.svgVisualsEnabled,
    required this.deepResearchEnabled,
    required this.studyModeEnabled,
    required this.userName,
    required this.writerContextBudget,
    required this.agenticWorkspace,
    required this.customMcpUrl,
    required this.onSearchSettingsChanged,
    required this.onAgenticEnabledChanged,
    required this.onArtifactsEnabledChanged,
    required this.onSvgVisualsEnabledChanged,
    required this.onDeepResearchEnabledChanged,
    required this.onStudyModeEnabledChanged,
    required this.onUserNameChanged,
    required this.onWriterContextBudgetChanged,
    required this.onAgenticWorkspaceChanged,
    required this.onCustomMcpUrlChanged,
    required this.onImageAttached,
    required this.onFileAttached,

    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onMaxTokensChanged,
    required this.onReasoningEnabledChanged,
    required this.onFetchModels,
    required this.onConfigureKey,
    required this.onDeleteCustomProvider,
    required this.sessionId,
  });

  final ProviderDefinition provider;
  final List<ProviderDefinition> customProviders;
  final Map<String, ProviderSettings> allSettings;
  final Map<String, List<String>> modelCache;
  final ProviderSettings settings;
  final List<String> cachedModels;
  final SearchSettings searchSettings;
  final bool agenticEnabled;
  final bool artifactsEnabled;
  final bool svgVisualsEnabled;
  final bool deepResearchEnabled;
  final bool studyModeEnabled;
  final String userName;
  final int writerContextBudget;
  final String agenticWorkspace;
  final String customMcpUrl;
  final List<ChatSession> sessions;
  final Future<void> Function() onRestoreCompleted;
  final ValueChanged<SearchSettings> onSearchSettingsChanged;
  final ValueChanged<bool> onAgenticEnabledChanged;
  final ValueChanged<bool> onArtifactsEnabledChanged;
  final ValueChanged<bool> onSvgVisualsEnabledChanged;
  final ValueChanged<bool> onDeepResearchEnabledChanged;
  final ValueChanged<int> onWriterContextBudgetChanged;
  final ValueChanged<bool> onStudyModeEnabledChanged;
  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<String> onAgenticWorkspaceChanged;
  final ValueChanged<String> onCustomMcpUrlChanged;
  final ValueChanged<String> onImageAttached;
  final ValueChanged<AttachedFile> onFileAttached;

  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<int> onMaxTokensChanged;
  final ValueChanged<bool> onReasoningEnabledChanged;
  final Future<List<String>> Function() onFetchModels;
  final ValueChanged<String> onConfigureKey;
  final ValueChanged<String> onDeleteCustomProvider;
  final String sessionId;

  @override
  State<MediaAndModelSheet> createState() => _MediaAndModelSheetState();
}

class _MediaAndModelSheetState extends State<MediaAndModelSheet> {
  List<ProviderDefinition> get _allProviders => [
        ...providerCatalog,
        ...widget.customProviders,
      ];

  late List<ProviderDefinition> _customLocal;

  bool get _isCustomSel =>
      _selectedProviderId == 'custom' ||
      _selectedProviderId.startsWith('custom_');

  late bool _studyModeEnabled;

  Future<void> _saveStudyMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('study_mode_enabled_v1', val);
  }
  int _activeTab = 0;
  bool _isFetchingModels = false;
  bool _managedSubscriptionEnabled = false;
  late int _maxTokens;
  var _fetching = false;
  late String _selectedProviderId;
  late String _selectedModel;
  late bool _reasoningEnabled;
  late bool _searchEnabled;
  late bool _agenticEnabled;
  late bool _artifactsEnabled;
  late bool _svgVisualsEnabled;
  late bool _deepResearchEnabled;
  late int _writerContextBudget;
  late TextEditingController _writerContextBudgetController;
  late TextEditingController _userNameController;
  late String _searchProvider;
  late final TextEditingController _searchKeyController;
  late final TextEditingController _searchCxController;
  late final TextEditingController _agenticWorkspaceController;
  late final TextEditingController _customMcpUrlController;
  bool _driveBackupEnabled = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String _syncProgressStatus = '';
  String _backupResultMessage = '';
  bool _backupResultSuccess = false;
  String _activePlanTier = '';
  int? _liveDailyPool;
  int? _liveSubscriptionCredits;
  int? _liveTopupCredits;
  Timer? _walletSyncTimer;
  String? _selectedVoiceName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.checkOnStartup(context);
      }
    });
    _maxTokens = widget.settings.maxTokens;
    _customLocal = List.of(widget.customProviders);
    _selectedProviderId = widget.provider.id;
    _selectedModel = widget.settings.model.isNotEmpty
        ? widget.settings.model
        : widget.provider.models.first;
    _reasoningEnabled = widget.settings.reasoningEnabled;
    _searchEnabled = widget.searchSettings.enabled;
    _agenticEnabled = widget.agenticEnabled;
    _artifactsEnabled = widget.artifactsEnabled;
    _svgVisualsEnabled = widget.svgVisualsEnabled;
    _deepResearchEnabled = widget.deepResearchEnabled;
    _studyModeEnabled = widget.studyModeEnabled;
    _writerContextBudget = widget.writerContextBudget;
    _userNameController = TextEditingController(text: widget.userName);
    _writerContextBudgetController = TextEditingController(
      text: widget.writerContextBudget.toString(),
    );
    _searchProvider = widget.searchSettings.provider;
    final initialKeys = [
      widget.searchSettings.apiKey,
      ...widget.searchSettings.fallbackApiKeys,
    ].where((k) => k.isNotEmpty).join(', ');
    _searchKeyController = TextEditingController(text: initialKeys);
    _searchCxController = TextEditingController(
      text: widget.searchSettings.googleCx,
    );
    _agenticWorkspaceController = TextEditingController(
      text: widget.agenticWorkspace,
    );
    _customMcpUrlController = TextEditingController(text: widget.customMcpUrl);

    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _driveBackupEnabled =
              prefs.getBool('google_drive_backup_enabled') ?? false;
          _managedSubscriptionEnabled =
              prefs.getBool('nexon_managed_subscription_enabled') ?? false;
          _activePlanTier = prefs.getString('nexon_managed_plan_tier') ?? '';
        });
      }
    });
    _liveDailyPool = ChatClient.liveDailyPool.value;
    _liveSubscriptionCredits = ChatClient.liveSubscriptionCredits.value;
    _liveTopupCredits = ChatClient.liveTopupCredits.value;
    ChatClient.liveDailyPool.addListener(_onWalletChanged);
    ChatClient.liveSubscriptionCredits.addListener(_onWalletChanged);
    ChatClient.liveTopupCredits.addListener(_onWalletChanged);

    _fetchLiveWallet();
    _walletSyncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _fetchLiveWallet(),
    );
  }

  @override
  void didUpdateWidget(covariant MediaAndModelSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final providerChanged = oldWidget.provider.id != widget.provider.id;
    final modelChanged = oldWidget.settings.model != widget.settings.model;
    if (providerChanged ||
        modelChanged ||
        oldWidget.settings.maxTokens != widget.settings.maxTokens ||
        oldWidget.settings.reasoningEnabled !=
            widget.settings.reasoningEnabled ||
        oldWidget.searchSettings.enabled != widget.searchSettings.enabled ||
        oldWidget.agenticEnabled != widget.agenticEnabled ||
        oldWidget.deepResearchEnabled != widget.deepResearchEnabled ||
        oldWidget.studyModeEnabled != widget.studyModeEnabled ||
        oldWidget.searchSettings.provider != widget.searchSettings.provider) {
      setState(() {
        _selectedProviderId = widget.provider.id;
        // When provider changes, reset to that provider's default model.
        // When only model changes (e.g. session switch), honour the new value.
        if (providerChanged) {
          _selectedModel = widget.settings.model.isNotEmpty
              ? widget.settings.model
              : widget.provider.models.first;
        } else if (modelChanged) {
          _selectedModel = widget.settings.model.isNotEmpty
              ? widget.settings.model
              : _selectedModel;
        }
        _maxTokens = widget.settings.maxTokens;
        _reasoningEnabled = widget.settings.reasoningEnabled;
        _searchEnabled = widget.searchSettings.enabled;
        _agenticEnabled = widget.agenticEnabled;
        _artifactsEnabled = widget.artifactsEnabled;
        _svgVisualsEnabled = widget.svgVisualsEnabled;
        _deepResearchEnabled = widget.deepResearchEnabled;
        _studyModeEnabled = widget.studyModeEnabled;
        _writerContextBudget = widget.writerContextBudget;
        _searchProvider = widget.searchSettings.provider;
      });
    }
  }

  void _showExclusivitySnackBar(String feature, String conflict) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature cannot be enabled while $conflict is active.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<Map<String, dynamic>> _checkBridgeAlive() async {
    final endpoint = widget.customMcpUrl.isNotEmpty
        ? widget.customMcpUrl
        : 'http://127.0.0.1:8390/mcp';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 3));
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode({'method': 'ping', 'params': {}}));
      request.headers.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic> && decoded['result'] is Map) {
          final result = decoded['result'] as Map;
          if (result['ok'] == true) return {'ok': true};
        }
      }
      return {'ok': false, 'reason': 'bridge_error'};
    } catch (_) {
      return {'ok': false, 'reason': 'bridge_unreachable'};
    } finally {
      client.close(force: true);
    }
  }

  void _showDeepResearchSetupDialog({required String reason}) {
    final isUnreachable = reason == 'bridge_unreachable';
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            bool rechecking = false;
            return AlertDialog(
              title: Text(
                isUnreachable
                    ? 'Bridge Not Running'
                    : 'Deep Research Setup Required',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUnreachable
                        ? "The Python bridge process isn't currently running. Please start it in Termux:"
                        : 'Deep Research requires the Python bridge. Please run this setup command in Termux:',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black87,
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            isUnreachable
                                ? 'cd ~/nexon_bridge && python3 mcp_server.py'
                                : 'curl -sL https://raw.githubusercontent.com/shivaww/Nexon/main/install_bridge.sh | bash',
                            style: const TextStyle(
                              color: Colors.green,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: isUnreachable
                                    ? 'cd ~/nexon_bridge && python3 mcp_server.py'
                                    : 'curl -sL https://raw.githubusercontent.com/shivaww/Nexon/main/install_bridge.sh | bash',
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
                StatefulBuilder(
                  builder: (ctx2, setRecheckState) {
                    return TextButton(
                      onPressed: rechecking
                          ? null
                          : () async {
                              setRecheckState(() => rechecking = true);
                              final result = await _checkBridgeAlive();
                              if (!mounted) return;
                              if (result['ok'] == true) {
                                Navigator.of(ctx).pop();
                                setState(() => _deepResearchEnabled = true);
                                widget.onDeepResearchEnabledChanged(true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bridge is running! Deep Research enabled.',
                                    ),
                                  ),
                                );
                              } else {
                                setRecheckState(() => rechecking = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bridge still not reachable. Please check it is running.',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: rechecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Recheck'),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _getTotalDailyCap(String planTier) {
    switch (planTier.toUpperCase()) {
      case 'GO':
        return 550000;
      case 'PLUS':
        return 1100000;
      case 'PRO':
        return 2000000;
      case 'MAX':
        return 3100000;
      default:
        return 100000; // Free tier
    }
  }

  int _getTotalMonthlyCap(String planTier) {
    switch (planTier.toUpperCase()) {
      case 'GO':
        return 16500000;
      case 'PLUS':
        return 33500000;
      case 'PRO':
        return 61000000;
      case 'MAX':
        return 95000000;
      default:
        return 0;
    }
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  void _onWalletChanged() {
    if (mounted) {
      setState(() {
        _liveDailyPool = ChatClient.liveDailyPool.value;
        _liveSubscriptionCredits = ChatClient.liveSubscriptionCredits.value;
        _liveTopupCredits = ChatClient.liveTopupCredits.value;
      });
    }
  }

  Future<void> _fetchLiveWallet() async {
    await ChatClient.fetchLiveWallet();
  }

  @override
  void dispose() {
    ChatClient.liveDailyPool.removeListener(_onWalletChanged);
    ChatClient.liveSubscriptionCredits.removeListener(_onWalletChanged);
    ChatClient.liveTopupCredits.removeListener(_onWalletChanged);
    _walletSyncTimer?.cancel();
    _userNameController.dispose();
    _searchKeyController.dispose();
    _searchCxController.dispose();
    _agenticWorkspaceController.dispose();
    _customMcpUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _fetching = true);
    try {
      final models = await widget.onFetchModels();
      if (mounted) {
        setState(() {
          // Keep the current selection if it exists in the new list.
          // Only fall back to first model if current selection is absent.
          if (models.isNotEmpty && !models.contains(_selectedModel)) {
            _selectedModel = models.first;
            widget.onModelChanged(_selectedModel);
          }
          // Re-evaluate vision capability after fresh model list is loaded
          // (modelsWithVision is populated during fetchModels)
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model fetch failed: $error')));
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFFFFBF2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Attach Image',
            style: TextStyle(
              color: Color(0xFF7B4E2E),
              fontWeight: FontWeight.bold,
              fontFamily: 'serif',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF2D241C)),
                title: const Text(
                  'Take a Photo',
                  style: TextStyle(color: Color(0xFF2D241C)),
                ),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Color(0xFF2D241C),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Color(0xFF2D241C)),
                ),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (status.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Camera permission denied')),
            );
          }
          return;
        }
      }

      if (source == ImageSource.gallery) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.single.path != null) {
          final file = File(result.files.single.path!);
          final bytes = await file.readAsBytes();
          final base64String = base64Encode(bytes);
          widget.onImageAttached(base64String);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image attached successfully')),
            );
          }
        }
      } else {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: source);
        if (pickedFile != null) {
          final bytes = await pickedFile.readAsBytes();
          final base64String = base64Encode(bytes);
          widget.onImageAttached(base64String);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image attached successfully')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('camera_access_denied') ||
            errorStr.contains('permission') ||
            errorStr.contains('denied')) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFFFFFBF2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Permission Denied',
                style: TextStyle(
                  color: Color(0xFF7B4E2E),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'serif',
                ),
              ),
              content: const Text(
                'Camera or Gallery permission was denied. If you selected "Don\'t ask again", you will need to enable this permission manually in the app settings to use this feature.',
                style: TextStyle(color: Color(0xFF2D241C), height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF7B4E2E)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    openAppSettings();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B4E2E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
        }
      }
    }
  }

  Future<void> _pickFile() async {
    const maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB (normal mode)
    const maxContentChars = 50000; // 50K chars

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf', 'txt', 'md', 'json', 'py', 'dart', 'js', 'html',
          'css', 'yaml', 'yml', 'csv', 'docx', 'doc', 'rtf', 'odt',
          'pptx', 'ppt', 'xlsx', 'xls', 'epub', 'htm', 'xml',
          'log', 'tex',
        ],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Validate files and filter by size limits
      final validFiles = <PlatformFile>[];
      for (final pickedFile in result.files) {
        if (pickedFile.path == null) continue;
        final file = File(pickedFile.path!);
        final stat = await file.stat();

        if (_studyModeEnabled) {
          if (stat.size > 150 * 1024 * 1024) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${pickedFile.name} too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB). Max: 150 MB.')),
              );
            }
            continue;
          }
        } else {
          if (stat.size > maxFileSizeBytes) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${pickedFile.name} too large (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB). Max: 5 MB for normal mode. Use Study Mode for up to 150MB.',
                  ),
                ),
              );
            }
            continue;
          }
        }
        validFiles.add(pickedFile);
      }

      if (validFiles.isEmpty) return;

      if (_studyModeEnabled) {
        // ── Study mode: batch stream-upload to Termux workspace ──
        final totalFiles = validFiles.length;
        final progressNotifier = ValueNotifier<double?>(0.0);
        final statusNotifier = ValueNotifier<String>('Preparing upload…');
        final fileNotifier = ValueNotifier<String>('');
        bool dialogShown = false;

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Uploading to Workspace'),
              content: ValueListenableBuilder<String>(
                valueListenable: statusNotifier,
                builder: (ctx, status, _) {
                  return ValueListenableBuilder<double?>(
                    valueListenable: progressNotifier,
                    builder: (ctx, value, _) {
                      return ValueListenableBuilder<String>(
                        valueListenable: fileNotifier,
                        builder: (ctx, fileName, _) {
                          final percent = value != null ? (value * 100).round() : 0;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LinearProgressIndicator(
                                value: (value != null && value > 0) ? value : null,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7B4E2E)),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                status,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              if (fileName.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  fileName,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                (value != null && value > 0) ? '$percent%' : '',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          );
          dialogShown = true;
        }

        try {
          int uploadedCount = 0;
          final httpClient = HttpClient();

          for (final pickedFile in validFiles) {
            final path = pickedFile.path!;
            final file = File(path);
            final fileName = pickedFile.name;
            final fileSize = await file.length();

            fileNotifier.value = fileName;
            statusNotifier.value = 'Uploading ${uploadedCount + 1}/$totalFiles';
            progressNotifier.value = 0.0;

            final uploadUri = Uri.parse('http://127.0.0.1:8390/workspace/upload?ingest=false&session=${widget.sessionId}');
            final httpReq = await httpClient.postUrl(uploadUri);

            final boundary = '----NexonUpload${DateTime.now().millisecondsSinceEpoch}';
            httpReq.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');

            final header = '--$boundary\r\n'
                'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
                'Content-Type: application/octet-stream\r\n\r\n';
            httpReq.add(utf8.encode(header));

            int bytesUploaded = 0;
            final stream = file.openRead();
            await for (final chunk in stream) {
              httpReq.add(chunk);
              bytesUploaded += chunk.length;
              final fileProgress = bytesUploaded / fileSize;
              progressNotifier.value = (uploadedCount + fileProgress) / totalFiles;
            }

            httpReq.add(utf8.encode('\r\n--$boundary--\r\n'));
            final httpResp = await httpReq.close();
            final respBody = await httpResp.transform(utf8.decoder).join();

            if (httpResp.statusCode != 200) {
              throw Exception('Upload failed for $fileName (${httpResp.statusCode}): $respBody');
            }

            final respJson = jsonDecode(respBody) as Map<String, dynamic>;
            final workspacePath = respJson['workspace_path'] as String? ?? '';

            widget.onFileAttached(
              AttachedFile(
                name: fileName,
                content: '[Workspace file — use <mcp_request> to query]',
                workspacePath: workspacePath,
              ),
            );
            uploadedCount++;
          }

          httpClient.close();

          // ── Chunking / Indexing phase ──
          fileNotifier.value = '';
          statusNotifier.value = 'Indexing & chunking documents…';
          progressNotifier.value = null; // Indeterminate spinner during indexing

          final reindexUri = Uri.parse('http://127.0.0.1:8390/workspace/reindex');
          final reindexClient = HttpClient()
            ..connectionTimeout = const Duration(seconds: 5);
          final reindexReq = await reindexClient.postUrl(reindexUri);
          reindexReq.headers.set('Content-Type', 'application/json');
          final reindexResp = await reindexReq
              .close()
              .timeout(const Duration(minutes: 5));
          final reindexBody = await reindexResp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 30));
          reindexClient.close();

          if (reindexResp.statusCode != 200) {
            throw Exception('Reindex failed (${reindexResp.statusCode}): $reindexBody');
          }

          final reindexJson = jsonDecode(reindexBody) as Map<String, dynamic>;
          final summary = reindexJson['index_summary'] as Map<String, dynamic>? ?? {};
          final totalChunks = summary['total_chunks'] ?? 0;

          progressNotifier.value = 1.0;
          statusNotifier.value = 'Done! $totalChunks chunks indexed.';

          await Future.delayed(const Duration(milliseconds: 800));

          if (mounted && dialogShown) {
            Navigator.of(context, rootNavigator: true).pop();
            dialogShown = false;
          }

          if (mounted) {
            final failedCount = (summary['failed_files'] as List?)?.length ?? 0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(
                failedCount > 0
                    ? '$uploadedCount file(s) uploaded, $totalChunks chunks indexed. $failedCount file(s) failed to process.'
                    : '$uploadedCount file(s) uploaded & indexed ($totalChunks chunks)',
              )),
            );
          }
        } catch (e) {
          if (mounted && dialogShown) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Workspace upload failed: $e')),
            );
          }
        }
      } else {
        // ── Normal mode: read files into memory for inline attachment ──
        for (final pickedFile in validFiles) {
          final file = File(pickedFile.path!);
          final ext = pickedFile.extension?.toLowerCase();
          String text = '';

          if (ext == 'pdf') {
            final bytes = await file.readAsBytes();
            final PdfDocument document = PdfDocument(inputBytes: bytes);
            try {
              text = PdfTextExtractor(document).extractText();
            } finally {
              document.dispose();
            }
          } else {
            text = await file.readAsString();
          }

          if (text.length > maxContentChars) {
            text =
                '${text.substring(0, maxContentChars)}\n\n[Content truncated — file exceeds size limit for full analysis]';
          }

          widget.onFileAttached(
            AttachedFile(name: pickedFile.name, content: text),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${pickedFile.name} attached')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to read document: $e')));
      }
    }
  }

  void _updateSearchSettings() {
    final rawKeyString = _searchKeyController.text.trim();
    final keys = rawKeyString
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    widget.onSearchSettingsChanged(
      SearchSettings(
        enabled: _searchEnabled,
        provider: _searchProvider,
        apiKey: keys.isNotEmpty ? keys.first : '',
        fallbackApiKeys: keys.length > 1 ? keys.sublist(1) : const [],
        googleCx: _searchCxController.text.trim(),
        customProviders: _searchSettings.customProviders,
      ),
    );
  }

  void _showCustomSearchProviderDialog() {
    final nameCtrl = TextEditingController();
    final endpointCtrl = TextEditingController();
    final keyHeaderCtrl = TextEditingController(text: 'Authorization');
    final keyPrefixCtrl = TextEditingController(text: 'Bearer ');
    final queryParamCtrl = TextEditingController(text: 'query');
    final resultsPathCtrl = TextEditingController(text: 'results');
    final titleCtrl = TextEditingController(text: 'title');
    final urlCtrl = TextEditingController(text: 'url');
    final snippetCtrl = TextEditingController(text: 'content');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Custom Search Provider', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: endpointCtrl, decoration: const InputDecoration(labelText: 'API Endpoint URL', border: OutlineInputBorder(), isDense: true, hintText: 'https://api.example.com/search')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: 'POST',
                  decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder(), isDense: true),
                  items: ['POST', 'GET'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) {},
                ),
                const SizedBox(height: 8),
                TextField(controller: keyHeaderCtrl, decoration: const InputDecoration(labelText: 'API Key Header', border: OutlineInputBorder(), isDense: true, hintText: 'Authorization')),
                const SizedBox(height: 8),
                TextField(controller: keyPrefixCtrl, decoration: const InputDecoration(labelText: 'API Key Prefix', border: OutlineInputBorder(), isDense: true, hintText: 'Bearer ')),
                const SizedBox(height: 8),
                TextField(controller: queryParamCtrl, decoration: const InputDecoration(labelText: 'Query Parameter', border: OutlineInputBorder(), isDense: true, hintText: 'query')),
                const SizedBox(height: 8),
                TextField(controller: resultsPathCtrl, decoration: const InputDecoration(labelText: 'Results JSON Path', border: OutlineInputBorder(), isDense: true, hintText: 'results')),
                const SizedBox(height: 8),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title Field', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'URL Field', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: snippetCtrl, decoration: const InputDecoration(labelText: 'Snippet Field', border: OutlineInputBorder(), isDense: true)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || endpointCtrl.text.trim().isEmpty) return;
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              final cp = CustomSearchProvider(
                id: id,
                name: nameCtrl.text.trim(),
                endpoint: endpointCtrl.text.trim(),
                apiKeyHeader: keyHeaderCtrl.text.trim(),
                apiKeyPrefix: keyPrefixCtrl.text.trim(),
                queryParam: queryParamCtrl.text.trim(),
                resultsPath: resultsPathCtrl.text.trim(),
                titleField: titleCtrl.text.trim(),
                urlField: urlCtrl.text.trim(),
                snippetField: snippetCtrl.text.trim(),
              );
              setState(() {
                _searchSettings = _searchSettings.copyWith(
                  customProviders: [..._searchSettings.customProviders, cp],
                );
                _updateSearchSettings();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAccountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF6C5946)),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _buildAccountTab(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final active = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7B4E2E) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: active ? Colors.white : const Color(0xFF6C5946),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active ? Colors.white : const Color(0xFF6C5946),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentProvider = _allProviders.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => providerCatalog.first,
    );
    final selectedCache = widget.modelCache[_selectedProviderId];
    final models = (selectedCache != null && selectedCache.isNotEmpty)
        ? selectedCache
        : (_selectedProviderId == widget.provider.id &&
                  widget.cachedModels.isNotEmpty
              ? widget.cachedModels
              : currentProvider.models);
    final visionEnabled = modelHasVision(_selectedModel);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      child: WarmGlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        backgroundColor: const Color(0xFFFFFBF2).withValues(alpha: 0.88),
        sigma: 10.0,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle at top
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCCBB8),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header Row
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Input & Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2D241C),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Account & Sync',
                  icon: const Icon(
                    Icons.account_circle_outlined,
                    color: Color(0xFF7B4E2E),
                    size: 22,
                  ),
                  onPressed: _showAccountDialog,
                ),
              ],
            ),

            // Custom Tab Bar Selector (Liquid Glass style)
            LiquidGlassSurface(
              margin: const EdgeInsets.symmetric(vertical: 14),
              padding: const EdgeInsets.all(4),
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  _buildTabButton(0, Icons.smart_toy_outlined, 'Model'),
                  _buildTabButton(1, Icons.explore_outlined, 'Features'),
                  _buildTabButton(2, Icons.attachment_outlined, 'Attach'),
                ],
              ),
            ),
            const Divider(color: Color(0xFFE7D8C4), height: 1),
            const SizedBox(height: 14),

            // Scrollable Content Pane
            Expanded(
              child: SingleChildScrollView(
                child: _buildActiveTabContent(models, visionEnabled),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(List<String> models, bool visionEnabled) {
    switch (_activeTab) {
      case 0:
        return _buildModelTab(models);
      case 1:
        return _buildCapabilitiesTab();
      case 2:
        return _buildAttachTab(visionEnabled);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomProvidersCard() {
    return LiquidGlassSurface(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.dns_outlined,
                size: 18,
                color: Color(0xFF7B4E2E),
              ),
              const SizedBox(width: 8),
              const Text(
                'Saved providers',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onConfigureKey('custom');
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add provider'),
              ),
            ],
          ),
          if (_customLocal.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No saved providers yet. Tap "Add provider" to create one.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
              ),
            ),
          for (final p in _customLocal)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedProviderId == p.id
                      ? const Color(0xFF7B4E2E)
                      : const Color(0xFFDCCBB8),
                ),
              ),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Radio<String>(
                  value: p.id,
                  groupValue: _selectedProviderId,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedProviderId = val;
                      final saved = widget.allSettings[val];
                      _selectedModel =
                          (saved != null && saved.model.trim().isNotEmpty)
                          ? saved.model.trim()
                          : (p.models.isNotEmpty ? p.models.first : '');
                    });
                    widget.onProviderChanged(val);
                  },
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  p.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfigureKey(p.id);
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Color(0xFFB3261E),
                      ),
                      onPressed: () {
                        setState(() {
                          _customLocal = [
                            for (final x in _customLocal)
                              if (x.id != p.id) x,
                          ];
                          if (_selectedProviderId == p.id) {
                            _selectedProviderId = 'custom';
                            widget.onProviderChanged('custom');
                          }
                        });
                        widget.onDeleteCustomProvider(p.id);
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelTab(List<String> models) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdowns Group Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _isCustomSel ? 'custom' : _selectedProviderId,
                      dropdownColor: const Color(0xFFFFFBF2),
                      decoration: const InputDecoration(
                        labelText: 'AI Provider',
                        labelStyle: TextStyle(
                          color: Color(0xFF6C5946),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                        ),
                        prefixIcon: Icon(
                          Icons.hub_outlined,
                          color: Color(0xFF7B4E2E),
                          size: 20,
                        ),
                      ),
                      items: providerCatalog.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          final nextProvider = providerCatalog.firstWhere(
                            (p) => p.id == val,
                            orElse: () => providerCatalog.first,
                          );
                          if (nextProvider.isKaggle) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const KaggleSetupScreen(),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _selectedProviderId = val as String;
                            _selectedModel = nextProvider.models.isNotEmpty
                                ? nextProvider.models.first
                                : '';
                          });
                          widget.onProviderChanged(val as String);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCCBB8)),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfigureKey(_selectedProviderId);
                      },
                      child: const Icon(
                        Icons.key,
                        color: Color(0xFF7B4E2E),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isCustomSel) ...[
                const SizedBox(height: 12),
                _buildCustomProvidersCard(),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: models.contains(_selectedModel)
                          ? _selectedModel
                          : (models.isNotEmpty ? models.first : null),
                      dropdownColor: const Color(0xFFFFFBF2),
                      decoration: const InputDecoration(
                        labelText: 'Model Name',
                        labelStyle: TextStyle(
                          color: Color(0xFF6C5946),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFDCCBB8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF7B4E2E)),
                        ),
                        prefixIcon: Icon(
                          Icons.memory_outlined,
                          color: Color(0xFF7B4E2E),
                          size: 20,
                        ),
                      ),
                      items: models.map((m) {
                        return DropdownMenuItem<String>(
                          value: m,
                          child: Text(
                            m,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedModel = val as String);
                          widget.onModelChanged(val as String);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCCBB8)),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.white,
                      ),
                      onPressed: _fetching ? null : _fetch,
                      child: _fetching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7B4E2E),
                              ),
                            )
                          : const Icon(
                              Icons.sync,
                              color: Color(0xFF7B4E2E),
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Token Slider Section
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Output Tokens',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_maxTokens tokens',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () async {
                          final controller = TextEditingController(
                            text: _maxTokens.toString(),
                          );
                          final customVal = await showDialog<int>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFFFFFBF2),
                              title: const Text(
                                'Custom Token Limit',
                                style: TextStyle(
                                  color: Color(0xFF2D241C),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: TextField(
                                controller: controller,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Enter token limit',
                                  hintText: 'e.g. 32768, 128000',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    final val = int.tryParse(controller.text);
                                    Navigator.pop(ctx, val);
                                  },
                                  child: const Text('Set'),
                                ),
                              ],
                            ),
                          );
                          if (customVal != null && customVal > 0) {
                            setState(() {
                              _maxTokens = customVal;
                            });
                            widget.onMaxTokensChanged(customVal);
                          }
                        },
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: Color(0xFF7B4E2E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Slider(
                value: _maxTokens.toDouble().clamp(128, 16384),
                min: 128,
                max: 16384,
                divisions: 63,
                activeColor: const Color(0xFF7B4E2E),
                inactiveColor: const Color(0xFFE7D8C4),
                onChanged: (val) {
                  setState(() => _maxTokens = (val as double).round());
                  widget.onMaxTokensChanged((val as double).round());
                },
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [512, 1024, 2048, 4096, 8192].map((preset) {
                    final selected = _maxTokens == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ChoiceChip(
                        label: Text(
                          preset.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: selected
                                ? Colors.white
                                : const Color(0xFF6C5946),
                          ),
                        ),
                        selected: selected,
                        selectedColor: const Color(0xFF7B4E2E),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: selected
                              ? Colors.transparent
                              : const Color(0xFFE5DDD3),
                        ),
                        onSelected: (sel) {
                          if (sel == true) {
                            setState(() => _maxTokens = preset);
                            widget.onMaxTokensChanged(preset);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Thinking / Reasoning Switch Card
        LiquidGlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CoT Thinking / Reasoning',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Allow models to think step-by-step',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Switch(
                value: _reasoningEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _reasoningEnabled = val);
                  widget.onReasoningEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapabilitiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File Access Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agentic File Access',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Let models read/write local files',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _agenticEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) async {
                      if (val) {
                        if (_searchEnabled) {
                          _showExclusivitySnackBar('Agentic File Access', 'Web Search');
                          return;
                        }
                        if (_deepResearchEnabled) {
                          _showExclusivitySnackBar('Agentic File Access', 'Deep Research');
                          return;
                        }
                        if (_studyModeEnabled) {
                          _showExclusivitySnackBar('Agentic File Access', 'Study Mode');
                          return;
                        }
                        final result = await _checkBridgeAlive();
                        if (!mounted) return;
                        if (result['ok'] != true) {
                          final reason = result['reason']?.toString() ?? 'bridge_unreachable';
                          _showDeepResearchSetupDialog(reason: reason);
                          return;
                        }
                      }
                      setState(() => _agenticEnabled = val);
                      widget.onAgenticEnabledChanged(val);
                    },
                  ),
                ],
              ),
              if (_agenticEnabled) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _agenticWorkspaceController,
                  decoration: const InputDecoration(
                    labelText: 'Workspace Directory Path',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'e.g. /data/data/com.termux/files/home',
                  ),
                  onChanged: widget.onAgenticWorkspaceChanged,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customMcpUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Custom MCP URL (Optional)',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'e.g. http://192.168.1.10:8390/mcp',
                  ),
                  onChanged: widget.onCustomMcpUrlChanged,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Web Search Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agentic Web Search',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Let models search the web if needed',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _searchEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) {
                      if (val && _agenticEnabled) {
                        _showExclusivitySnackBar('Web Search', 'Agentic File Access');
                        return;
                      }
                      setState(() => _searchEnabled = val);
                      _updateSearchSettings();
                    },
                  ),
                ],
              ),
              if (_searchEnabled) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _searchProvider,
                  dropdownColor: const Color(0xFFFFFBF2),
                  decoration: const InputDecoration(
                    labelText: 'Search API Provider',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    'tavily',
                    'duckduckgo',
                    'exa',
                    'firecrawl',
                    'google',
                    ..._searchSettings.customProviders.map((p) => 'custom:${p.id}'),
                  ].map((p) {
                    final label = p.startsWith('custom:')
                        ? _searchSettings.customProviders
                            .firstWhere((cp) => cp.id == p.substring(7),
                                orElse: () => CustomSearchProvider(
                                    id: '', name: 'Unknown', endpoint: ''))
                            .name
                        : p.toUpperCase();
                    return DropdownMenuItem<String>(
                      value: p,
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _searchProvider = val);
                      _updateSearchSettings();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Search API Key(s) (comma-separated)',
                    labelStyle: TextStyle(
                      color: Color(0xFF6C5946),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    border: OutlineInputBorder(),
                    hintText: 'key1, key2...',
                  ),
                  obscureText: true,
                  onChanged: (_) => _updateSearchSettings(),
                ),
                if (_searchProvider == 'google') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCxController,
                    decoration: const InputDecoration(
                      labelText: 'Google Search Engine ID (CX)',
                      labelStyle: TextStyle(
                        color: Color(0xFF6C5946),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateSearchSettings(),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Custom Search Providers',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showCustomSearchProviderDialog(),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7B4E2E),
                      ),
                    ),
                  ],
                ),
                if (_searchSettings.customProviders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'No custom providers. Add one to use any OpenAI-compatible search API.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9B8B7A)),
                    ),
                  ),
                ..._searchSettings.customProviders.map((cp) => Card(
                      margin: const EdgeInsets.only(top: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(cp.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(cp.endpoint, style: const TextStyle(fontSize: 10, color: Color(0xFF9B8B7A)), overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _searchSettings = _searchSettings.copyWith(
                                customProviders: _searchSettings.customProviders
                                    .where((p) => p.id != cp.id)
                                    .toList(),
                              );
                              if (_searchProvider == 'custom:${cp.id}') {
                                _searchProvider = 'tavily';
                              }
                              _updateSearchSettings();
                            });
                          },
                        ),
                      ),
                    )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Artifacts Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Artifacts',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Let models create HTML, React, markdown & code artifacts',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Switch(
                value: _artifactsEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _artifactsEnabled = val);
                  widget.onArtifactsEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // SVG Visuals Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SVG Visuals',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Let models render dynamic SVG diagrams',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Switch(
                value: _svgVisualsEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) {
                  setState(() => _svgVisualsEnabled = val);
                  widget.onSvgVisualsEnabledChanged(val);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Agentic Deep Research Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agentic Deep Research',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Multi-step research with web search. Requires Web Search enabled.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Switch(
                value: _deepResearchEnabled,
                activeColor: const Color(0xFF7B4E2E),
                  onChanged: (val) async {
                    if (val) {
                      if (_agenticEnabled) {
                        _showExclusivitySnackBar('Deep Research', 'Agentic File Access');
                        return;
                      }
                      if (_studyModeEnabled) {
                        _showExclusivitySnackBar('Deep Research', 'Study Mode');
                        return;
                      }
                      final result = await _checkBridgeAlive();
                      if (!mounted) return;
                      if (result['ok'] != true) {
                        final reason =
                            result['reason']?.toString() ?? 'bridge_unreachable';
                        _showDeepResearchSetupDialog(reason: reason);
                        setState(() => _deepResearchEnabled = false);
                        widget.onDeepResearchEnabledChanged(false);
                        return;
                      }
                    }
                    setState(() => _deepResearchEnabled = val);
                    widget.onDeepResearchEnabledChanged(val);
                  },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Study Mode / Cross-Document Analysis Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Study Mode / Cross-Document Analysis',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cross-reference sources, synthesize insights, and build study guides across documents',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _studyModeEnabled,
                activeColor: const Color(0xFF7B4E2E),
                onChanged: (val) async {
                  if (val) {
                    if (_agenticEnabled) {
                      _showExclusivitySnackBar('Study Mode', 'Agentic File Access');
                      return;
                    }
                    if (_deepResearchEnabled) {
                      _showExclusivitySnackBar('Study Mode', 'Deep Research');
                      return;
                    }
                    final bridgeResult = await _checkBridgeAlive();
                    if (!bridgeResult['alive']) {
                      _appendSystemMessage(
                        'Study Mode requires the Python bridge. Start it from Settings or run the bridge manually.',
                      );
                      return;
                    }
                  }
                  setState(() => _studyModeEnabled = val);
                  await _saveStudyMode(val);
                  widget.onStudyModeEnabledChanged(val);

                  if (val) {
                    // Check backend dependencies for document extraction
                    try {
                      final client = HttpClient();
                      client.connectionTimeout = const Duration(seconds: 4);
                      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8390/workspace/deps'));
                      final resp = await req.close();
                      final body = await resp.transform(utf8.decoder).join();
                      client.close();

                      if (resp.statusCode == 200) {
                        final deps = jsonDecode(body) as Map<String, dynamic>;
                        final allPresent = deps['all_present'] == true;
                        if (!allPresent && mounted) {
                          final missing = (deps['missing'] as List).cast<String>();
                          final commands = (deps['commands'] as List).cast<String>();
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Missing Document Extractors'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Study mode is enabled, but some document extractors are missing. You may not be able to index PDFs or DOCX files until they are installed in Termux.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Missing: ${missing.join(', ')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  const SizedBox(height: 8),
                                  const Text('Run in Termux:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  ...commands.map((c) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(6)),
                                      child: SelectableText(c, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent)),
                                    ),
                                  )),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Got it'),
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    } catch (_) {
                      // Silently fail if bridge isn't running yet — user can toggle later
                    }
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Audio Feedback / TTS Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Audio Feedback / TTS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D241C),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Text-to-Speech audio button on model outputs',
                    style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
                  ),
                ],
              ),
              Icon(Icons.volume_up_rounded, color: Color(0xFF7B4E2E), size: 24),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Live Voice & TTS Engine Voice Selection Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Voice',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'The voice used for read-aloud and Live Voice.',
                style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<dynamic>>(
                future: NexonTts.getVoices(),
                builder: (context, snapshot) {
                  final allVoices = snapshot.data ?? [];
                  final voices = allVoices.where((v) {
                    if (v is! Map) return false;
                    final locale = v['locale']?.toString().toLowerCase() ?? '';
                    return locale.startsWith('en-') || locale == 'en';
                  }).toList();
                  if (voices.isEmpty) {
                    return const Text(
                      'Default System Voice',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7B4E2E),
                      ),
                    );
                  }
                  return DropdownButtonFormField<String>(
                    value: _selectedVoiceName ?? NexonTts.selectedVoiceName,
                    dropdownColor: const Color(0xFFFFFBF2),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: voices.map((v) {
                      final name = v is Map
                          ? (v['name']?.toString() ?? 'Voice')
                          : v.toString();
                      final lang = v is Map
                          ? (v['locale']?.toString() ?? '')
                          : '';
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(
                          '$name ${lang.isNotEmpty ? "($lang)" : ""}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final selected = voices.firstWhere(
                          (v) => v is Map && v['name'] == val,
                          orElse: () => <String, dynamic>{},
                        );
                        final locale = selected is Map
                            ? (selected['locale']?.toString() ?? 'en-US')
                            : 'en-US';
                        setState(() => _selectedVoiceName = val);
                        NexonTts.setVoice({"name": val, "locale": locale});
                      }
                    },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Writer Context Budget Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Writer Context Budget',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set this near your selected model\'s context limit, leaving room for instructions and output. '
                'The writer reserves ~18% for prompts; the rest is available for evidence.',
                style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _writerContextBudgetController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'e.g. 32000',
                        suffixText: 'tokens',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5DDD3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF7B4E2E),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5DDD3),
                          ),
                        ),
                      ),
                      onSubmitted: (val) {
                        final parsed = int.tryParse(val.trim());
                        if (parsed != null && parsed > 0) {
                          setState(() => _writerContextBudget = parsed);
                          widget.onWriterContextBudgetChanged(parsed);
                        } else {
                          // Reset field to current valid value
                          _writerContextBudgetController.text =
                              _writerContextBudget.toString();
                        }
                      },
                      onEditingComplete: () {
                        final parsed = int.tryParse(
                          _writerContextBudgetController.text.trim(),
                        );
                        if (parsed != null && parsed > 0) {
                          setState(() => _writerContextBudget = parsed);
                          widget.onWriterContextBudgetChanged(parsed);
                        } else {
                          _writerContextBudgetController.text =
                              _writerContextBudget.toString();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current: $_writerContextBudget tokens  ·  Evidence cap: ${(_writerContextBudget * 0.82).floor()} tokens',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7B4E2E),
                  fontStyle: FontStyle.italic,
                ),
              ),
              // Soft advisory — shown only when the budget is very low.
              // This is purely informational; deep research will still run.
              if (_writerContextBudget <= 8192)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      border: Border.all(color: const Color(0xFFFFCC02)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1, right: 8),
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Color(0xFFF9A825),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Low context budget: Deep Research works best with at least '
                            '16 000 tokens. With $_writerContextBudget tokens, only a small '
                            'amount of evidence will fit and report quality may be reduced. '
                            'You can still run it — this is only a heads-up.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6D4C00),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Personalization Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Name',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Personalizes replies and the user_info block',
                style: TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userNameController,
                onChanged: (val) => widget.onUserNameChanged(val.trim()),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'e.g. Shiva',
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFFFFFBF2),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Cloud Sync & Backup Card
        LiquidGlassSurface(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Drive Backup',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Auto-sync chats & artifacts to Drive',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: _driveBackupEnabled,
                    activeColor: const Color(0xFF7B4E2E),
                    onChanged: (val) async {
                      setState(() => _driveBackupEnabled = val);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('google_drive_backup_enabled', val);
                    },
                  ),
                ],
              ),
              if (_driveBackupEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Live progress status text
                      if (_syncProgressStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Color(0xFF7B4E2E),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _syncProgressStatus,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7B4E2E),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_backupResultMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _backupResultSuccess
                                    ? Icons.cloud_done
                                    : Icons.cloud_off,
                                size: 14,
                                color: _backupResultSuccess
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _backupResultMessage,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _backupResultSuccess
                                        ? const Color(0xFF3B7A3B)
                                        : const Color(0xFFB33A3A),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: _isRestoring || _isBackingUp
                                ? null
                                : () async {
                                    setState(() {
                                      _isRestoring = true;
                                      _syncProgressStatus = 'Starting restore…';
                                    });
                                    try {
                                      final result =
                                          await DriveSyncService.restoreFromDriveDetailed(
                                            onProgress: (status) {
                                              if (mounted) {
                                                setState(
                                                  () => _syncProgressStatus =
                                                      status,
                                                );
                                              }
                                            },
                                          );
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
                                        if (result.success) {
                                          await widget.onRestoreCompleted();
                                        }
                                        _showSyncResultDialog(
                                          context,
                                          title: result.success
                                              ? 'Restore Complete'
                                              : 'Restore Failed',
                                          message: result.message,
                                          details: result.details,
                                          success: result.success,
                                          needsRelogin: result.needsRelogin,
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(
                                          () => _syncProgressStatus = '',
                                        );
                                        _showSyncResultDialog(
                                          context,
                                          title: 'Restore Error',
                                          message: 'Unexpected error: $e',
                                          details: [],
                                          success: false,
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isRestoring = false;
                                          _syncProgressStatus = '';
                                        });
                                      }
                                    }
                                  },
                            icon: _isRestoring
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download, size: 16),
                            label: Text(
                              _isRestoring ? 'Restoring…' : 'Restore',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7B4E2E),
                              backgroundColor: const Color(0xFFF5EFE6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _isBackingUp || _isRestoring
                                ? null
                                : () async {
                                    setState(() {
                                      _isBackingUp = true;
                                      _syncProgressStatus = 'Starting backup…';
                                      _backupResultMessage = '';
                                    });
                                    try {
                                      final result =
                                          await DriveSyncService.syncToDriveDetailed(
                                        widget.sessions,
                                        force: true,
                                        onProgress: (status) {
                                          if (mounted) {
                                            setState(
                                              () => _syncProgressStatus =
                                                  status,
                                            );
                                          }
                                        },
                                      );
                                      if (mounted) {
                                        setState(() {
                                          _syncProgressStatus = '';
                                          _backupResultSuccess = result.success;
                                          _backupResultMessage = result.success
                                              ? result.message
                                              : 'Backup failed: ${result.message}';
                                        });
                                        if (!result.success || result.needsRelogin) {
                                          _showSyncResultDialog(
                                            context,
                                            title: result.success
                                                ? 'Backup Complete'
                                                : 'Backup Failed',
                                            message: result.message,
                                            details: result.details,
                                            success: result.success,
                                            needsRelogin: result.needsRelogin,
                                          );
      } else if (method == 'workspace_cross_compare' && decoded is Map) {
        final groups = (decoded['results'] as List?) ??
            (decoded['groups'] as List?) ?? [];
        header = 'Cross-document comparison (${groups.length} docs)';
        icon = Icons.compare_arrows;
        accent = const Color(0xFF7C3AED);
        for (final g in groups.whereType<Map>().take(6)) {
          final file = g['file']?.toString() ??
              g['file_path']?.toString() ??
              g['document']?.toString() ?? '';
          final chunks = (g['chunks'] as List?) ?? [];
          for (final chunk in chunks.whereType<Map>().take(2)) {
            final excerpt = chunk['content']?.toString() ??
                chunk['excerpt']?.toString() ?? '';
            final page = chunk['page']?.toString() ?? '';
            detailChildren.add(
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE7D8C4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file + (page.isNotEmpty ? ' — Page $page' : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      excerpt,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF52606D),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      } else {
                                          Future.delayed(const Duration(seconds: 3), () {
                                            if (mounted) setState(() => _backupResultMessage = '');
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() {
                                          _syncProgressStatus = '';
                                          _backupResultSuccess = false;
                                          _backupResultMessage = 'Backup error: $e';
                                        });
                                        _showSyncResultDialog(
                                          context,
                                          title: 'Backup Error',
                                          message: 'Unexpected error: $e',
                                          details: [],
                                          success: false,
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isBackingUp = false;
                                          _syncProgressStatus = '';
                                        });
                                      }
                                    }
                                  },
                            icon: _isBackingUp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload, size: 16),
                            label: Text(
                              _isBackingUp ? 'Backing up…' : 'Force Backup',
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF7B4E2E),
                              backgroundColor: const Color(0xFFF5EFE6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const Divider(height: 32, color: Color(0xFFE5DDD3)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6C5946),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Supabase.instance.client.auth.currentSession?.user.email ??
                        'Not logged in',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2D241C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (Supabase.instance.client.auth.currentSession != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Active Plan: ${_activePlanTier.isEmpty ? "FREE" : _activePlanTier.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF7B4E2E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Daily Pool: ${_liveDailyPool != null ? "${_formatNumber(_liveDailyPool!)} / ${_formatNumber(_getTotalDailyCap(_activePlanTier))}" : "Loading..."}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                    if (_activePlanTier.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Monthly Pool: ${_liveSubscriptionCredits != null ? "${_formatNumber(_liveSubscriptionCredits!)} / ${_formatNumber(_getTotalMonthlyCap(_activePlanTier))}" : "Loading..."}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                    if (_liveTopupCredits != null &&
                        _liveTopupCredits! > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Top-up Credits: ${_formatNumber(_liveTopupCredits!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6C5946),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => WarmGlassDialog(
                              title: const Text(
                                'Confirm Logout',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              content: const Text(
                                'Are you sure you want to logout?',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () async {
                                    Navigator.of(ctx).pop();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                      'has_completed_onboarding_v2',
                                      false,
                                    );
                                    await Supabase.instance.client.auth
                                        .signOut();
                                    if (mounted) {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const ForgeChatApp(
                                            hasCompletedOnboarding: false,
                                          ),
                                        ),
                                        (route) => false,
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'Logout',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.logout,
                          size: 16,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Logout',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => UpdateService.checkForUpdates(
                          context,
                          userInitiated: true,
                        ),
                        icon: const Icon(
                          Icons.system_update_rounded,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        label: const Text(
                          'Check for Updates',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Subscription Settings Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF9F4),
            border: Border.all(color: const Color(0xFFE5DDD3)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nexon Subscription Plans',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D241C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _managedSubscriptionEnabled
                          ? 'Active Plan: ${_activePlanTier.toUpperCase()}'
                          : 'Switch to a Managed API key and skip the hassle.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6C5946),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (sheetContext) {
                      return Padding(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 24,
                          bottom:
                              MediaQuery.of(sheetContext).viewInsets.bottom +
                              24,
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Manage Subscription',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF2D241C),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        Navigator.pop(sheetContext),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildSubscriptionPlans(),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D241C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Manage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSubscriptionPlans() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPlanCard(
          title: 'GO',
          subtitle: 'The Student / Hobbyist Tier',
          price: '₹249',
          monthlyCredits: '16.5M',
          dailyCap: '550K',
          color: const Color(0xFFE8F3EB),
          borderColor: const Color(0xFFC3DFCD),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'PLUS',
          subtitle: 'The Light Freelancer Tier',
          price: '₹499',
          monthlyCredits: '33.5M',
          dailyCap: '1.1M',
          color: const Color(0xFFEBF0F6),
          borderColor: const Color(0xFFC7D9EA),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'PRO',
          subtitle: 'The Professional Tier',
          price: '₹899',
          monthlyCredits: '61.0M',
          dailyCap: '2.0M',
          color: const Color(0xFFF6EBF0),
          borderColor: const Color(0xFFEAC7D9),
        ),
        const SizedBox(height: 12),
        _buildPlanCard(
          title: 'MAX',
          subtitle: 'The Power User Tier',
          price: '₹1,399',
          monthlyCredits: '95.0M',
          dailyCap: '3.1M',
          color: const Color(0xFFFFF7E6),
          borderColor: const Color(0xFFFFD580),
          isPremium: true,
        ),
      ],
    );
  }

  Widget _buildPlanCard({
    required String title,
    required String subtitle,
    required String price,
    required String monthlyCredits,
    required String dailyCap,
    required Color color,
    required Color borderColor,
    bool isPremium = false,
  }) {
    final bool isThisPlanActive =
        _managedSubscriptionEnabled && _activePlanTier == title.toLowerCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor, width: isPremium ? 2 : 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2D241C),
                        ),
                      ),
                      if (isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D241C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6C5946),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '$price/mo',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildPlanStat(
                'Monthly Credits',
                isThisPlanActive && _liveSubscriptionCredits != null
                    ? '${(_liveSubscriptionCredits! / 1000000).toStringAsFixed(1)}M'
                    : monthlyCredits,
              ),
              _buildPlanStat(
                'Daily Cap',
                isThisPlanActive && _liveDailyPool != null
                    ? '${(_liveDailyPool! / 1000).toStringAsFixed(1)}K'
                    : dailyCap,
              ),
              ElevatedButton(
                onPressed: () {
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
                            Icons.workspace_premium_rounded,
                            color: Color(0xFFD97706),
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Coming Soon',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      content: Text(
                        'Subscriptions for the $title plan are coming soon! Stay updated for upcoming releases.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                      actionsPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      actions: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2D241C),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'Got it, Stay Updated!',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D241C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text(
                  'Subscribe',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6C5946)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D241C),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachTab(bool visionEnabled) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LiquidGlassSurface(
          padding: const EdgeInsets.all(18),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Media & Document Attachments',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose photos, capture via camera, or attach documents to send as context.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6C5946)),
              ),
              const SizedBox(height: 18),

              // Grid of media attachment buttons
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _buildAttachTile(
                    Icons.image_outlined,
                    'Photos',
                    'Gallery images',
                    isEnabled: true,
                    onTap: _pickImage,
                  ),
                  _buildAttachTile(
                    Icons.camera_alt_outlined,
                    'Camera',
                    'Capture photo',
                    isEnabled: true,
                    onTap: _pickImage,
                  ),
                  _buildAttachTile(
                    Icons.insert_drive_file_outlined,
                    'Document',
                    'PDF, TXT, MD, Code',
                    isEnabled: true,
                    onTap: _pickFile,
                  ),
                  _buildAttachTile(
                    Icons.mic_none_outlined,
                    'Audio',
                    'Voice notes',
                    isEnabled: false,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Audio input is not supported yet.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttachTile(
    IconData icon,
    String title,
    String subtitle, {
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.45,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFF1EAE0),
            border: Border.all(
              color: isEnabled ? const Color(0xFFE2D6C5) : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 24,
                color: isEnabled
                    ? const Color(0xFF7B4E2E)
                    : const Color(0xFF9E8F7F),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isEnabled
                      ? const Color(0xFF2D241C)
                      : const Color(0xFF9E8F7F),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isEnabled
                      ? const Color(0xFF77624F)
                      : const Color(0xFFB0A59A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMediaItem(
    IconData icon,
    String label, {
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isEnabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFF8F5F0),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled ? const Color(0xFFDCCBB8) : Colors.transparent,
              width: 1,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF7B4E2E).withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 26,
                color: isEnabled
                    ? const Color(0xFF7B4E2E)
                    : const Color(0xFFB0A496),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isEnabled
                      ? const Color(0xFF2D241C)
                      : const Color(0xFFB0A496),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show a detailed result dialog after backup/restore with step-by-step log.
  void _showSyncResultDialog(
    BuildContext context, {
    required String title,
    required String message,
    required List<String> details,
    required bool success,
    bool needsRelogin = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFBF2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              success ? Icons.cloud_done : Icons.cloud_off,
              color: success ? Colors.green : Colors.red,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D241C),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: success
                        ? const Color(0xFF3B7A3B)
                        : const Color(0xFFB33A3A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (needsRelogin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3CD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Color(0xFFD4A017),
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sign out and sign in again with Google to re-authorize Drive access.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7B6B2E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Details:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7B4E2E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5EFE6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: details.map((line) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: line.startsWith('❌')
                                  ? const Color(0xFFB33A3A)
                                  : line.startsWith('✅')
                                  ? const Color(0xFF3B7A3B)
                                  : line.startsWith('⚠️')
                                  ? const Color(0xFFD4A017)
                                  : const Color(0xFF5A4A3A),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF7B4E2E))),
          ),
        ],
      ),
    );
  }
}
