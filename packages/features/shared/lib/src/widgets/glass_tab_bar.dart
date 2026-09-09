import 'dart:ui' show ImageFilter;

import 'package:features_shared/src/theme/tokens.dart';
import 'package:flutter/material.dart';

/// One destination of [GlassTabBar].
class GlassTab {
  const GlassTab({required this.icon, required this.label, this.key});

  final IconData icon;
  final String label;
  final Key? key;
}

/// Floating "liquid glass" tab bar: a 64 px pill inset 16 px from the
/// edges, a backdrop blur, a hairline with a highlight on top and a soft
/// shadow. Content scrolls underneath (`Scaffold.extendBody`). Its
/// preferred height includes the bottom safe area, so lists padded by
/// `MediaQuery.padding.bottom` end above it.
class GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<GlassTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const barHeight = 64.0;
  static const bottomGap = 12.0;
  static const sideInset = 16.0;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight + bottomGap);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(sideInset, 0, sideInset, bottom + bottomGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(barHeight / 2),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(barHeight / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: barHeight,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: t.glass,
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(color: t.glassLine),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _Tab(
                        key: tabs[i].key,
                        tab: tabs[i],
                        selected: i == selectedIndex,
                        onTap: () => onSelected(i),
                        labelStyle: theme.textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.labelStyle,
    super.key,
  });

  final GlassTab tab;
  final bool selected;
  final VoidCallback onTap;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.accentInk : t.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? t.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, size: 22, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
