import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reelriot_tv/utils/tv_keys.dart';
import '../models/sub_languages.dart';

class LanguagePickerDialog extends StatefulWidget {
  const LanguagePickerDialog({super.key});

  @override
  State<LanguagePickerDialog> createState() => _LanguagePickerDialogState();
}

class _LanguagePickerDialogState extends State<LanguagePickerDialog> {
  final ScrollController _scrollController = ScrollController();
  int _focusedIndex = -1;

  @override
  Widget build(BuildContext context) {
    // Filter out empty language (index 0)
    final languages = supportedLanguages.where((l) => l.languageCode.isNotEmpty).toList();

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Language',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: languages.length,
                    itemBuilder: (context, index) {
                      final lang = languages[index];
                      return _LanguageItem(
                        language: lang,
                        isFocused: _focusedIndex == index,
                        onFocusChange: (focused) {
                          if (focused) {
                            setState(() => _focusedIndex = index);
                          }
                        },
                        onTap: () => Navigator.of(context).pop(lang.languageCode),
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

class _LanguageItem extends StatefulWidget {
  final SubLanguages language;
  final bool isFocused;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;

  const _LanguageItem({
    required this.language,
    required this.isFocused,
    required this.onFocusChange,
    required this.onTap,
  });

  @override
  State<_LanguageItem> createState() => _LanguageItemState();
}

class _LanguageItemState extends State<_LanguageItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.isFocused || _isHovered;

    return Focus(
      onFocusChange: widget.onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && TvKeys.isSelect(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  widget.language.englishName,
                  style: TextStyle(
                    color: isActive ? Colors.black : Colors.white,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  const Icon(
                    Icons.language,
                    color: Colors.black,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
