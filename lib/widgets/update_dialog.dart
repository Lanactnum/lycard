import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/apk_installer.dart';
import '../services/update_service.dart';

/// 「检查更新」发现新版后，**在应用内**下载并安装 —— 不跳浏览器。
///
/// 优先走**差分更新**：APK 里 86% 是内置卡图，而卡图在版本之间从不变化，
/// 所以只下十几 MB 的补丁就够了（实测 0.85.3→0.85.4 整包 573 MB、补丁 12.6 MB）。
/// 补丁对不上或应用失败会自动退回整包下载。
Future<void> showUpdateDialog(
  BuildContext context,
  AppUpdate update, {
  File? initialFile,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => UpdateDialog(update: update, initialFile: initialFile),
  );
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.update, this.initialFile});

  final AppUpdate update;

  /// 只给测试用：直接把目标文件递进来，跳过 path_provider 和建目录
  /// （widget test 跑在 FakeAsync 里，真实文件 IO 永远等不到，会挂满 10 分钟）。
  final File? initialFile;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final UpdateDownload _dl = UpdateDownload.instance;

  File? _file;
  Directory? _dir;
  File? _selfApk;
  bool _installing = false;
  bool _needPermission = false;
  String? _localError;

  int get _fullSize => widget.update.downloadSize ?? 0;
  int get _patchSize => widget.update.patchSize ?? 0;

  /// 能不能走差分：Release 挂了补丁，而且拿得到本机那个 APK
  bool get _canDelta => widget.update.patchUrl != null && _selfApk != null;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// 算好安装包落在哪个文件上（文件名自带版本号和 arm64/universal 标记），
  /// 顺便问一下本机已装的 APK 在哪（差分要用它当输入）。
  Future<void> _prepare() async {
    final injected = widget.initialFile;
    if (injected != null) {
      // 这一步在 initState 里同步跑到，直接赋字段 —— 在这里 setState 会报错
      _file = injected;
      return;
    }
    final name = widget.update.apkName.isEmpty
        ? 'lycard-${widget.update.latestVersion}.apk'
        : widget.update.apkName;
    try {
      final dir = await updateDir();
      final self = await ApkInstaller.apkPath();
      if (!mounted) return;
      setState(() {
        _dir = dir;
        _file = File('${dir.path}/$name');
        if (self != null) {
          final f = File(self);
          if (f.existsSync()) _selfApk = f;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _localError = tr('找不到可写目录：{0}', ['$e']));
    }
  }

  int get _have {
    final f = _file;
    if (f == null || !f.existsSync()) return 0;
    return f.lengthSync();
  }

  Future<void> _start() async {
    final f = _file;
    final dir = _dir;
    if (f == null || dir == null) return;
    setState(() => _localError = null);
    final out = await _dl.startUpdate(
      update: widget.update,
      dir: dir,
      apkFile: f,
      selfApk: _selfApk,
    );
    if (!mounted) return;
    if (out == null) {
      final e = _dl.error.value;
      if (e != null) setState(() => _localError = tr('下载失败：{0}', [e]));
      return;
    }
    await _install();
  }

  Future<void> _install() async {
    final f = _file;
    if (f == null) return;
    setState(() => _localError = null);
    final ok = await ApkInstaller.canInstall();
    if (!mounted) return;
    if (!ok) {
      setState(() => _needPermission = true);
      return;
    }
    setState(() => _installing = true);
    final launched = await ApkInstaller.install(f.path);
    if (!mounted) return;
    setState(() {
      _installing = false;
      if (!launched) _localError = tr('没拉起安装器，再点一次「安装」试试');
    });
  }

  static String _mb(num bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  static String _eta(int remain, double? speed) {
    if (speed == null || speed <= 0) return '';
    final s = (remain / speed).round();
    if (s < 60) return tr('还剩 {0} 秒', ['$s']);
    return tr('还剩 {0} 分 {1} 秒', ['${s ~/ 60}', '${s % 60}']);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return ValueListenableBuilder<bool>(
      valueListenable: _dl.running,
      builder: (context, running, _) => ValueListenableBuilder<UpdatePhase>(
        valueListenable: _dl.phase,
        builder: (context, phase, _) => ValueListenableBuilder<DownloadProgress?>(
          valueListenable: _dl.progress,
          builder: (context, live, _) {
            final have = _have;
            final isDelta = phase == UpdatePhase.downloadingPatch ||
                phase == UpdatePhase.applyingPatch;
            // 总量：差分时是补丁大小，整包时是包大小
            final total = isDelta
                ? (_patchSize > 0 ? _patchSize : (live?.total ?? 0))
                : (_fullSize > 0 ? _fullSize : (live?.total ?? 0));
            final received = running ? (live?.received ?? have) : have;
            final done = !running &&
                phase == UpdatePhase.idle &&
                _fullSize > 0 &&
                have >= _fullSize;

            return AlertDialog(
              title: Text('lycard ${widget.update.latestVersion}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _canDelta && _patchSize > 0
                        ? tr('差分更新：只下 {0}（完整包 {1}）',
                            [_mb(_patchSize), _mb(_fullSize)])
                        : (_fullSize > 0
                            ? tr('完整更新：{0}', [_mb(_fullSize)])
                            : tr('正在获取安装包信息…')),
                  ),
                  if (phase == UpdatePhase.applyingPatch) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    Text(tr('正在拼出新安装包…（本地运算，几秒）'), style: small),
                  ] else if (running && received > 0) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: total > 0 ? received / total : null,
                    ),
                    const SizedBox(height: 6),
                    ValueListenableBuilder<double?>(
                      valueListenable: _dl.speed,
                      builder: (context, sp, _) {
                        final line = <String>[
                          '${_mb(received)} / ${_mb(total)}',
                          if (sp != null && sp > 0) '${_mb(sp)}/s',
                          if (total > 0) _eta(total - received, sp),
                        ].where((e) => e.isNotEmpty).join(' · ');
                        return Text(line, style: small);
                      },
                    ),
                  ],
                  if (done) ...[
                    const SizedBox(height: 8),
                    Text(
                      _installing
                          ? tr('正在交给系统安装器…')
                          : tr('已经下好了，点「安装」就能装'),
                    ),
                  ],
                  if (_needPermission) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr('要在系统设置里允许 lycard 安装应用，才能装这个包。'),
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                  if (_localError != null) ...[
                    const SizedBox(height: 8),
                    Text(_localError!, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String?>(
                    valueListenable: _dl.deltaNote,
                    builder: (context, note, _) => note == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(note, style: small),
                          ),
                  ),
                  Text(
                    tr('关掉这个窗口也不会中断，回「关于」页能接着看进度。'),
                    style: small,
                  ),
                ],
              ),
              actions: [
                if (done)
                  TextButton(
                    onPressed: _installing ? null : _install,
                    child: Text(tr('安装')),
                  )
                else if (running)
                  TextButton(
                    onPressed: _dl.cancel,
                    child: Text(tr('暂停')),
                  )
                else if (_file != null && widget.update.downloadUrl != null)
                  TextButton(
                    onPressed: _start,
                    child: Text(have > 0 ? tr('继续更新') : tr('开始更新')),
                  ),
                if (_needPermission)
                  TextButton(
                    onPressed: () async {
                      await ApkInstaller.openInstallSettings();
                      if (!mounted) return;
                      // 回来看一眼权限开没开，开了就直接装
                      if (await ApkInstaller.canInstall()) await _install();
                    },
                    child: Text(tr('去开安装权限')),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('关闭')),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
