import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    as selector;
import 'package:file_selector_windows/file_selector_windows.dart';
import 'package:flutter/services.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:url_launcher/url_launcher.dart';

typedef WindowsOpenFile = Future<String?> Function(bool backupOnly);
typedef WindowsSaveFile = Future<String?> Function();
typedef WindowsPickFolder = Future<String?> Function();
typedef WindowsReplaceFile = Future<void> Function(File temporary, File target);

/// Windows equivalents of the app's native document and archive methods.
///
/// Files stay outside the installation directory, so replacing or uninstalling
/// an application package does not remove the user's archive.
class WindowsNative {
  WindowsNative({
    Future<Directory> Function()? supportDirectory,
    WindowsOpenFile? openFile,
    WindowsSaveFile? saveFile,
    WindowsPickFolder? pickFolder,
    WindowsReplaceFile? replaceFile,
    Future<bool> Function(Uri)? openUrl,
  }) : _supportDirectory = supportDirectory ?? _applicationSupportDirectory,
       _openFile = openFile ?? _chooseFile,
       _saveFile = saveFile ?? _chooseSaveFile,
       _pickFolder = pickFolder ?? _chooseFolder,
       _replaceFile = replaceFile ?? _rename,
       _openUrl =
           openUrl ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  static final instance = WindowsNative();
  static const version = String.fromEnvironment(
    'MIKANSETA_VERSION',
    defaultValue: '0.5.3 (16)',
  );
  final Future<Directory> Function() _supportDirectory;
  final WindowsOpenFile _openFile;
  final WindowsSaveFile _saveFile;
  final WindowsPickFolder _pickFolder;
  final WindowsReplaceFile _replaceFile;
  final Future<bool> Function(Uri) _openUrl;
  int _temporarySequence = 0;
  static final selector.FileSelectorPlatform _selector = FileSelectorWindows();

  static Future<Directory> _applicationSupportDirectory() async {
    final path = await PathProviderWindows().getApplicationSupportPath();
    if (path == null) throw const FileSystemException('无法定位应用数据目录');
    return Directory(path);
  }

  static Future<String?> _chooseFolder() =>
      _selector.getDirectoryPathWithOptions(const selector.FileDialogOptions());

  static Future<String?> _chooseFile(bool backupOnly) async {
    final file = await _selector.openFile(
      acceptedTypeGroups: [
        selector.XTypeGroup(
          label: backupOnly ? 'Mikansei JSON 备份' : '课表或文本',
          extensions: backupOnly ? ['json'] : ['csv', 'ics', 'txt', 'json'],
        ),
      ],
    );
    return file?.path;
  }

  static Future<String?> _chooseSaveFile() async {
    final location = await _selector.getSaveLocation(
      options: const selector.SaveDialogOptions(
        suggestedName: 'Mikanseta-backup.json',
      ),
      acceptedTypeGroups: [
        const selector.XTypeGroup(label: 'JSON 备份', extensions: ['json']),
      ],
    );
    return location?.path;
  }

  static Future<void> _rename(File temporary, File target) async {
    await temporary.rename(target.path);
  }

  File _child(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  Future<File> _localFile(String name) async {
    final directory = await _supportDirectory();
    await directory.create(recursive: true);
    return _child(directory, name);
  }

  Future<String?> _readOptional(File file) async {
    try {
      return await file.readAsString();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) return null;
      // A denied or malformed archive is not a fresh installation.
      rethrow;
    }
  }

  Future<void> _writeAtomic(File target, String content) async {
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.${pid}_${DateTime.now().microsecondsSinceEpoch}_${_temporarySequence++}.tmp',
    );
    await temporary.create(exclusive: true);
    try {
      await temporary.writeAsString(content, flush: true);
      // In particular, never delete the original to work around a Windows
      // sharing violation. A failed replacement must leave it recoverable.
      await _replaceFile(temporary, target);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _text(Object? value) {
    if (value is! String) {
      throw PlatformException(code: 'arguments', message: '缺少文本内容');
    }
    return value;
  }

  Future<Directory?> _syncFolder() async {
    final text = await _readOptional(
      await _localFile('local-sync-folder.json'),
    );
    if (text == null) return null;
    final data = jsonDecode(text) as Map<String, dynamic>;
    final path = data['path'];
    if (path == null) return null;
    if (path is! String || path.isEmpty) {
      throw const FormatException('同步文件夹设置无效，请重新选择');
    }
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw FileSystemException('同步文件夹不可用，请重新选择', path);
    }
    return directory;
  }

