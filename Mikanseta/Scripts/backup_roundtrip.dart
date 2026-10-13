import 'dart:io';

import 'package:mikanseta/src/domain.dart';

void main(List<String> args) {
  final imported = Archive.decode(File(args[0]).readAsStringSync());
  final entries =
      imported.entries
          .map(
            (e) => e.kind == EntryKind.homework
                ? e.change({'title': '${e.title}（Flutter 编辑）'})
                : e,
          )
          .toList()
        ..add(Entry.create(title: 'Flutter 新增'));
  final exported = Archive(entries: []).merge(imported.withEntries(entries));
  File(args[1]).writeAsStringSync(exported.encode());
}
