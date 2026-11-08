import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/image_store.dart';

const List<Color> _placeholderColors = [
  Color(0xFFB2DFDB), Color(0xFFC5CAE9), Color(0xFFFFCCBC), Color(0xFFFFE0B2),
  Color(0xFFD1C4E9), Color(0xFFB3E5FC), Color(0xFFDCEDC8), Color(0xFFF8BBD0),
];

Color placeholderColorFor(String name) =>
    _placeholderColors[name.hashCode.abs() % _placeholderColors.length];

/// Product photo (file image) or a friendly colored placeholder with the
/// product initial. Works for product images and the store logo.
class ProductImage extends StatelessWidget {
  final String? relativePath;
  final String name;
  final double size;
  final double radius;
  final BoxFit fit;

  const ProductImage({
    super.key,
    this.relativePath,
    required this.name,
    required this.size,
    this.radius = 14,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = Container(
      width: size,
      height: size,
      color: placeholderColorFor(name),
      alignment: Alignment.center,
      child: Text(
        name.trim().isEmpty ? '؟' : name.trim().characters.first,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.95),
        ),
      ),
    );

    if (relativePath == null || relativePath!.isEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(radius), child: placeholder);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: FutureBuilder<Directory>(
        future: ImageStore.docs(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return SizedBox(width: size, height: size, child: placeholder);
          }
          final file = File(p.join(snap.data!.path, relativePath!));
          return Image.file(
            file,
            width: size,
            height: size,
            fit: fit,
            errorBuilder: (_, _, _) => placeholder,
          );
        },
      ),
    );
  }
}
