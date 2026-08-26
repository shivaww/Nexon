// Extracted from main.dart lines 10326-11112
// Extracted on: 2026-08-26T18:20:45.723897

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Rich chat media display system
// ══════════════════════════════════════════════════════════════════════════════

/// Animated shimmer placeholder — shown while media decodes or loads.
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 12,
  });
  final double width;
  final double height;
  final double radius;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              const Color(0xFFE8DDD0),
              Color.lerp(
                const Color(0xFFE8DDD0),
                const Color(0xFFF5EDE0),
                _anim.value,
              )!,
              const Color(0xFFE8DDD0),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of image + video tiles in a chat bubble.
class _ChatMediaGrid extends StatelessWidget {
  const _ChatMediaGrid({required this.images, required this.videos});
  final List<String> images;
  final List<String> videos;

  @override
  Widget build(BuildContext context) {
    final allImages = images;
    final allVideos = videos;
    final total = allImages.length + allVideos.length;

    // Build combined tile list: images first, then videos
    final tiles = <Widget>[
      for (int i = 0; i < allImages.length; i++)
        _ImageChatTile(
          heroTag: 'chat_img_${allImages[i].hashCode}_$i',
          base64Data: allImages[i],
          allImages: allImages,
          initialIndex: i,
        ),
      for (int i = 0; i < allVideos.length; i++)
        _VideoChatTile(base64Data: allVideos[i], index: i),
    ];

    if (total == 1) {
      // Single item — show larger
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(width: 260, height: 180, child: tiles.first),
      );
    }

    if (total == 2) {
      return SizedBox(
        height: 140,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: tiles[0]),
            const SizedBox(width: 6),
            Flexible(child: tiles[1]),
          ],
        ),
      );
    }

    // 3+ items — wrap grid
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tiles.map((t) {
        return SizedBox(width: 140, height: 140, child: t);
      }).toList(),
    );
  }
}

/// A single image tile with shimmer loading, error state, hero + fullscreen viewer.
class _ImageChatTile extends StatefulWidget {
  const _ImageChatTile({
    required this.heroTag,
    required this.base64Data,
    required this.allImages,
    required this.initialIndex,
  });
  final String heroTag;
  final String base64Data;
  final List<String> allImages;
  final int initialIndex;

  @override
  State<_ImageChatTile> createState() => _ImageChatTileState();
}

class _ImageChatTileState extends State<_ImageChatTile> {
  Uint8List? _bytes;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _decode() {
    try {
      final bytes = base64Decode(widget.base64Data);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _ChatMediaViewer(
          images: widget.allImages,
          initialIndex: widget.initialIndex,
          heroTag: widget.heroTag,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _errorTile();
    }
    if (_bytes == null) {
      return _ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return GestureDetector(
      onTap: () => _openViewer(context),
      child: Hero(
        tag: widget.heroTag,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true),
                // Subtle gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.25),
                        ],
                      ),
                    ),
                  ),
                ),
                // Tap-to-expand hint icon
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.fullscreen_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorTile() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF5EDE0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDCCBB8)),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, color: Color(0xFFB08060), size: 32),
        SizedBox(height: 4),
        Text(
          'Image unavailable',
          style: TextStyle(fontSize: 10, color: Color(0xFFB08060)),
        ),
      ],
    ),
  );
}

/// A single video tile backed by VideoPlayerController.
/// Shows thumbnail (first decoded frame via controller) with play overlay.
class _VideoChatTile extends StatefulWidget {
  const _VideoChatTile({required this.base64Data, required this.index});
  final String base64Data;
  final int index;

  @override
  State<_VideoChatTile> createState() => _VideoChatTileState();
}

