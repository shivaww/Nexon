/// Plugin system service for TermuxForge.
///
/// Manages installation and lifecycle of plugins that extend the IDE's
/// capabilities including custom tools, MCP servers, agent types,
/// UI panels, workflow templates, model adapters, and media adapters.
library;

import 'package:uuid/uuid.dart';

/// Types of plugins supported.
enum PluginType {
  /// Custom tool for the Tool Registry.
  tool,

  /// MCP server configuration.
  mcpServer,

  /// Custom agent type.
  agentType,

  /// UI panel or widget.
  uiPanel,

  /// Workflow template.
  workflowTemplate,

  /// LLM model adapter.
  modelAdapter,

  /// Media generation adapter.
  mediaAdapter,

  /// Theme or appearance customization.
  theme,
}

/// Status of a plugin.
enum PluginStatus {
  /// Available but not installed.
  available,

  /// Currently being installed.
  installing,

  /// Installed and active.
  active,

  /// Installed but disabled.
  disabled,

  /// Failed to load or install.
  error,
}

/// Represents a plugin that extends TermuxForge.
class Plugin {
  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// Description of what this plugin does.
  final String description;

  /// Plugin type.
  final PluginType type;

  /// Version string.
  final String version;

  /// Author name.
  final String author;

  /// Current status.
  PluginStatus status;

  /// Plugin configuration.
  final Map<String, dynamic> config;

  /// Required permissions.
  final List<String> requiredPermissions;

  /// Dependencies on other plugins.
  final List<String> dependencies;

  /// When this plugin was installed.
  DateTime? installedAt;

  /// Path to plugin files if local.
  final String? localPath;

  /// Error message if status is error.
  String? errorMessage;

  Plugin({
    String? id,
    required this.name,
    required this.description,
    required this.type,
    this.version = '1.0.0',
    this.author = 'Unknown',
    this.status = PluginStatus.available,
    this.config = const {},
    this.requiredPermissions = const [],
    this.dependencies = const [],
    this.installedAt,
    this.localPath,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'type': type.name,
        'version': version,
        'author': author,
        'status': status.name,
        'config': config,
        'requiredPermissions': requiredPermissions,
        'dependencies': dependencies,
        'installedAt': installedAt?.toIso8601String(),
        'localPath': localPath,
      };
}

/// Plugin system service.
///
/// Manages the lifecycle of plugins including discovery, installation,
/// activation, configuration, and removal.
class PluginService {
  // Singleton
  static final PluginService _instance = PluginService._internal();
  factory PluginService() => _instance;
  PluginService._internal();

  /// Registry of all known plugins.
  final Map<String, Plugin> _plugins = {};

  /// Register a plugin.
  void registerPlugin(Plugin plugin) {
    _plugins[plugin.id] = plugin;
  }

  /// Install a plugin.
  Future<bool> installPlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;

    try {
      plugin.status = PluginStatus.installing;

      // Check dependencies
      for (final dep in plugin.dependencies) {
        final depPlugin = _plugins[dep];
        if (depPlugin == null || depPlugin.status != PluginStatus.active) {
          plugin.status = PluginStatus.error;
          plugin.errorMessage = 'Missing dependency: $dep';
          return false;
        }
      }

      // TODO: Actually load plugin resources based on type
      plugin.status = PluginStatus.active;
      plugin.installedAt = DateTime.now();
      return true;
    } catch (e) {
      plugin.status = PluginStatus.error;
      plugin.errorMessage = e.toString();
      return false;
    }
  }

  /// Disable a plugin.
  void disablePlugin(String pluginId) {
    final plugin = _plugins[pluginId];
    if (plugin != null && plugin.status == PluginStatus.active) {
      plugin.status = PluginStatus.disabled;
    }
  }

  /// Enable a previously disabled plugin.
  void enablePlugin(String pluginId) {
    final plugin = _plugins[pluginId];
    if (plugin != null && plugin.status == PluginStatus.disabled) {
      plugin.status = PluginStatus.active;
    }
  }

  /// Remove a plugin.
  Future<bool> removePlugin(String pluginId) async {
    final plugin = _plugins[pluginId];
    if (plugin == null) return false;

    // Check if other plugins depend on this one
    final dependents = _plugins.values.where(
      (p) => p.dependencies.contains(pluginId) && p.status == PluginStatus.active,
    );
    if (dependents.isNotEmpty) return false;

    _plugins.remove(pluginId);
    return true;
  }

  /// Get a plugin by ID.
  Plugin? getPlugin(String pluginId) => _plugins[pluginId];

  /// List all plugins, optionally filtered.
  List<Plugin> listPlugins({PluginType? type, PluginStatus? status}) {
    var plugins = _plugins.values;
    if (type != null) plugins = plugins.where((p) => p.type == type);
    if (status != null) plugins = plugins.where((p) => p.status == status);
    return plugins.toList();
  }

  /// List active plugins of a specific type.
  List<Plugin> getActivePlugins(PluginType type) {
    return listPlugins(type: type, status: PluginStatus.active);
  }

  /// Update plugin configuration.
  void configurePlugin(String pluginId, Map<String, dynamic> config) {
    final plugin = _plugins[pluginId];
    if (plugin != null) {
      plugin.config.addAll(config);
    }
  }

  /// Get plugin statistics.
  Map<String, dynamic> getStats() {
    return {
      'total': _plugins.length,
      'active': _plugins.values.where((p) => p.status == PluginStatus.active).length,
      'disabled': _plugins.values.where((p) => p.status == PluginStatus.disabled).length,
      'errors': _plugins.values.where((p) => p.status == PluginStatus.error).length,
      'byType': PluginType.values.map((t) => {
            'type': t.name,
            'count': _plugins.values.where((p) => p.type == t).length,
          }).toList(),
    };
  }
}
