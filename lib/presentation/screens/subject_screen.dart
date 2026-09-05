import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/domain_model.dart';
import 'quiz_start_screen.dart';
import 'sub_level_screen.dart';

/// Subject list for one domain. Domains can hold 10-50 subjects, so this
/// screen leads with a search box that filters as you type — scrolling a
/// 50-card grid to find "Chemistry" isn't reasonable.
class SubjectScreen extends ConsumerStatefulWidget {
  final DomainModel domain;
  const SubjectScreen({super.key, required this.domain});

  @override
  ConsumerState<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends ConsumerState<SubjectScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Hidden subjects (isActive: false) never show to regular users.
    final all = widget.domain.subjects.where((s) => s.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final subjects = _query.isEmpty
        ? all
        : all.where((s) => s.name.toLowerCase().contains(_query)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.domain.name)),
      body: Column(
        children: [
          // Search — only worth showing once there are enough subjects that
          // scanning the grid becomes tedious.
          if (all.length >= 8)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search ${all.length} subjects...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('No subjects in this domain yet.'))
                : subjects.isEmpty
                    ? Center(child: Text('No subjects match "$_query".'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: subjects.length,
                        itemBuilder: (context, i) =>
                            _subjectCard(theme, subjects[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _subjectCard(ThemeData theme, SubjectModel s) {
    final hasSubLevels = s.subLevels.any((sl) => sl.isActive);
    // A shared subject may have sub-levels contributed by OTHER domains too,
    // so it always routes through SubLevelScreen, which merges them.
    final routesToSubLevels = hasSubLevels || s.isShared;

    return Card(
      elevation: 2,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => routesToSubLevels
              ? SubLevelScreen(domain: widget.domain, subject: s)
              : QuizStartScreen(
                  domainId: widget.domain.id,
                  domainName: widget.domain.name,
                  subjectId: s.id,
                  subjectName: s.name,
                  isShared: s.isShared,
                ),
        )),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      routesToSubLevels
                          ? Icons.folder_open_rounded
                          : Icons.menu_book_rounded,
                      color: theme.colorScheme.primary,
                      size: 30),
                  const Spacer(),
                  if (s.isShared)
                    Tooltip(
                      message: 'Shared question pool across domains',
                      child: Icon(Icons.hub_rounded,
                          size: 16, color: theme.hintColor),
                    ),
                ],
              ),
              const Spacer(),
              Text(s.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
