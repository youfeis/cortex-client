import 'dart:io';
import 'package:cortex/remote_ui/layout_release.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_layout.dart RELEASE.json');
    exitCode = 1;
    return;
  }
  final release = LayoutRelease.parse(File(args.single).readAsStringSync());
  stdout.writeln(
    'Valid UI ${release.revision}: ${release.libraries.length} layouts',
  );
}