class _VideoChatTileState extends State<_VideoChatTile> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final bytes = base64Decode(widget.base64Data);
      // Write to temp file so VideoPlayerController can load it
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/nexon_video_${widget.index}_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await file.writeAsBytes(bytes);
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      ctrl.addListener(() {
        if (mounted) setState(() => _isPlaying = ctrl.value.isPlaying);
      });
      if (mounted) {
        setState(() {
          _ctrl = ctrl;
          _initialized = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _errorTile();
    }

    if (!_initialized || _ctrl == null) {
      return _ShimmerBox(width: double.infinity, height: double.infinity);
    }

    return GestureDetector(
      onTap: () {
        if (_expanded) {
          _isPlaying ? _ctrl!.pause() : _ctrl!.play();
        } else {
          setState(() => _expanded = true);
          _ctrl!.play();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _expanded ? _buildPlayer() : _buildThumbnail(),
      ),
    );
  }

  Widget _buildThumbnail() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // First frame as thumbnail
        AspectRatio(
          aspectRatio: _ctrl!.value.aspectRatio,
          child: VideoPlayer(_ctrl!),
        ),
        // Dark overlay
        Container(color: Colors.black54),
        // Play icon
        const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: Colors.white,
            size: 44,
          ),
        ),
        // Duration badge
        Positioned(
          bottom: 6,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _fmtDuration(_ctrl!.value.duration),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Video badge
        Positioned(
          top: 6,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xB2000000),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_rounded,
                  color: Color(0xFF67E8A0),
                  size: 12,
                ),
                SizedBox(width: 3),
                Text(
                  'VIDEO',
                  style: TextStyle(
                    color: Color(0xFF67E8A0),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _ctrl!.value.aspectRatio,
            child: VideoPlayer(_ctrl!),
          ),
        ),
        // Play/Pause overlay
        Center(
          child: AnimatedOpacity(
            opacity: _isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        // Progress bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _ctrl!,
            builder: (_, val, __) {
              final total = val.duration.inMilliseconds;
              final pos = val.position.inMilliseconds;
              final progress = total == 0 ? 0.0 : pos / total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF67E8A0),
                    ),
                    minHeight: 3,
                  ),
                  Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmtDuration(val.position),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          _fmtDuration(val.duration),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Buffering spinner
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _ctrl!,
          builder: (_, val, __) => val.isBuffering
              ? const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF67E8A0),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _errorTile() => Container(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.videocam_off_rounded, color: Color(0xFF67E8A0), size: 32),
        SizedBox(height: 6),
        Text(
          'Video unavailable',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
      ],
    ),
  );
}

/// Full-screen media viewer with:
///  - Hero transition from chat bubble
///  - InteractiveViewer pinch-to-zoom for images
///  - VideoPlayer with controls for videos
///  - Swipe-down to dismiss
///  - Thumbnail strip for navigating multiple images
class _ChatMediaViewer extends StatefulWidget {
  const _ChatMediaViewer({
    required this.images,
    required this.initialIndex,
    required this.heroTag,
  });
  final List<String> images;
  final int initialIndex;
  final String heroTag;

  @override
  State<_ChatMediaViewer> createState() => _ChatMediaViewerState();
}

class _ChatMediaViewerState extends State<_ChatMediaViewer> {
  late int _current;
  late final PageController _pageCtrl;
  final _transformKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity!.abs() > 600) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            // Blurred dark background
            Container(color: Colors.black.withOpacity(0.92)),

            // Image pager
            PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                Uint8List? bytes;
                try {
                  bytes = base64Decode(widget.images[i]);
                } catch (_) {}

                if (bytes == null) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 60,
                    ),
                  );
                }

                final heroTag = i == widget.initialIndex
                    ? widget.heroTag
                    : 'viewer_img_$i';

                return Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 6.0,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                );
              },
            ),

            // Top bar — image counter + close
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (widget.images.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_current + 1} / ${widget.images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Hint: swipe down to dismiss
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 80,
              left: 0,
              right: 0,
              child: const Center(
                child: Text(
                  'Swipe down to dismiss · Pinch to zoom',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ),

            // Thumbnail strip (multiple images)
            if (widget.images.length > 1)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 12,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.images.length,
                    itemBuilder: (context, i) {
                      Uint8List? bytes;
                      try {
                        bytes = base64Decode(widget.images[i]);
                      } catch (_) {}
                      final isSelected = i == _current;
                      return GestureDetector(
                        onTap: () => _pageCtrl.animateToPage(
                          i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white30,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                          child: bytes == null
                              ? const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white38,
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(bytes, fit: BoxFit.cover),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
