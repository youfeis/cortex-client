import 'dart:convert';
import 'package:rfw/formats.dart';

/// Layouts can compose these native capabilities, but cannot add executable code.
const layoutSlots = <String, Set<String>>{
  'space': {'time', 'fitness', 'money', 'targets'},
  'fitness': {
    'intro',
    'goal',
    'energy',
    'foodPhoto',
    'checkIn',
    'movement',
    'health',
    'meals',
    'readings',
    'chat',
  },
  'time': {'intro', 'todos', 'plan', 'routines', 'calendars', 'chat'},
  'chat': {'divider', 'login', 'conversation', 'error', 'composer'},
  'composer': {'images', 'input', 'actions'},
  'userMessage': {'content'},
  'assistantMessage': {'content'},
};

class LayoutRelease {
  final Map<String, dynamic> document;
  final Map<String, RemoteWidgetLibrary> libraries;
  String get revision => document['revision'] as String;
  LayoutRelease._(this.document, this.libraries);

  factory LayoutRelease.parse(String json) {
    if (utf8.encode(json).length > 65536) {
      throw const FormatException('Layout too large');
    }
    final doc = jsonDecode(json) as Map<String, dynamic>;
    if (doc['schema'] != 1 ||
        doc['revision'] is! String ||
        !RegExp(r'^[a-zA-Z0-9._-]{1,80}$').hasMatch(doc['revision'])) {
      throw const FormatException('Unsupported layout release');
    }
    final pages = doc['pages'] as Map<String, dynamic>;
    if (pages.length != layoutSlots.length) {
      throw const FormatException('Missing pages');
    }
    final libraries = <String, RemoteWidgetLibrary>{};
    for (final page in layoutSlots.keys) {
      final root = pages[page] as Map<String, dynamic>;
      final expectedRoot = switch (page) {
        'chat' || 'composer' => 'column',
        'userMessage' || 'assistantMessage' => 'bubble',
        _ => 'list',
      };
      if (root['type'] != expectedRoot) {
        throw const FormatException('Invalid page layout');
      }
      final seen = <String>{};
      var count = 0;
      String compile(dynamic value, int depth) {
        if (depth > 6 || ++count > 80) {
          throw const FormatException('Layout too complex');
        }
        final n = value as Map<String, dynamic>;
        final type = n['type'];
        const fields = {
          'type',
          'name',
          'children',
          'text',
          'size',
          'height',
          'padding',
          'radius',
          'tone',
          'align',
          'width',
          'columns',
          'gap',
          'ratio',
        };
        if (n.keys.any((k) => !fields.contains(k))) {
          throw const FormatException('Unknown layout field');
        }
        const types = {
          'slot',
          'column',
          'list',
          'grid',
          'surface',
          'text',
          'gap',
          'bubble',
        };
        if (!types.contains(type)) {
          throw const FormatException('Unknown component');
        }
        if (type == 'list' && depth != 0 ||
            type == 'bubble' && depth != 0 ||
            type == 'grid' && page != 'space') {
          throw const FormatException('Invalid nesting');
        }
        if (page == 'chat' && depth > 0 && type != 'slot') {
          throw const FormatException('Chat controls must remain reachable');
        }
        if (type == 'slot') {
          if (!layoutSlots[page]!.contains(n['name']) ||
              !seen.add(n['name'] as String)) {
            throw const FormatException('Unknown or repeated native slot');
          }
          return 'Slot(name: ${jsonEncode(n['name'])})';
        }
        for (final key in [
          'size',
          'height',
          'padding',
          'radius',
          'width',
          'columns',
          'gap',
          'ratio',
        ]) {
          if (!n.containsKey(key)) continue;
          final v = n[key];
          final (min, max) = switch (key) {
            'size' => (11, 32),
            'width' => (.65, 1),
            'ratio' => (.55, 1.2),
            'columns' => (1, 2),
            _ => (0, 40),
          };
          if (v is! num ||
              !v.isFinite ||
              v < min ||
              v > max ||
              key == 'columns' && v is! int) {
            throw const FormatException('Invalid layout measurement');
          }
        }
        if (n.containsKey('tone') &&
                !{'soft', 'white', 'paper'}.contains(n['tone']) ||
            n.containsKey('align') && !{'left', 'right'}.contains(n['align'])) {
          throw const FormatException('Unknown layout token');
        }
        if (type == 'text' &&
            (n['text'] is! String || (n['text'] as String).length > 500)) {
          throw const FormatException('Invalid label');
        }
        final args = <String>[];
        for (final entry in n.entries) {
          if (entry.key == 'type') {
            continue;
          }
          if (entry.key == 'children') {
            final children = entry.value as List;
            if (type == 'grid' && children.any((c) => c['type'] != 'slot')) {
              throw const FormatException('Grid cells must be native cards');
            }
            args.add(
              'children: [${children.map((c) => compile(c, depth + 1)).join(',')}]',
            );
          } else {
            args.add('${entry.key}: ${jsonEncode(entry.value)}');
          }
        }
        if ({'column', 'list', 'grid', 'surface', 'bubble'}.contains(type) &&
            n['children'] is! List) {
          throw const FormatException('Missing children');
        }
        return '${(type as String)[0].toUpperCase()}${type.substring(1)}(${args.join(',')})';
      }

      final source = compile(root, 0);
      if (!seen.containsAll(layoutSlots[page]!)) {
        throw const FormatException('Missing native controls');
      }
      libraries[page] = parseLibraryFile(
        'import cortex; widget root = $source;',
      );
    }
    return LayoutRelease._(doc, libraries);
  }
}
