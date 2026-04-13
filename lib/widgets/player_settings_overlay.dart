import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:caffeine_tv/widgets/language_picker_dialog.dart';

class PlayerSettingsOverlay extends StatefulWidget {
  final BetterPlayerController controller;
  final String? currentProvider;
  final List<Map<String, String>>? allProviders;
  final Function(String)? onChangeProvider;
  final Function(String)? onSearchMore;
  final String providerLabel;

  const PlayerSettingsOverlay({
    super.key, 
    required this.controller,
    this.currentProvider,
    this.allProviders,
    this.onChangeProvider,
    this.onSearchMore,
    this.providerLabel = 'Server (Provider)',
  });

  @override
  State<PlayerSettingsOverlay> createState() => _PlayerSettingsOverlayState();
}

class _PlayerSettingsOverlayState extends State<PlayerSettingsOverlay> {
  @override
  Widget build(BuildContext context) {
    final audioTracks = widget.controller.betterPlayerAsmsAudioTracks ?? [];
    final subtitleSources = widget.controller.betterPlayerSubtitlesSourceList;
    final currentAudio = widget.controller.betterPlayerAsmsAudioTrack;
    final currentSubtitle = widget.controller.betterPlayerSubtitlesSource;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12), 
                width: 1.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Player Options',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  if (audioTracks.isNotEmpty) ...[
                    const _CategoryHeader(title: 'Audio Language'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: audioTracks.map((track) {
                        final isSelected = currentAudio == track;
                        return _TrackChip(
                          label: track.label ?? track.language ?? 'Unknown',
                          isSelected: isSelected,
                          onPressed: () {
                            widget.controller.setAudioTrack(track);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 48),
                  ],
                  if (subtitleSources.isNotEmpty) ...[
                    const _CategoryHeader(title: 'Subtitles'),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: subtitleSources.map((source) {
                        final isSelected = currentSubtitle == source;
                        final name = source.name ?? 'Unknown';
                        return _TrackChip(
                          label: name == 'Default subtitles' && source.type == BetterPlayerSubtitlesSourceType.none 
                              ? 'Off' 
                              : name,
                          isSelected: isSelected,
                          onPressed: () {
                            widget.controller.setupSubtitleSource(source);
                            setState(() {});
                          },
                        );
                      }).toList(),
                    ),
                    if (widget.onSearchMore != null) ...[
                      const SizedBox(height: 16),
                      _TrackChip(
                        label: '+ Search More Languages',
                        isSelected: false,
                        isAction: true,
                        onPressed: () async {
                          final langCode = await showDialog<String>(
                            context: context,
                            builder: (context) => const LanguagePickerDialog(),
                          );
                          if (langCode != null) {
                            widget.onSearchMore!(langCode);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ],
                  if (widget.onChangeProvider != null && widget.allProviders != null && widget.allProviders!.isNotEmpty) ...[
                    const SizedBox(height: 48),
                    _CategoryHeader(title: widget.providerLabel),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: widget.allProviders!.map((provider) {
                        final isSelected = widget.currentProvider == provider['code'];
                        return _TrackChip(
                          label: provider['name'] ?? 'Unknown',
                          isSelected: isSelected,
                          onPressed: () {
                            if (!isSelected) {
                              widget.onChangeProvider!(provider['code']!);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 48),
                  const _CategoryHeader(title: 'Subtitle Sync'),
                  const SizedBox(height: 12),
                  Text(
                    'Current Offset: ${(widget.controller.betterPlayerSubtitlesSource?.offset ?? 0) / 1000}s',
                    style: const TextStyle(
                      color: Colors.white60, 
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      _TrackChip(
                        label: '-1.0s',
                        isSelected: false,
                        isAction: true,
                        onPressed: () {
                          final currentOffset = widget.controller.betterPlayerSubtitlesSource?.offset ?? 0;
                          widget.controller.setSubtitleOffset(currentOffset - 1000);
                          setState(() {});
                        },
                      ),
                      _TrackChip(
                        label: '-0.1s',
                        isSelected: false,
                        isAction: true,
                        onPressed: () {
                          final currentOffset = widget.controller.betterPlayerSubtitlesSource?.offset ?? 0;
                          widget.controller.setSubtitleOffset(currentOffset - 100);
                          setState(() {});
                        },
                      ),
                      _TrackChip(
                        label: 'Reset',
                        isSelected: false,
                        isAction: true,
                        onPressed: () {
                          widget.controller.setSubtitleOffset(0);
                          setState(() {});
                        },
                      ),
                      _TrackChip(
                        label: '+0.1s',
                        isSelected: false,
                        isAction: true,
                        onPressed: () {
                          final currentOffset = widget.controller.betterPlayerSubtitlesSource?.offset ?? 0;
                          widget.controller.setSubtitleOffset(currentOffset + 100);
                          setState(() {});
                        },
                      ),
                      _TrackChip(
                        label: '+1.0s',
                        isSelected: false,
                        isAction: true,
                        onPressed: () {
                          final currentOffset = widget.controller.betterPlayerSubtitlesSource?.offset ?? 0;
                          widget.controller.setSubtitleOffset(currentOffset + 1000);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  const _CategoryHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
      ),
    );
  }
}

class _TrackChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final bool isAction;

  const _TrackChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.isAction = false,
  });

  @override
  State<_TrackChip> createState() => _TrackChipState();
}

class _TrackChipState extends State<_TrackChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = (double v) => (v * MediaQuery.of(context).size.width) / 1920;
    
    // Background color logic
    Color bgColor;
    if (widget.isSelected) {
      bgColor = const Color(0xFFE60000); // Marvel Red
    } else if (_focused) {
      bgColor = Colors.white;
    } else {
      bgColor = Colors.white.withValues(alpha: 0.05);
    }
    
    // Text color logic
    Color textColor;
    if (widget.isSelected) {
      textColor = Colors.white;
    } else if (_focused) {
      textColor = Colors.black;
    } else {
      textColor = Colors.white70;
    }

    return Focus(
      onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(horizontal: s(32), vertical: s(16)),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.1),
              width: _focused ? 2 : 1,
            ),
            boxShadow: _focused ? [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.25),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ] : [],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontWeight: widget.isSelected || _focused ? FontWeight.w900 : FontWeight.w600,
              fontSize: 17,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
