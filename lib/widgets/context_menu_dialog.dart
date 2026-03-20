import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

class ContextMenuDialog extends StatelessWidget {
  final String title;
  final List<ContextMenuItem> items;
  final double Function(double) s;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required List<ContextMenuItem> items,
    required double Function(double) s,
  }) {
    return showDialog(
      context: context,
      builder: (context) => ContextMenuDialog(
        title: title,
        items: items,
        s: s,
      ),
    );
  }

  const ContextMenuDialog({
    super.key,
    required this.title,
    required this.items,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: s(400)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(s(24)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: s(1.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: s(40),
                  spreadRadius: s(5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.all(s(24)),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: s(28),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: Colors.white10, height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      return _ContextMenuItemWidget(
                        item: items[index],
                        s: s,
                        isFirst: index == 0,
                        isLast: index == items.length - 1,
                      );
                    },
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

class ContextMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const ContextMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
  });
}

class _ContextMenuItemWidget extends StatefulWidget {
  final ContextMenuItem item;
  final double Function(double) s;
  final bool isFirst;
  final bool isLast;

  const _ContextMenuItemWidget({
    required this.item,
    required this.s,
    required this.isFirst,
    required this.isLast,
  });

  @override
  State<_ContextMenuItemWidget> createState() => _ContextMenuItemWidgetState();
}

class _ContextMenuItemWidgetState extends State<_ContextMenuItemWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Focus(
      autofocus: widget.isFirst,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.item.onTap();
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          widget.item.onTap();
          Navigator.of(context).pop();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(20)),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                color: _isFocused ? Colors.black : (widget.item.color ?? Colors.white70),
                size: s(28),
              ),
              SizedBox(width: s(24)),
              Text(
                widget.item.label,
                style: TextStyle(
                  color: _isFocused ? Colors.black : Colors.white,
                  fontSize: s(22),
                  fontWeight: _isFocused ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
