import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import '../../../core/navigation/home_tab_provider.dart';
import '../../../core/utils/safe_file_name.dart';
import '../../project_editor/presentation/providers/project_editor_provider.dart';
import '../../projects/presentation/providers/project_library_notifier.dart';
import '../domain/text_file_gateway.dart';
import 'providers/share_providers.dart';
import 'share_pages.dart';

void _say(BuildContext context, String m) {
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

Future<void> _problem(BuildContext context, String message) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Could not import'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
      ],
    ),
  );
}

Future<void> _shareText(
  BuildContext context,
  TextFileGateway gateway,
  String text,
  String fileName,
  String subject, {
  String mimeType = 'application/json',
}) async {
  final outcome = await gateway.shareTextFile(
      text: text, fileName: fileName, subject: subject, mimeType: mimeType);
  switch (outcome) {
    case TextFileShareOutcome.downloaded:
      _say(context, 'Saved $fileName to your downloads.');
    case TextFileShareOutcome.copied:
      _say(context,
          'The browser would not save a file, so the text was copied instead.');
    case TextFileShareOutcome.shared:
      break;
  }
}

/// Phones and desktops: the system share sheet with a file. Browsers download the file; if the
/// browser refuses, the text is copied so it can be pasted into Import > Paste instead.
Future<void> shareTextFile(
  BuildContext context,
  WidgetRef ref,
  String text,
  String fileName,
  String subject, {
  String mimeType = 'application/json',
}) =>
    _shareText(
        context, ref.read(textFileGatewayProvider), text, fileName, subject,
        mimeType: mimeType);

/// Checks the text, then adds it as a new local project and opens it.
Future<void> importText(
    BuildContext context, WidgetRef ref, String text) async {
  final library = ref.read(projectLibraryProvider.notifier);
  final tab = ref.read(homeTabProvider.notifier);
  try {
    final doc = await parseShared(text);
    await library.importShared(doc);
    tab.select(1);
    _say(context, 'Imported "${doc.name}"');
  } on FormatException catch (e) {
    await _problem(context, e.message);
  } catch (_) {
    await _problem(context, 'The project could not be saved on this device.');
  }
}

Future<void> shareProjectFile(
    BuildContext context, WidgetRef ref, String id) async {
  final library = ref.read(projectLibraryProvider.notifier);
  final gateway = ref.read(textFileGatewayProvider);
  try {
    final doc = await library.docFor(id);
    if (doc == null) return _say(context, 'That project could not be found.');
    await _shareText(context, gateway, jsonEncode(doc.toJson()),
        '${safeFileName(doc.name)}.ductletor', doc.name);
  } catch (e) {
    _say(context, 'Could not share the project: $e');
  }
}

Future<void> showProjectQr(
    BuildContext context, WidgetRef ref, String id) async {
  final doc = await ref.read(projectLibraryProvider.notifier).docFor(id);
  if (doc == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ProjectQrPage(
        doc: doc, onShareFile: () => shareProjectFile(context, ref, id)),
  ));
}

Future<void> importFromFile(BuildContext context, WidgetRef ref) async {
  final gateway = ref.read(textFileGatewayProvider);
  try {
    final f = await gateway.pickFile();
    if (f == null) return;
    if (f.size > maxSharedBytes)
      return _problem(context, 'That file is too large to be a project.');
    final text = utf8.decode(await f.readBytes());
    if (!context.mounted) return;
    await importText(context, ref, text);
  } on FormatException {
    await _problem(context, 'That file is not a Ductletor project.');
  } catch (e) {
    await _problem(context, 'Could not open the file: $e');
  }
}

Future<void> importFromScan(BuildContext context, WidgetRef ref) async {
  final code = await Navigator.of(context)
      .push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
  if (code == null || !context.mounted) return;
  await importText(context, ref, code);
}

Future<void> importFromPaste(BuildContext context, WidgetRef ref) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  final ctl = TextEditingController(
      text: (clip.trim().startsWith('DUCT1:') || clip.trim().startsWith('{'))
          ? clip.trim()
          : '');
  if (!context.mounted) return;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paste project code'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: 4,
        decoration:
            const InputDecoration(hintText: 'DUCT1:... or project text'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('Import')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importText(context, ref, text);
}

// ---- fitting library files ----

Future<void> shareLibraryFile(BuildContext context, WidgetRef ref) async {
  final gateway = ref.read(textFileGatewayProvider);
  try {
    final c = ref.read(currentProjectProvider);
    if (c.library.isEmpty)
      return _say(context, 'The fitting library is empty.');
    await _shareText(
      context,
      gateway,
      encodeLibraryFile(c.library, name: c.name),
      '${safeFileName(c.name)}-fittings.ductlib',
      '${c.name} fittings',
    );
  } catch (e) {
    _say(context, 'Could not share the library: $e');
  }
}

Future<void> importLibraryFromFile(BuildContext context, WidgetRef ref) async {
  final gateway = ref.read(textFileGatewayProvider);
  try {
    final f = await gateway.pickFile();
    if (f == null) return;
    if (f.size > maxSharedBytes)
      return _problem(
          context, 'That file is too large to be a fitting library.');
    final text = utf8.decode(await f.readBytes());
    if (!context.mounted) return;
    await importLibraryText(context, ref, text);
  } on FormatException {
    await _problem(context, 'That file is not a Ductletor fitting library.');
  } catch (e) {
    await _problem(context, 'Could not open the file: $e');
  }
}

/// Checks the text, asks what to do about name clashes, then merges it into the project library.
Future<void> importLibraryText(
    BuildContext context, WidgetRef ref, String text) async {
  try {
    final incoming = parseLibraryFile(text);
    final clashes =
        ref.read(currentProjectProvider).countLibraryConflicts(incoming);
    var overwrite = false;
    if (clashes > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some fittings already exist'),
          content: Text(
              '$clashes of ${incoming.length} fittings have the same name and code as ones in this project.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep mine')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace with imported')),
          ],
        ),
      );
      if (choice == null) return;
      overwrite = choice;
    }
    final r = ref
        .read(projectEditorProvider.notifier)
        .importLibrary(incoming, overwrite: overwrite);
    _say(context,
        'Library import: added ${r.added}, replaced ${r.replaced}, skipped ${r.skipped}');
  } on FormatException catch (e) {
    await _problem(context, e.message);
  }
}

Future<void> importLibraryFromPaste(BuildContext context, WidgetRef ref) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  final ctl = TextEditingController(
      text: clip.trim().startsWith('{') ? clip.trim() : '');
  if (!context.mounted) return;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paste fitting library'),
      content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Library text')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('Import')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importLibraryText(context, ref, text);
}
