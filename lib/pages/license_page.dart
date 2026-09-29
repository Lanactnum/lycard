import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../widgets/glass.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 开源许可页：MIT 协议全文 + 制作署名
class MitLicensePage extends StatefulWidget {
  const MitLicensePage({super.key});

  @override
  State<MitLicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<MitLicensePage> {
  String? _text;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/LICENSE.txt').then((s) {
      if (mounted) setState(() => _text = s);
    }).catchError((_) {
      if (mounted) setState(() => _text = _fallback);
    });
  }

  static const String _fallback = 'MIT License\n\n'
      'Copyright (c) 2026 镧锕Lanactnum的蓝色大肥鱼\n\n'
      'Permission is hereby granted, free of charge, to any person obtaining a copy '
      'of this software and associated documentation files (the "Software"), to deal '
      'in the Software without restriction...';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('开源许可'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.favorite, size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(tr('由镧锕Lanactnum的大肥鱼制作'),
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('lycard · Lycard',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(tr('以 MIT 协议开源'),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _text ?? tr('载入中…'),
            style: const TextStyle(fontSize: 12.5, height: 1.7),
          ),
        ],
      ),
    );
  }
}
