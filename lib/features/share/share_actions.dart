import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/file_download.dart';
import '../../state/project_controller.dart';
import '../../state/project_library.dart';
import 'share_pages.dart';

void _say(BuildContext context, String m) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

Future<void> _problem(BuildContext context, String message) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Could not import'),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

/// Phones and desktops: the system share sheet with a file. Browsers download the file; if the
/// browser refuses, the text is copied so it can be pasted into Import > Paste instead.
Future<void> shareTextFile(
  BuildContext context,
  String text,
  String fileName,
  String subject, {
  String mimeType = 'application/json',
}) async {
  if (kIsWeb) {
    if (await downloadTextFile(fileName, text, mimeType: mimeType)) {
      _say(context, 'Saved $fileName to your downloads.');
    } else {
      await Clipboard.setData(ClipboardData(text: text));
      _say(context, 'The browser would not save a file, so the text was copied instead.');
    }
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(text, flush: true);
  await Share.shareXFiles([XFile(file.path, mimeType: mimeType)], subject: subject);
}

/// Checks the text, then adds it as a new local project.
Future<void> importText(BuildContext context, ProjectLibrary lib, String text, VoidCallback onOpened) async {
  try {
    final doc = await parseShared(text);
    await lib.importShared(doc);
    onOpened();
    _say(context, 'Imported "${doc.name}"');
  } on FormatException catch (e) {
    await _problem(context, e.message);
  } catch (_) {
    await _problem(context, 'The project could not be saved on this device.');
  }
}

Future<void> shareProjectFile(BuildContext context, ProjectLibrary lib, String id) async {
  try {
    final doc = await lib.docFor(id);
    if (doc == null) return _say(context, 'That project could not be found.');
    final safe = doc.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await shareTextFile(context, jsonEncode(doc.toJson()), '$safe.ductletor', doc.name);
  } catch (e) {
    _say(context, 'Could not share the project: $e');
  }
}

Future<void> showProjectQr(BuildContext context, ProjectLibrary lib, String id) async {
  final doc = await lib.docFor(id);
  if (doc == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ProjectQrPage(doc: doc, onShareFile: () => shareProjectFile(context, lib, id)),
  ));
}

Future<void> importFromFile(BuildContext context, ProjectLibrary lib, VoidCallback onOpened) async {
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.size > maxSharedBytes) return _problem(context, 'That file is too large to be a project.');
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    final text = utf8.decode(bytes);
    if (!context.mounted) return;
    await importText(context, lib, text, onOpened);
  } on FormatException {
    await _problem(context, 'That file is not a Ductletor project.');
  } catch (e) {
    await _problem(context, 'Could not open the file: $e');
  }
}

Future<void> importFromScan(BuildContext context, ProjectLibrary lib, VoidCallback onOpened) async {
  final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
  if (code == null || !context.mounted) return;
  await importText(context, lib, code, onOpened);
}

Future<void> importFromPaste(BuildContext context, ProjectLibrary lib, VoidCallback onOpened) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  final ctl = TextEditingController(text: (clip.trim().startsWith('DUCT1:') || clip.trim().startsWith('{')) ? clip.trim() : '');
  if (!context.mounted) return;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paste project code'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: 4,
        decoration: const InputDecoration(hintText: 'DUCT1:... or project text'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Import')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importText(context, lib, text, onOpened);
}

// ---- fitting library files ----

Future<void> shareLibraryFile(BuildContext context, ProjectController c) async {
  try {
    if (c.library.isEmpty) return _say(context, 'The fitting library is empty.');
    final safe = c.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await shareTextFile(context, encodeLibraryFile(c.library, name: c.name), '$safe-fittings.ductlib', '${c.name} fittings');
  } catch (e) {
    _say(context, 'Could not share the library: $e');
  }
}

Future<void> importLibraryFromFile(BuildContext context, ProjectController c) async {
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.single;
    if (f.size > maxSharedBytes) return _problem(context, 'That file is too large to be a fitting library.');
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    final text = utf8.decode(bytes);
    if (!context.mounted) return;
    await importLibraryText(context, c, text);
  } on FormatException {
    await _problem(context, 'That file is not a Ductletor fitting library.');
  } catch (e) {
    await _problem(context, 'Could not open the file: $e');
  }
}

/// Checks the text, asks what to do about name clashes, then merges it into the project library.
Future<void> importLibraryText(BuildContext context, ProjectController c, String text) async {
  try {
    final incoming = parseLibraryFile(text);
    final clashes = c.countLibraryConflicts(incoming);
    var overwrite = false;
    if (clashes > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some fittings already exist'),
          content: Text('$clashes of ${incoming.length} fittings have the same name and code as ones in this project.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep mine')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Replace with imported')),
          ],
        ),
      );
      if (choice == null) return;
      overwrite = choice;
    }
    final r = c.importLibrary(incoming, overwrite: overwrite);
    _say(context, 'Library import: added ${r.added}, replaced ${r.replaced}, skipped ${r.skipped}');
  } on FormatException catch (e) {
    await _problem(context, e.message);
  }
}

Future<void> importLibraryFromPaste(BuildContext context, ProjectController c) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  final ctl = TextEditingController(text: clip.trim().startsWith('{') ? clip.trim() : '');
  if (!context.mounted) return;
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Paste fitting library'),
      content: TextField(controller: ctl, autofocus: true, maxLines: 5, decoration: const InputDecoration(hintText: 'Library text')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Import')),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  await importLibraryText(context, c, text);
}
