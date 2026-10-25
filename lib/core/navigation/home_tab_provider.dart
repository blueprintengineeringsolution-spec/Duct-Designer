import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the bottom navigation tab: 0 Projects, 1 Network, 2 Report, 3 Settings.
class HomeTabNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void select(int index) => state = index;
}

final homeTabProvider = NotifierProvider<HomeTabNotifier, int>(HomeTabNotifier.new);
