import 'dart:io';
import 'package:flutter/material.dart';

/// Reusable Store Logo Avatar that renders either a local file image,
/// a network URL, or a graceful retail fallback icon.
class StoreLogoAvatar extends StatelessWidget {
  final String? logoUrl;
  final double size;
  final double radius;
  final IconData fallbackIcon;
  final Color? fallbackBgColor;
  final Color? fallbackIconColor;
  final Border? border;

  const StoreLogoAvatar({
    super.key,
    this.logoUrl,
    this.size = 34,
    this.radius = 10,
    this.fallbackIcon = Icons.storefront_rounded,
    this.fallbackBgColor,
    this.fallbackIconColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    Widget? imageWidget;

    if (logoUrl != null && logoUrl!.trim().isNotEmpty) {
      final path = logoUrl!.trim();
      if (path.startsWith('http://') || path.startsWith('https://')) {
        imageWidget = Image.network(
          path,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildFallback(),
        );
      } else {
        final file = File(path);
        if (file.existsSync()) {
          imageWidget = Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => _buildFallback(),
          );
        }
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fallbackBgColor ?? const Color(0xFF0B1528),
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: const Color(0xFF1E293B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageWidget ?? _buildFallback(),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Icon(
        fallbackIcon,
        size: size * 0.52,
        color: fallbackIconColor ?? const Color(0xFFF59E0B),
      ),
    );
  }
}
