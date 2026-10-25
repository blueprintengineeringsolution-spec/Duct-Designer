import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/file_project_data_source.dart';
import '../../data/prefs_project_data_source.dart';
import '../../data/project_data_source.dart';
import '../../data/project_repository_impl.dart';
import '../../domain/project_repository.dart';
import '../../domain/project_use_cases.dart';

/// Browser storage on the web, one file per project everywhere else.
final projectDataSourceProvider = Provider<ProjectDataSource>((ref) {
  if (kIsWeb) return PrefsProjectDataSource(); // path_provider has no web version
  return FileProjectDataSource.lazy(() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}projects');
  });
});

final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => ProjectRepositoryImpl(ref.watch(projectDataSourceProvider)),
);

/// How long to wait after an edit before saving.
final saveDebounceProvider = Provider<Duration>((ref) => const Duration(milliseconds: 600));

final listProjectsProvider = Provider<ListProjects>((ref) => ListProjects(ref.watch(projectRepositoryProvider)));
final loadProjectProvider = Provider<LoadProject>((ref) => LoadProject(ref.watch(projectRepositoryProvider)));
final deleteProjectProvider = Provider<DeleteProject>((ref) => DeleteProject(ref.watch(projectRepositoryProvider)));
final createProjectProvider = Provider<CreateProject>((ref) => CreateProject(ref.watch(projectRepositoryProvider)));
final renameStoredProjectProvider =
    Provider<RenameStoredProject>((ref) => RenameStoredProject(ref.watch(projectRepositoryProvider)));
final duplicateProjectProvider =
    Provider<DuplicateProject>((ref) => DuplicateProject(ref.watch(projectRepositoryProvider)));
final importSharedProjectProvider =
    Provider<ImportSharedProject>((ref) => ImportSharedProject(ref.watch(projectRepositoryProvider)));
