// lib/widgets/trending_chips.dart
import 'package:flutter/material.dart';
import '../models.dart';

class TrendingChips extends StatelessWidget {
  final List<TrendingKeyword> keywords;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const TrendingChips({
    super.key,
    required this.keywords,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          const SizedBox(width: 8),
          ...keywords.map((k) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(k.keyword),
              selected: selected == k.keyword,
              onSelected: (_) => onSelect(k.keyword),
            ),
          )),
        ],
      ),
    );
  }
}
