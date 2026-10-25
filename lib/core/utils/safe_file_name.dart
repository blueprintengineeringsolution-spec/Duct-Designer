/// Turns a project name into something safe to use as a file name.
String safeFileName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