  Future<Directory> _replicaDirectory() async {
    final folder = await _syncFolder();
    if (folder == null) {
      throw PlatformException(code: 'folder', message: '尚未选择同步文件夹');
    }
    return Directory('${folder.path}${Platform.pathSeparator}Mikansei-sync')
        .create(recursive: true);
  }

  static bool validReplicaName(String name) =>
      RegExp(r'^replica-[a-zA-Z0-9-]+\.json$').hasMatch(name);

  Future<Object?> invoke(String method, [Object? arguments]) async {
    switch (method) {
      case 'appInfo':
        return version;
      case 'readArchive':
        return _readOptional(await _localFile('entries.json'));
      case 'writeArchive':
        await _writeAtomic(await _localFile('entries.json'), _text(arguments));
        return null;
      case 'importArchive':
      case 'importText':
        final path = await _openFile(method == 'importArchive');
        if (path == null) return null;
        final text = await File(path).readAsString();
        return text.startsWith('\uFEFF') ? text.substring(1) : text;
      case 'exportArchive':
        final text = _text(arguments);
        final path = await _saveFile();
        if (path == null) return false;
        await _writeAtomic(File(path), text);
        return true;
      case 'pickLocalSyncFolder':
        final path = await _pickFolder();
        if (path == null) return null;
        final folder = Directory(path);
        if (!await folder.exists()) {
          throw FileSystemException('所选文件夹不存在', path);
        }
        await _writeAtomic(
          await _localFile('local-sync-folder.json'),
          jsonEncode({'path': folder.absolute.path}),
        );
        return {
          'name': folder.uri.pathSegments.where((p) => p.isNotEmpty).last,
          'path': folder.absolute.path,
        };
      case 'localSyncFolder':
        try {
          final folder = await _syncFolder();
          if (folder == null) return {'connected': false};
          return {'connected': true, 'name': folder.path, 'path': folder.path};
        } catch (error) {
          return {'connected': false, 'error': '$error'};
        }
      case 'disconnectLocalSyncFolder':
        await _writeAtomic(await _localFile('local-sync-folder.json'), '{}');
        return null;
      case 'readLocalSyncFiles':
        final directory = await _replicaDirectory();
        final files = <String, String>{};
        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = entity.uri.pathSegments.last;
          if (!validReplicaName(name)) continue;
          files[name] = await entity.readAsString();
        }
        return files;
      case 'writeLocalSyncFile':
        if (arguments is! Map) {
          throw PlatformException(code: 'arguments', message: '缺少同步文件');
        }
        final name = _text(arguments['name']);
        if (!validReplicaName(name)) {
          throw PlatformException(code: 'arguments', message: '同步文件名无效');
        }
        final content = _text(arguments['content']);
        await _writeAtomic(_child(await _replicaDirectory(), name), content);
        return true;
      case 'readLocalSyncState':
        return _readOptional(await _localFile('local-sync-state.json'));
      case 'writeLocalSyncState':
        await _writeAtomic(
          await _localFile('local-sync-state.json'),
          _text(arguments),
        );
        return null;
      case 'openExternalURL':
        final uri = Uri.tryParse(_text(arguments));
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw PlatformException(code: 'arguments', message: '网址无效');
        }
        if (!await _openUrl(uri)) {
          throw PlatformException(code: 'unavailable', message: '无法打开浏览器');
        }
        return true;
      case 'takeRoutes':
        return <Object?>[];
      case 'reconcileServices':
        return null;
      case 'systemStatus':
        return {
          'supported': false,
          'notification': 'Windows 版尚未接入',
          'alarm': 'Windows 版尚未接入',
          'scheduled': 0,
        };
      case 'requestReminderAccess':
        return false;
      default:
        throw PlatformException(
          code: 'unsupported',
          message: 'Windows 版暂不支持此系统功能：$method',
        );
    }
  }
}
