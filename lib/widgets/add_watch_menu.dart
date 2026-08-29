import 'package:flutter/material.dart';
import 'package:reelriot_tv/widgets/context_menu_dialog.dart';

/// Trakt-style "add a watch" quick menu: lets the user pick when the watch
/// happened (just now, the media's release date, or unknown) instead of
/// always defaulting to "now". "Other date" (custom backdating) is
/// intentionally omitted — a D-pad-navigable date picker is a disproportionate
/// build for a remote-control interface.
class AddWatchMenu {
  static void show({
    required BuildContext context,
    required String title,
    required double Function(double) s,
    DateTime? releaseDate,
    required void Function({DateTime? watchedAt, bool unknownDate}) onPick,
  }) {
    ContextMenuDialog.show(
      context: context,
      title: title,
      s: s,
      items: [
        ContextMenuItem(
          label: 'Just Now',
          icon: Icons.bolt_rounded,
          onTap: () => onPick(watchedAt: DateTime.now()),
        ),
        if (releaseDate != null)
          ContextMenuItem(
            label: 'Release Date',
            icon: Icons.event_rounded,
            onTap: () => onPick(watchedAt: releaseDate),
          ),
        ContextMenuItem(
          label: 'Unknown Date',
          icon: Icons.help_outline_rounded,
          onTap: () => onPick(unknownDate: true),
        ),
      ],
    );
  }
}
