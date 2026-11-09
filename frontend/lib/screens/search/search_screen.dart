import 'package:flutter/material.dart';

import '../../models/feature_catalog.dart';
import '../../widgets/state_views.dart';
import '../modules/module_screen.dart';

/// Searches app features. Searching the user's own records is added with feature 38.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? <HealthFeature>[]
        : allFeatures
            .where((f) => isListedFeature(f) && f.title.toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search features, e.g. "medicine"',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: q.isEmpty
          ? const EmptyView(
              icon: Icons.search,
              title: 'Search the app',
              message: 'Type a word to find a health feature.',
            )
          : results.isEmpty
              ? EmptyView(icon: Icons.search_off, title: 'No results', message: 'Nothing matches "$_query".')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => FeatureTile(feature: results[i]),
                ),
    );
  }
}
