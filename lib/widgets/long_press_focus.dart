import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class LongPressFocus extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final bool autofocus;
  final bool descendantsAreFocusable;

  const LongPressFocus({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.focusNode,
    this.onFocusChange,
    this.onKeyEvent,
    this.autofocus = false,
    this.descendantsAreFocusable = true,
  });

  @override
  State<LongPressFocus> createState() => _LongPressFocusState();
}

class _LongPressFocusState extends State<LongPressFocus> {
  Timer? _longPressTimer;
  bool _isLongPress = false;

  void _handleKeyDown(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
      if (_longPressTimer != null) return;
      _isLongPress = false;
      _longPressTimer = Timer(const Duration(milliseconds: 700), () {
        _isLongPress = true;
        HapticFeedback.heavyImpact();
        widget.onLongPress?.call();
      });
    }
  }

  void _handleKeyUp(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      if (!_isLongPress) {
        widget.onTap?.call();
      }
    }
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      descendantsAreFocusable: widget.descendantsAreFocusable,
      onFocusChange: widget.onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          _handleKeyDown(event.logicalKey);
        } else if (event is KeyUpEvent) {
          _handleKeyUp(event.logicalKey);
        }

        if (widget.onKeyEvent != null) {
          final result = widget.onKeyEvent!(node, event);
          if (result != KeyEventResult.ignored) return result;
        }

        if (event.logicalKey == LogicalKeyboardKey.enter || 
            event.logicalKey == LogicalKeyboardKey.select) {
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      ),
    );
  }
}
