import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import '../providers/database_provider.dart';
import 'subject_screen.dart';
import 'quiz_start_screen.dart';
import 'sub_level_screen.dart';

/// One flat searchable entry (a domain, subject, or sub-level).
class _Hit {
  final String label;
  final String path; // breadcrumb, e.g. "SSC CGL"
  final IconData icon;
  final VoidCallback onTap;
  _Hit(this.label, this.path, this.icon, this.onTap);
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  List<_Hit> _buildHits(List<DomainModel> domains, BuildContext context) {
    final hits = <_Hit>[];
    for (final d in domains.where((d) => d.isActive)) {
      hits.add(_Hit(d.name, 'Domain', Icons.category_rounded, () {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SubjectScreen(domain: d)));
      }));
      for (final s in d.subjects.where((s) => s.isActive)) {
        // Shared subjects route through SubLevelScreen too, since their
        // sub-levels may be contributed by other domains.
        final hasSub = s.subLevels.any((sl) => sl.isActive) || s.isShared;
        hits.add(_Hit(s.name, d.name, Icons.menu_book_rounded, () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => hasSub
                ? SubLevelScreen(domain: d, subject: s)
                : QuizStartScreen(
                    domainId: d.id,
                    domainName: d.name,
                    subjectId: s.id,
                    subjectName: s.name,
                    isShared: s.isShared,
                  ),
          ));
        }));
        for (final sl in s.subLevels.where((sl) => sl.isActive)) {
          hits.add(_Hit(sl.name, '${d.name} • ${s.name}', Icons.label_rounded,
              () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => QuizStartScreen(
                domainId: d.id,
                domainName: d.name,
                subjectId: s.id,
                subjectName: s.name,
                subLevelId: sl.id,
                subLevelName: sl.name,
                isShared: s.isShared,
              ),
            ));
          }));
        }
      }
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(domainsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search domains, subjects, topics...',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      ),
      body: domainsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (domains) {
          final all = _buildHits(domains, context);
          final results = _query.isEmpty
              ? <_Hit>[]
              : all
                  .where((h) => h.label.toLowerCase().contains(_query))
                  .toList();

          if (_query.isEmpty) {
            return const Center(
                child: Text('Type to search across all quiz content.'));
          }
          if (results.isEmpty) {
            return Center(child: Text('No matches for "$_query".'));
          }
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final h = results[i];
              return ListTile(
                leading: Icon(h.icon),
                title: Text(h.label),
                subtitle: Text(h.path),
                trailing: const Icon(Icons.chevron_right),
                onTap: h.onTap,
              );
            },
          );
        },
      ),
    );
  }
}
