import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lycee_app/services/apk_installer.dart';
import 'package:crypto/crypto.dart';
import 'package:lycee_app/services/delta_patch.dart';
import 'package:lycee_app/services/update_service.dart';
import 'package:lycee_app/widgets/update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 应用内更新（检查 → 下载 → 安装）的测试。
///
/// 这一块最容易踩的两个坑都钉在这里：
/// ① Release 里同时挂 arm64 和全架构包时，GitHub 按**文件名**排序，
///    只取「第一个 .apk」会挑到不该装的那个；
/// ② 断点续传拼错一个字节，装上去就是坏的 —— 宁可报错也不能糊弄。

String? _hdr(http.BaseRequest r, String name) {
  for (final MapEntry<String, String> e in r.headers.entries) {
    if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
  }
  return null;
}

http.StreamedResponse _resp(
  List<List<int>> chunks,
  int status, {
  int? contentLength,
}) =>
    http.StreamedResponse(
      Stream<List<int>>.fromIterable(chunks),
      status,
      contentLength: contentLength,
    );

AppUpdate _mk(String latest, String current) => AppUpdate(
      currentVersion: current,
      latestVersion: latest,
      releaseUrl: Uri.parse('https://example.com/release'),
      downloadUrl: null,
      apkName: '',
      downloadSize: null,
      notes: '',
      publishedAt: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本比较', () {
    test('比当前新才算新版本', () {
      expect(_mk('0.85.4', '0.85.3').isNewer, isTrue);
      expect(_mk('0.85.3', '0.85.3').isNewer, isFalse);
      expect(_mk('0.85.2', '0.85.3').isNewer, isFalse);
      expect(_mk('0.86.0', '0.85.3').isNewer, isTrue);
      expect(_mk('0.85.10', '0.85.9').isNewer, isTrue, reason: '10 > 9，不能按字符串比');
    });
  });

  group('按架构挑安装包', () {
    final assets = <Map<String, dynamic>>[
      {
        'name': 'lycard-0.85.4-universal.apk',
        'size': 646089269,
        'browser_download_url': 'https://x/u.apk',
      },
      {
        'name': 'lycard-0.85.4-arm64.apk',
        'size': 601327899,
        'browser_download_url': 'https://x/a.apk',
      },
      {
        'name': 'lycard-0.85.4-arm64.apk.sha256',
        'size': 90,
        'browser_download_url': 'https://x/a.sha256',
      },
    ];

    test('arm64 机器挑 arm64 包（哪怕 universal 按文件名排在前面）', () {
      expect(
        pickApk(assets, abiToken: 'arm64')['name'],
        'lycard-0.85.4-arm64.apk',
      );
    });

    test('32 位 / x86 机器挑全架构包', () {
      expect(
        pickApk(assets, abiToken: 'universal')['name'],
        'lycard-0.85.4-universal.apk',
      );
    });

    test('架构认不出来时退回第一个 .apk', () {
      expect(
        pickApk(assets, abiToken: null, defaultToDeviceAbi: false)['name'],
        'lycard-0.85.4-universal.apk',
      );
    });

    test('sha256 附件不会被当成安装包', () {
      final picked = '${pickApk(assets, abiToken: 'arm64')['name']}';
      expect(picked, endsWith('.apk'));
      expect(picked, isNot(contains('sha256')));
    });

    test('一个 apk 附件都没有时返回空', () {
      expect(
        pickApk(<Map<String, dynamic>>[
          {'name': 'lycee_cards.pack.part01'},
        ], abiToken: 'arm64'),
        isEmpty,
      );
    });
  });

  group('检查更新（对着假的 GitHub 响应）', () {
    setUpAll(() {
      PackageInfo.setMockInitialValues(
        appName: 'lycard',
        packageName: 'com.lycard.app',
        version: '0.85.3',
        buildNumber: '96',
        buildSignature: '',
      );
    });

    Map<String, dynamic> releaseJson() => <String, dynamic>{
          'tag_name': 'v0.85.4',
          'html_url': 'https://github.com/Lanactnum/lycard-updates/releases/tag/v0.85.4',
          'body': '应用内更新：下载完直接装',
          'published_at': '2026-09-30T12:00:00Z',
          'assets': [
            {
              'name': 'lycard-0.85.4-universal.apk',
              'size': 646089269,
              'browser_download_url': 'https://x/u.apk',
            },
            {
              'name': 'lycard-0.85.4-arm64.apk',
              'size': 601327899,
              'browser_download_url': 'https://x/a.apk',
            },
          ],
        };

    test('解析版本 / 备注 / 大小，并按架构挑对包', () async {
      final client = MockClient((http.Request req) async {
        expect(
          req.url.path,
          '/repos/Lanactnum/lycard-updates/releases/latest',
        );
        return http.Response.bytes(
          utf8.encode(jsonEncode(releaseJson())),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final result =
          await UpdateService.instance.check(client: client, abiToken: 'arm64');
      expect(result.hasUpdate, isTrue);
      final u = result.update!;
      expect(u.latestVersion, '0.85.4');
      expect(u.currentVersion, '0.85.3');
      expect(u.apkName, 'lycard-0.85.4-arm64.apk');
      expect(u.downloadSize, 601327899);
      expect(u.notes, contains('应用内更新'));
      expect(u.publishedAt, isNotNull);
    });

    test('tag 没变新时 hasUpdate = false', () async {
      final json = releaseJson()..['tag_name'] = 'v0.85.3';
      final client = MockClient(
        (http.Request req) async => http.Response.bytes(
          utf8.encode(jsonEncode(json)),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      );
      final result =
          await UpdateService.instance.check(client: client, abiToken: 'arm64');
      expect(result.hasUpdate, isFalse);
    });

    test('404 时给出「暂无可用更新」，不当成错误', () async {
      final client = MockClient(
        (http.Request req) async => http.Response('{}', 404),
      );
      final result = await UpdateService.instance.check(client: client);
      expect(result.update, isNull);
      expect(result.message, '暂无可用更新');
    });

    test('其它 HTTP 错误要抛出来（界面提示检查失败）', () async {
      final client = MockClient(
        (http.Request req) async => http.Response('boom', 500),
      );
      await expectLater(
        UpdateService.instance.check(client: client),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('应用内下载', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lycard_update_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('一次下完：字节一模一样，进度只增不减', () async {
      final data = List<int>.generate(300000, (i) => i % 251);
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async => _resp(
          <List<int>>[data.sublist(0, 100000), data.sublist(100000)],
          200,
          contentLength: data.length,
        ),
      );
      final target = File('${tmp.path}/a.apk');
      final seen = <DownloadProgress>[];
      final out = await downloadApk(
        url: Uri.parse('https://x/a.apk'),
        target: target,
        client: client,
        onProgress: seen.add,
      );
      expect(out, isNotNull);
      expect(await target.readAsBytes(), equals(data));
      expect(seen, isNotEmpty);
      expect(seen.first.isComplete, isFalse);
      expect(seen.last.isComplete, isTrue);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].received, greaterThanOrEqualTo(seen[i - 1].received));
      }
    });

    test('断点续传：带 Range 头，接在已经下过的那一段后面', () async {
      final data = List<int>.generate(400000, (i) => (i * 7) % 256);
      final target = File('${tmp.path}/b.apk');
      await target.writeAsBytes(data.sublist(0, 123456));
      String? range;
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async {
          range = _hdr(req, 'range');
          final from = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(range!)!.group(1)!,
          );
          return _resp(
            <List<int>>[data.sublist(from)],
            206,
            contentLength: data.length - from,
          );
        },
      );
      final seen = <DownloadProgress>[];
      final out = await downloadApk(
        url: Uri.parse('https://x/b.apk'),
        target: target,
        client: client,
        onProgress: seen.add,
      );
      expect(range, 'bytes=123456-');
      expect(out, isNotNull);
      expect(await target.readAsBytes(), equals(data), reason: '既不能少字节，也不能把内容拼成双份');
      expect(seen.first.resumedFrom, 123456);
    });

    test('服务端不支持续传（回 200）时从头下，不拼成双份', () async {
      final data = List<int>.generate(50000, (i) => i % 97);
      final target = File('${tmp.path}/c.apk');
      await target.writeAsBytes(data.sublist(0, 5000));
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async =>
            _resp(<List<int>>[data], 200, contentLength: data.length),
      );
      await downloadApk(
        url: Uri.parse('https://x/c.apk'),
        target: target,
        client: client,
      );
      expect(await target.readAsBytes(), equals(data));
    });

    test('暂停：返回 null，已下的那一段留在磁盘上等着续', () async {
      final data = List<int>.generate(600000, (i) => i % 200);
      final target = File('${tmp.path}/d.apk');
      var got = 0;
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async => _resp(
          <List<int>>[data.sublist(0, 300000), data.sublist(300000)],
          200,
          contentLength: data.length,
        ),
      );
      final out = await downloadApk(
        url: Uri.parse('https://x/d.apk'),
        target: target,
        client: client,
        isCancelled: () => got > 0,
        onProgress: (DownloadProgress p) => got = p.received,
      );
      expect(out, isNull);
      expect(target.existsSync(), isTrue);
      expect(target.lengthSync(), greaterThan(0));
      expect(target.lengthSync(), lessThan(data.length));
    });

    test('下短了必须报错，不能拿半个包糊弄', () async {
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async =>
            _resp(<List<int>>[
              <int>[1, 2, 3, 4, 5],
            ], 200, contentLength: 100),
      );
      await expectLater(
        downloadApk(
          url: Uri.parse('https://x/e.apk'),
          target: File('${tmp.path}/e.apk'),
          client: client,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('HTTP 404 直接抛错', () async {
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async =>
            _resp(<List<int>>[], 404),
      );
      await expectLater(
        downloadApk(
          url: Uri.parse('https://x/f.apk'),
          target: File('${tmp.path}/f.apk'),
          client: client,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('416（区间不存在）当成已经下全', () async {
      final target = File('${tmp.path}/g.apk');
      await target.writeAsBytes(List<int>.filled(50, 7));
      final client = MockClient.streaming(
        (http.BaseRequest req, http.ByteStream body) async =>
            _resp(<List<int>>[], 416),
      );
      final out = await downloadApk(
        url: Uri.parse('https://x/g.apk'),
        target: target,
        client: client,
      );
      expect(out, isNotNull);
      expect(target.lengthSync(), 50);
    });
  });

  group('安装通道（Android 侧）', () {
    const MethodChannel channel = MethodChannel('lycard/update');
    final calls = <MethodCall>[];

    void handler(Future<Object?> Function(MethodCall) fn) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        calls.add(call);
        return fn(call);
      });
    }

    setUp(calls.clear);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('装的时候把文件路径交给原生', () async {
      handler((MethodCall call) async => switch (call.method) {
            'canInstall' => true,
            'openInstallSettings' => true,
            'install' => true,
            _ => null,
          });
      const String path =
          '/storage/emulated/0/Android/data/com.lycard.app/files/update/lycard-0.85.4-arm64.apk';
      expect(await ApkInstaller.canInstall(), isTrue);
      expect(await ApkInstaller.install(path), isTrue);
      expect(calls.last.method, 'install');
      expect(calls.last.arguments['path'], path);
    });

    test('权限没开时如实说 false（面板据此提示去开）', () async {
      handler((MethodCall call) async => false);
      expect(await ApkInstaller.canInstall(), isFalse);
      expect(await ApkInstaller.install('/x.apk'), isFalse);
    });

    test('原生报错时返回 false，不把异常甩到界面上', () async {
      handler((MethodCall call) async =>
          throw PlatformException(code: 'boom'));
      expect(await ApkInstaller.install('/x.apk'), isFalse);
      expect(await ApkInstaller.canInstall(), isFalse);
      expect(await ApkInstaller.openInstallSettings(), isFalse);
    });
  });

  group('更新面板', () {
    // ⚠ 这条**绝不能碰真实磁盘**：testWidgets 跑在 FakeAsync 时钟下，
    // `await Directory.systemTemp.createTemp(...)` 这种真实 IO 永远不会返回，
    // 测试会在第一行就死等（实测挂满 10 分钟，整轮测试看着像卡死）。
    // 用一个「不需要存在」的路径就够了 —— 面板只读它的长度，不读内容。
    final File target = File(
      r'C:/lycard_test_no_such_dir/lycard-0.85.4-arm64.apk',
    );

    AppUpdate buildUpdate() => AppUpdate(
          currentVersion: '0.85.3',
          latestVersion: '0.85.4',
          releaseUrl: Uri.parse('https://example.com/r'),
          downloadUrl: Uri.parse('https://example.com/x.apk'),
          apkName: 'lycard-0.85.4-arm64.apk',
          downloadSize: 104857600,
          notes: '',
          publishedAt: null,
        );

    testWidgets(
      '面板里就是下载 / 安装，不再跳浏览器',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(home: UpdateDialog(update: buildUpdate(), initialFile: target)),
        );
        await tester.pump();

        expect(find.text('lycard 0.85.4'), findsOneWidget);
        expect(find.text('完整更新：100.0 MB'), findsOneWidget);
        expect(find.text('开始更新'), findsOneWidget);
        expect(find.text('关闭'), findsOneWidget);
        // 这次改动的核心：更新全程留在应用内 —— 不再有「用浏览器打开」那个外链图标
        expect(find.byIcon(Icons.open_in_new), findsNothing);
        expect(find.textContaining('关掉这个窗口也不会中断'), findsOneWidget);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      '已经下好的包：面板直接给「安装」，不再显示「开始下载」',
      (WidgetTester tester) async {
        final File half = File(r'C:/lycard_test_no_such_dir/half.apk');
        await tester.pumpWidget(
          MaterialApp(
            home: UpdateDialog(update: buildUpdate(), initialFile: half),
          ),
        );
        await tester.pump();
        // 文件不存在 → 一个字节都没下 → 给的是「开始更新」
        expect(find.text('开始更新'), findsOneWidget);
        expect(find.text('安装'), findsNothing);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
  group('差分更新', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lycard_delta_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('按「从哪个版本升」挑补丁，架构也要对得上', () {
      final assets = <Map<String, dynamic>>[
        {
          'name': 'lycard-0.85.5-arm64.apk',
          'size': 601000000,
          'browser_download_url': 'https://x/a.apk',
        },
        {
          'name': 'lycard-0.85.5-arm64.apk.from-0.85.3.lycpatch',
          'size': 20000000,
          'browser_download_url': 'https://x/p3.lycpatch',
        },
        {
          'name': 'lycard-0.85.5-arm64.apk.from-0.85.4.lycpatch',
          'size': 13208782,
          'browser_download_url': 'https://x/p4.lycpatch',
        },
        {
          'name': 'lycard-0.85.5-universal.apk.from-0.85.4.lycpatch',
          'size': 14000000,
          'browser_download_url': 'https://x/pu.lycpatch',
        },
      ];
      // 本机 0.85.4 + arm64 → 只认那个 arm64 的 0.85.4 补丁
      final p = pickPatch(assets, from: '0.85.4', abiToken: 'arm64');
      expect(p['name'], 'lycard-0.85.5-arm64.apk.from-0.85.4.lycpatch');
      // 全架构机器 → 拿 universal 的
      expect(
        pickPatch(assets, from: '0.85.4', abiToken: 'universal')['name'],
        'lycard-0.85.5-universal.apk.from-0.85.4.lycpatch',
      );
      // 本机版本没有对应补丁 → 空（那就老实下整包）
      expect(pickPatch(assets, from: '0.85.1', abiToken: 'arm64'), isEmpty);
      // 一个补丁都没有 → 空
      expect(
        pickPatch(<Map<String, dynamic>>[
          {'name': 'lycard-0.85.5-arm64.apk'},
        ], from: '0.85.4', abiToken: 'arm64'),
        isEmpty,
      );
    });

    test('应用补丁：复制段 + 新内容段拼出来，且核对哈希', () async {
      final oldData = List<int>.generate(200000, (i) => (i * 13) % 256);
      final newData = <int>[
        ...oldData.sublist(0, 50000),
        ...List<int>.generate(777, (i) => 200 + i % 55), // 新内容
        ...oldData.sublist(50000, 150000),
      ];
      final oldApk = File('${tmp.path}/old.apk');
      final patchFile = File('${tmp.path}/u.lycpatch');
      final out = File('${tmp.path}/new.apk');
      await oldApk.writeAsBytes(oldData);
      await patchFile.writeAsBytes(
        buildTestPatch(
          fromSize: oldData.length,
          toBytes: newData,
          ops: <void Function(TestPatchBuilder)>[
            (TestPatchBuilder b) => b.copy(0, 50000),
            (TestPatchBuilder b) => b.literal(
                List<int>.generate(777, (i) => 200 + i % 55)),
            (TestPatchBuilder b) => b.copy(50000, 100000),
          ],
        ),
      );

      final info = await DeltaPatch.readInfo(patchFile);
      expect(info, isNotNull);
      expect(info!.fromSize, oldData.length);
      expect(info.toSize, newData.length);

      await DeltaPatch.apply(oldApk: oldApk, patch: patchFile, out: out);
      expect(await out.readAsBytes(), equals(newData));
    });

    test('旧包大小对不上：直接拒绝，不许瞎拼', () async {
      final patchFile = File('${tmp.path}/u.lycpatch');
      await patchFile.writeAsBytes(buildTestPatch(
        fromSize: 999999,
        toBytes: <int>[1, 2, 3],
        ops: <void Function(TestPatchBuilder)>[
          (TestPatchBuilder b) => b.literal(<int>[1, 2, 3]),
        ],
      ));
      final wrongOld = File('${tmp.path}/wrong.apk');
      await wrongOld.writeAsBytes(<int>[0, 0, 0]);
      await expectLater(
        DeltaPatch.apply(
          oldApk: wrongOld,
          patch: patchFile,
          out: File('${tmp.path}/o.apk'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('拼出来的哈希不符：必须报错，不能拿半成品去装', () async {
      final oldData = List<int>.generate(1000, (i) => i % 256);
      final oldApk = File('${tmp.path}/old2.apk');
      await oldApk.writeAsBytes(oldData);
      final patchFile = File('${tmp.path}/bad.lycpatch');
      // 故意写一个错的哈希
      await patchFile.writeAsBytes(buildTestPatch(
        fromSize: oldData.length,
        toBytes: oldData,
        shaOverride: 'f' * 64,
        ops: <void Function(TestPatchBuilder)>[
          (TestPatchBuilder b) => b.copy(0, oldData.length),
        ],
      ));
      await expectLater(
        DeltaPatch.apply(
          oldApk: oldApk,
          patch: patchFile,
          out: File('${tmp.path}/o2.apk'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('头不对的补丁：读信息返回 null，应用会拒绝', () async {
      final bad = File('${tmp.path}/notapatch.bin');
      await bad.writeAsBytes(List<int>.filled(80, 7));
      expect(await DeltaPatch.readInfo(bad), isNull);
    });

    test('取消：抛 DeltaPatchCancelled，写了一半的输出要删掉', () async {
      final oldData = List<int>.generate(300000, (i) => i % 256);
      final oldApk = File('${tmp.path}/old3.apk');
      await oldApk.writeAsBytes(oldData);
      final patchFile = File('${tmp.path}/big.lycpatch');
      await patchFile.writeAsBytes(buildTestPatch(
        fromSize: oldData.length,
        toBytes: oldData,
        ops: <void Function(TestPatchBuilder)>[
          (TestPatchBuilder b) => b.copy(0, oldData.length),
        ],
      ));
      final out = File('${tmp.path}/o3.apk');
      var calls = 0;
      await expectLater(
        DeltaPatch.apply(
          oldApk: oldApk,
          patch: patchFile,
          out: out,
          isCancelled: () => ++calls > 1,
        ),
        throwsA(isA<DeltaPatchCancelled>()),
      );
      expect(out.existsSync(), isFalse, reason: '半成品不能留在磁盘上');
    });
  });

  group('更新完清理更新包', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lycard_clean_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('装上的版本、躺太久的残包都清掉；正在用的留着', () async {
      final dir = Directory('${tmp.path}/update')..createSync(recursive: true);
      final old = File('${dir.path}/lycard-0.85.4-arm64.apk')
        ..writeAsBytesSync(List<int>.filled(1000, 1));
      final patch = File('${dir.path}/lycard-0.85.5-arm64.apk.from-0.85.4.lycpatch')
        ..writeAsBytesSync(List<int>.filled(2000, 2));
      final stale = File('${dir.path}/lycard-0.99.0-arm64.apk')
        ..writeAsBytesSync(List<int>.filled(3000, 3));
      // 假装这个残包是 30 天前下到一半留下的
      stale.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 30)),
      );
      final keep = File('${dir.path}/lycard-0.85.5-arm64.apk')
        ..writeAsBytesSync(List<int>.filled(4000, 4));

      final freed =
          await cleanUpdateDir(currentVersion: '0.85.4', dir: dir);

      expect(old.existsSync(), isFalse, reason: '0.85.4 已经装上了，包没用了');
      expect(patch.existsSync(), isTrue, reason: '补丁是新版的，可能还要用');
      expect(stale.existsSync(), isFalse, reason: '躺了 30 天没人管，清掉');
      expect(keep.existsSync(), isTrue, reason: '新版本包，留着装');
      expect(freed, 4000);
    });
  });

  group('「下好了」的判定（别让用户下完了却装不了）', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lycard_done_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('下载成功才记 completed，重新开始时清掉', () async {
      final dl = UpdateDownload.instance;
      final out = File('${tmp.path}/lycard-0.85.5-arm64.apk');
      final body = List<int>.filled(4096, 7);
      final client = MockClient(
        (http.Request req) async => http.Response.bytes(
          body,
          200,
          headers: <String, String>{'content-length': '${body.length}'},
        ),
      );

      dl.completed.value = null;
      final r = await dl.downloadFull(
        url: Uri.parse('https://x/a.apk'),
        file: out,
        expectedSize: body.length,
        client: client,
      );
      expect(r, isNotNull);
      expect(dl.completed.value?.path, out.path, reason: '下完了要记上');
      expect(out.lengthSync(), body.length);

      // 服务端报错 → 这次不算完成，不能还留着上一次的标记
      final bad = MockClient(
        (http.Request req) async => http.Response('nope', 500),
      );
      final r2 = await dl.downloadFull(
        url: Uri.parse('https://x/a.apk'),
        file: File('${tmp.path}/other.apk'),
        expectedSize: 4096,
        client: bad,
      );
      expect(r2, isNull);
      expect(dl.completed.value, isNull, reason: '失败要把标记清掉，免得界面显示「已经下好了」');
    });
  });
}

/// 造一个差分补丁（和 tools/make_delta.py 的格式一致），给测试用。
Uint8List buildTestPatch({
  required int fromSize,
  required List<int> toBytes,
  required List<void Function(TestPatchBuilder)> ops,
  String? shaOverride,
}) {
  final b = TestPatchBuilder();
  for (final op in ops) {
    op(b);
  }
  return b.build(fromSize: fromSize, toBytes: toBytes, shaOverride: shaOverride);
}

class TestPatchBuilder {
  final List<int> _body = <int>[];

  static Uint8List _varint(int n) {
    final out = <int>[];
    var v = n;
    while (true) {
      final b = v & 0x7F;
      v >>= 7;
      if (v != 0) {
        out.add(b | 0x80);
      } else {
        out.add(b);
        return Uint8List.fromList(out);
      }
    }
  }

  static Uint8List _u32(int n) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, n, Endian.little);

  /// 从旧包 [oldOff] 开始复制 [len] 字节
  void copy(int oldOff, int len) {
    _body.addAll(_varint(1));
    _body.addAll(_varint(oldOff));
    _body.addAll(_varint(len));
  }

  /// 直接写入新内容
  void literal(List<int> data) {
    _body.addAll(_varint(2));
    _body.addAll(_varint(data.length));
    _body.addAll(data);
  }

  Uint8List build({
    required int fromSize,
    required List<int> toBytes,
    String? shaOverride,
  }) {
    _body.add(0); // 结束
    final sha = shaOverride != null
        ? List<int>.generate(
            32, (i) => int.parse(shaOverride.substring(i * 2, i * 2 + 2), radix: 16))
        : sha256.convert(toBytes).bytes;
    return Uint8List.fromList(<int>[
      ...'LYCDELTA1'.codeUnits,
      ..._u32(fromSize),
      ..._u32(toBytes.length),
      ...sha,
      ...gzip.encode(_body),
    ]);
  }
}
