import 'package:flutter/material.dart';
import 'package:nexon/widgets/liquid_glass_widgets.dart';

/// One option in a [GlassPickerField].
class GlassPickerItem<T> {
  final T value;
  final String label;
  const GlassPickerItem(this.value, this.label);
}

/// Outlined field that opens a frosted-glass popup under itself instead of
/// the flat Material dropdown menu.
class GlassPickerField<T> extends StatefulWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<GlassPickerItem<T>> items;
  final ValueChanged<T> onChanged;
  final double fontSize;
  final FontWeight fontWeight;
  final int maxLines;

  const GlassPickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w600,
    this.maxLines = 1,
  });

  @override
  State<GlassPickerField<T>> createState() => _GlassPickerFieldState<T>();
}

class _GlassPickerFieldState<T> extends State<GlassPickerField<T>> {
  static const double _itemHeight = 46;
  static const Color _brown = Color(0xFF7B4E2E);

  final GlobalKey _fieldKey = GlobalKey();
  bool _open = false;

  int get _selectedIndex =>
      widget.items.indexWhere((i) => i.value == widget.value);

  String get _selectedLabel {
    final i = _selectedIndex;
    return i < 0 ? '' : widget.items[i].label;
  }

  Future<void> _openPicker() async {
    if (widget.items.isEmpty) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final media = MediaQuery.of(context);
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screenH = media.size.height;
    final spaceBelow = screenH -
        media.viewInsets.bottom -
        media.padding.bottom -
        (origin.dy + size.height) -
        12;
    final spaceAbove = origin.dy - media.padding.top - 12;
    final openUp = spaceBelow < 200 && spaceAbove > spaceBelow;
    final maxOuter =
        (openUp ? spaceAbove : spaceBelow).clamp(120.0, 360.0).toDouble();
    final contentH = (widget.items.length * _itemHeight)
        .clamp(0.0, maxOuter - 12)
        .toDouble();
    final selIndex = _selectedIndex;
    final maxScroll = (widget.items.length * _itemHeight - contentH)
        .clamp(0.0, double.infinity)
        .toDouble();
    final initialOffset = selIndex < 0
        ? 0.0
        : (selIndex * _itemHeight - contentH / 2 + _itemHeight / 2)
            .clamp(0.0, maxScroll)
            .toDouble();

    setState(() => _open = true);
    final picked = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: widget.label,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 170),
      transitionBuilder: (ctx, anim, secondary, child) => child,
      pageBuilder: (ctx, anim, secondary) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned(
                left: origin.dx,
                width: size.width,
                top: openUp ? null : origin.dy + size.height + 6,
                bottom: openUp ? screenH - origin.dy + 6 : null,
                child: FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    alignment:
                        openUp ? Alignment.bottomCenter : Alignment.topCenter,
                    scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                    child: LiquidGlassSurface(
                      borderRadius: BorderRadius.circular(18),
                      sigma: 18,
                      backgroundColor:
                          const Color(0xFFFFFDF8).withValues(alpha: 0.78),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: SizedBox(
                        height: contentH,
                        child: ListView.builder(
                          controller: ScrollController(
                            initialScrollOffset: initialOffset,
                          ),
                          padding: EdgeInsets.zero,
                          itemExtent: _itemHeight,
                          itemCount: widget.items.length,
                          itemBuilder: (_, i) => _buildItem(ctx, i, selIndex),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged(picked);
  }

  Widget _buildItem(BuildContext ctx, int i, int selIndex) {
    final item = widget.items[i];
    final selected = i == selIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected ? _brown.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(ctx).pop(item.value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.fontSize + 1,
                      fontWeight: selected ? FontWeight.w700 : widget.fontWeight,
                      color: const Color(0xFF2D241C),
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_rounded, size: 18, color: _brown),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDCCBB8)),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openPicker,
      child: Container(
        key: _fieldKey,
        child: InputDecorator(
          isFocused: _open,
          isEmpty: _selectedLabel.isEmpty,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: const TextStyle(
              color: Color(0xFF6C5946),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: border,
            enabledBorder: border,
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _brown),
            ),
            prefixIcon: Icon(widget.icon, color: _brown, size: 20),
            suffixIcon: AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 170),
              child: const Icon(
                Icons.arrow_drop_down,
                color: Color(0xFF6C5946),
              ),
            ),
          ),
          child: Text(
            _selectedLabel,
            maxLines: widget.maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: widget.fontWeight,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}
