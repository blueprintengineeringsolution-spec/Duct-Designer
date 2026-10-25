import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/projects/presentation/providers/project_library_notifier.dart';

/// Opens local storage and the first project. Loading until done; an error if storage can't be opened.
final appStartupProvider = FutureProvider<void>((ref) => ref.read(projectLibraryProvider.notifier).init());
